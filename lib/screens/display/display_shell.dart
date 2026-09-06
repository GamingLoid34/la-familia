import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../providers/family_provider.dart';
import '../../utils/web_reload.dart';
import 'display_config_source.dart';
import 'display_controller.dart';
import 'display_layouts.dart';
import 'display_log.dart';
import 'display_module_registry.dart';
import 'display_scene_models.dart';
import 'display_theme.dart';

/// Beslut för tick-hoppsdetektorn (FAS 2.2 Beslut 1).
enum TickJumpDecision {
  normal,
  jumpWithoutMissedReload,
  jumpWithMissedReload,
}

/// Utvärderar om ett tidssteg mellan två minutpulser utgör ett tick-hopp (> 90 s)
/// samt om en schemalagd omladdningstid passerades under hoppet.
TickJumpDecision evaluateTickJump({
  required DateTime lastTick,
  required DateTime currentTick,
  required DateTime? scheduledReload,
}) {
  final diff = currentTick.difference(lastTick);
  if (diff.inSeconds <= 90) {
    return TickJumpDecision.normal;
  }
  if (scheduledReload != null &&
      !scheduledReload.isAfter(currentTick) &&
      scheduledReload.isAfter(lastTick)) {
    return TickJumpDecision.jumpWithMissedReload;
  }
  return TickJumpDecision.jumpWithoutMissedReload;
}

/// Avgör om en resume-händelse ska hanteras (max en per 30 sekunder) (FAS 3.1).
/// Resumes inom 30 sekunder från senaste hanterade resume koalesceras.
bool shouldHandleResume({
  required DateTime now,
  required DateTime? lastHandledResume,
  Duration minInterval = const Duration(seconds: 30),
}) {
  if (lastHandledResume == null) return true;
  return now.difference(lastHandledResume) >= minInterval;
}

/// Huvud-orkestrator för Storskärmsläget (FAS 1, 1.1, 2 & 2.2).
/// - Central DisplayController för kommandostyrning (tangentbord, Stream Deck, scener)
/// - Tangentbordslyssnare med 150 ms debounce och fokusvakt
/// - Sömn-medveten minutpuls och tick-hoppsdetektor (> 90 s)
/// - Omladdningsdisciplin vid väckningsstorm (60 s lugn före omladdning)
/// - Telemetrilogg och debug-overlay (tangent D)
/// - Växlar mellan Nattläge och Veckotavlan med stöd för nattöverstyrning
/// - Auto-hem till aktuell vecka efter 60 sekunder
/// - Kvittenspill nere till vänster
///
/// Test-overrides (aktiva ENDAST vid ?display=1 på webben):
/// - ?testNight=1      → Tvingar nattvyn oavsett klockslag.
/// - ?testReloadMin=N  → Schemalägger självomladdningen N minuter framåt istället
///                       för kl 03:00. Vid utlösning navigeras till samma URL
///                       utan testReloadMin (via location.replace) för att undvika loop.
class DisplayShell extends StatefulWidget {
  const DisplayShell({super.key});

  @override
  State<DisplayShell> createState() => _DisplayShellState();
}

class _DisplayShellState extends State<DisplayShell>
    with WidgetsBindingObserver {
  late final DisplayController _controller;
  late final FocusNode _focusNode;

  DateTime _now = DateTime.now();
  late DateTime _weekStart;
  DateTime _lastTickTime = DateTime.now();
  DateTime _lastKeyPressTime = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? _scheduledReloadTarget;
  int _weatherRefreshEpoch = 0;
  DateTime? _lastHandledResume;

  Timer? _minuteTimer;
  Timer? _reloadTimer;
  Timer? _pendingStormReloadTimer;
  Timer? _cursorHideTimer;
  bool _cursorVisible = false;
  DateTime _lastCursorArmTime = DateTime.fromMillisecondsSinceEpoch(0);

  DisplayConfigSource? _configSource;
  String? _currentFamilyId;

  bool get _isDisplayMode =>
      kIsWeb && Uri.base.queryParameters['display'] == '1';

  bool get _isTestNight =>
      _isDisplayMode && Uri.base.queryParameters['testNight'] == '1';

  int? get _testReloadMin {
    if (!_isDisplayMode) return null;
    final val = Uri.base.queryParameters['testReloadMin'];
    return val != null ? int.tryParse(val) : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = DisplayController(
      nowProvider: () => _now,
      configProvider: () =>
          _configSource?.config ?? DisplayConfig.defaultConfig(),
    );
    _controller.addListener(_onControllerChanged);

    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);

    _lastTickTime = DateTime.now();
    _weekStart = _computeWeekMonday(_now);
    _scheduleNextMinute();
    _scheduleNightReload();

    DisplayLog.instance.log(
      'lifecycle/resume',
      'DisplayShell startad (v${DisplayLog.appVersion})',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (!shouldHandleResume(now: now, lastHandledResume: _lastHandledResume)) {
        DisplayLog.instance.log(
          'lifecycle/resume (koalescerad)',
          'Resume inom 30s-fönster — ignoreras',
        );
        return;
      }
      _lastHandledResume = now;
      DisplayLog.instance.log(
        'lifecycle/resume',
        'App återupptagen från bakgrund/vila (AppLifecycleState.resumed)',
      );
      if (mounted) {
        context.read<FamilyProvider>().ensureDateSubscriptionsFresh(force: true);
        setState(() => _weatherRefreshEpoch++);
      }
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    // Fokusvakt: vid fokusförlust begär vi omedelbart tillbaka fokus
    if (!_focusNode.hasFocus && mounted) {
      _focusNode.requestFocus();
    }
  }

  DateTime _computeWeekMonday(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day - (dt.weekday - 1));
  }

  void _scheduleNextMinute() {
    _minuteTimer?.cancel();
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
      0,
      50,
    );
    final delay = nextMinute.difference(now);
    _minuteTimer = Timer(delay, () {
      if (!mounted) return;
      final current = DateTime.now();
      final decision = evaluateTickJump(
        lastTick: _lastTickTime,
        currentTick: current,
        scheduledReload: _scheduledReloadTarget,
      );

      // Tick-hoppsdetektor (FAS 2.2 Beslut 1)
      if (decision != TickJumpDecision.normal) {
        final diffSec = current.difference(_lastTickTime).inSeconds;
        DisplayLog.instance.log(
          'tick-hopp',
          'Tick-hopp detekterat: ${diffSec}s (från $_lastTickTime till $current)',
        );

        // Kör fokusvakten
        if (!_focusNode.hasFocus && mounted) {
          _focusNode.requestFocus();
        }

        // Koalescerad resync från providern
        if (mounted) {
          context
              .read<FamilyProvider>()
              .ensureDateSubscriptionsFresh(force: true);
        }

        // Trigga väderuppdatering
        _weatherRefreshEpoch++;

        // Omladdningsdisciplin vid väckningsstorm
        if (decision == TickJumpDecision.jumpWithMissedReload) {
          DisplayLog.instance.log(
            'omladdningsbeslut',
            'Schemalagd omladdningstid passerades under sömn — skjuter upp 60s för att undvika väckningsstorm',
          );
          _pendingStormReloadTimer?.cancel();
          _pendingStormReloadTimer = Timer(const Duration(seconds: 60), () {
            DisplayLog.instance.log(
              'omladdningsbeslut',
              '60s lugn efter uppvaknande uppnådd — utför omladdning',
            );
            _performReload();
          });
        } else {
          _scheduleNightReload();
        }
      }

      _lastTickTime = current;

      // Fokusvakt på varje minutskifte
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }

      // Schemagränskontroll för nattöverstyrning
      _controller.checkScheduleBoundary(current);

      final newMonday = _computeWeekMonday(current);
      setState(() {
        _now = current;
        if (newMonday.year != _weekStart.year ||
            newMonday.month != _weekStart.month ||
            newMonday.day != _weekStart.day) {
          _weekStart = newMonday;
        }
      });
      _scheduleNextMinute();
    });
  }

  void _scheduleNightReload() {
    _reloadTimer?.cancel();
    final now = DateTime.now();

    // Test-override: omladdning efter N minuter
    final testMin = _testReloadMin;
    if (testMin != null && testMin > 0) {
      final target = now.add(Duration(minutes: testMin));
      _scheduledReloadTarget = target;
      final delay = target.difference(now);
      _reloadTimer = Timer(delay, () {
        _performReload();
      });
      return;
    }

    // Ordinarie omladdning kl 03:00
    var target = DateTime(now.year, now.month, now.day, 3, 0, 0);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    _scheduledReloadTarget = target;
    final delay = target.difference(now);
    _reloadTimer = Timer(delay, () {
      _performReload();
    });
  }

  void _performReload() {
    final testMin = _testReloadMin;
    if (testMin != null && testMin > 0) {
      final newParams = Map<String, String>.from(Uri.base.queryParameters)
        ..remove('testReloadMin');
      final cleanUri = Uri.base.replace(
        queryParameters: newParams.isEmpty ? null : newParams,
      );
      reloadWebPage(replaceUrl: cleanUri.toString());
      return;
    }
    reloadWebPage();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Debounce: max 1 steg per 150 ms vid tangentnedtryckning/auto-repeat
    final now = DateTime.now();
    if (now.difference(_lastKeyPressTime) < const Duration(milliseconds: 150)) {
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    String? commandId;

    if (key == LogicalKeyboardKey.keyH) {
      commandId = 'home';
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      commandId = 'week_prev';
    } else if (key == LogicalKeyboardKey.arrowRight) {
      commandId = 'week_next';
    } else if (key == LogicalKeyboardKey.keyN) {
      commandId = 'night_toggle';
    } else if (key == LogicalKeyboardKey.keyL) {
      commandId = 'low_stimuli_toggle';
    } else if (key == LogicalKeyboardKey.keyD) {
      commandId = 'debug_toggle';
    } else if (key == LogicalKeyboardKey.keyR) {
      commandId = 'reload';
    } else if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      commandId = 'scene:standard';
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      commandId = 'scene:natt';
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3 ||
        key == LogicalKeyboardKey.keyI) {
      commandId = 'scene:morgon';
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4 ||
        key == LogicalKeyboardKey.keyM) {
      commandId = 'scene:kvall';
    } else if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.digit7 ||
        key == LogicalKeyboardKey.digit8 ||
        key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad5 ||
        key == LogicalKeyboardKey.numpad6 ||
        key == LogicalKeyboardKey.numpad7 ||
        key == LogicalKeyboardKey.numpad8 ||
        key == LogicalKeyboardKey.numpad9) {
      _lastKeyPressTime = now;
      final digitChar = event.character ?? '';
      DisplayLog.instance.log(
        'kommando',
        'Scentangent $digitChar reserverad för senare fas',
      );
      return KeyEventResult.handled;
    }

    if (commandId != null) {
      _lastKeyPressTime = now;
      _controller.handleCommand(commandId);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  void _onPointerMoved(PointerHoverEvent event) {
    if (!_cursorVisible) {
      setState(() => _cursorVisible = true);
    }
    final now = DateTime.now();
    if (now.difference(_lastCursorArmTime) >= const Duration(milliseconds: 500)) {
      _lastCursorArmTime = now;
      _cursorHideTimer?.cancel();
      _cursorHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _cursorVisible) {
          setState(() => _cursorVisible = false);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _configSource?.removeListener(_onConfigChanged);
    _configSource?.dispose();
    _minuteTimer?.cancel();
    _reloadTimer?.cancel();
    _pendingStormReloadTimer?.cancel();
    _cursorHideTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final fid = provider.currentUser?.familyId ?? '';
    final members = provider.familyMembers;

    if (_configSource == null || _currentFamilyId != fid) {
      _currentFamilyId = fid;
      _configSource?.removeListener(_onConfigChanged);
      _configSource?.dispose();
      _configSource = DisplayConfigSource(familyId: fid)
        ..addListener(_onConfigChanged);
    }

    final effectiveWeekStart = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + _controller.weekOffset * 7,
    );

    final config = _configSource?.config ?? DisplayConfig.defaultConfig();
    final effectiveSceneId =
        _isTestNight ? 'natt' : _controller.effectiveSceneId(_now, config);
    final scene = config.scenes[effectiveSceneId] ??
        config.scenes['standard'] ??
        DisplayConfig.defaultConfig().scenes['standard']!;

    final moduleContext = DisplayModuleContext(
      now: _now,
      weekStart: effectiveWeekStart,
      weekOffset: _controller.weekOffset,
      members: members,
      weatherRefreshEpoch: _weatherRefreshEpoch,
    );

    final body = buildDisplayLayout(
      layoutId: scene.layout,
      context: context,
      moduleContext: moduleContext,
      zoneModules: scene.modules,
    );

    final feedbackMsg = _controller.feedbackMessage;
    final isLow = AppTheme.lowStimuli;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: _cursorVisible ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: _onPointerMoved,
        child: Stack(
          children: [
            body,
            const Positioned(
              bottom: 4,
              right: 8,
              child: DisplaySyncStamp(),
            ),
            if (feedbackMsg != null)
              Positioned(
                bottom: 24,
                left: 24,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isLow
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: Text(
                    feedbackMsg,
                    style: DisplayTheme.feedbackPillStyle,
                  ),
                ),
              ),
            if (_controller.showDebugOverlay)
              DisplayDebugOverlay(controller: _controller),
          ],
        ),
      ),
    );
  }
}
