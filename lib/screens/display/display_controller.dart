import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_theme.dart';
import '../../utils/date_utils.dart';
import '../../utils/web_reload.dart';
import 'display_log.dart';
import 'display_scene_models.dart';

// ══════════════════════════════════════════════════════════════════════════════
// KOMMANDOTABELL — Storskärm La Familia (FAS 2, 2.2 & 3)
// ══════════════════════════════════════════════════════════════════════════════
// Kommando-ID          Effekt                                  Auto-hem
// ──────────────────────────────────────────────────────────────────────────────
// home                 Sätter weekOffset=0, rensar             Avbryts
//                      manuell scen (återgår till schema)
// week_prev            Backar en vecka (min -8)                Startar / förlängs (+60s)
// week_next            Stegar fram en vecka (max +8)           Startar / förlängs (+60s)
// night_toggle         Växlar nattläge (natt ↔ vaken via scen) Påverkas ej (schemat styr)
// scene:<id>           Sätter manuell scen (t.ex. standard)    Påverkas ej
// low_stimuli_toggle   Växlar lågstimuli lokalt (sparas)       Påverkas ej
// debug_toggle         Togglar debug-overlay på/av             Påverkas ej
// reload               Laddar om webbläsarsidan                Ej tillämpligt
// today (reserverat)   Loggas: 'Kommando today aktiveras i...' Ej tillämpligt
// meals (reserverat)   Loggas: 'Kommando meals aktiveras i...' Ej tillämpligt
// ══════════════════════════════════════════════════════════════════════════════

/// Central controller och kommandomotor för Storskärmen (FAS 2, 2.2 & 3).
/// All extern och intern styrning (tangentbord, Stream Deck, scener)
/// passerar genom [handleCommand].
class DisplayController extends ChangeNotifier {
  final Duration autoHomeDuration;
  final Duration feedbackDuration;
  final Duration sceneTimeoutDuration;
  final DateTime Function() nowProvider;
  final void Function({String? replaceUrl}) onReload;
  final DisplayConfig Function()? configProvider;

  int _weekOffset = 0;
  String? _manualSceneId;
  DateTime _lastScheduleTime;
  String? _feedbackMessage;
  bool _showDebugOverlay = false;

  Timer? _autoHomeTimer;
  Timer? _feedbackTimer;
  Timer? _sceneTimeoutTimer;

  DisplayController({
    this.autoHomeDuration = const Duration(seconds: 60),
    this.feedbackDuration = const Duration(milliseconds: 1500),
    this.sceneTimeoutDuration = const Duration(minutes: 10),
    DateTime Function()? nowProvider,
    void Function({String? replaceUrl})? onReload,
    this.configProvider,
  })  : nowProvider = nowProvider ?? DateTime.now,
        onReload = onReload ?? reloadWebPage,
        _lastScheduleTime = (nowProvider ?? DateTime.now)();

  int get weekOffset => _weekOffset;
  String? get manualSceneId => _manualSceneId;
  String? get feedbackMessage => _feedbackMessage;
  bool get showDebugOverlay => _showDebugOverlay;

  DisplayConfig get currentConfig =>
      configProvider?.call() ?? DisplayConfig.defaultConfig();

  /// Avgör vilken scen som visas för angivet klockslag [now] och [config].
  /// Manuell scen gäller tills schemagräns passeras, 10-minuters timeout löper ut, eller 'home' trycks.
  String effectiveSceneId(DateTime now, [DisplayConfig? config]) {
    final cfg = config ?? currentConfig;
    return _manualSceneId ?? resolveScheduledScene(now, cfg.schedule);
  }

  /// Kontrollerar om aktiv vy är natt-scenen.
  bool isNight(DateTime now, [DisplayConfig? config]) {
    return effectiveSceneId(now, config) == 'natt';
  }

  /// Kontrollerar om en schemagräns har passerats sedan förra kollen.
  /// Vid schemagränspassage rensas eventuell manuell scen och schemat tar över.
  void checkScheduleBoundary(DateTime now, [DisplayConfig? config]) {
    final cfg = config ?? currentConfig;
    final prevScheduled = resolveScheduledScene(_lastScheduleTime, cfg.schedule);
    final currScheduled = resolveScheduledScene(now, cfg.schedule);
    _lastScheduleTime = now;

    if (prevScheduled != currScheduled) {
      if (_manualSceneId != null) {
        _sceneTimeoutTimer?.cancel();
        _sceneTimeoutTimer = null;
        DisplayLog.instance.log(
          'scenbyte',
          'Schemagräns passerad ($prevScheduled → $currScheduled): rensar manuell scen "$_manualSceneId"',
        );
        _manualSceneId = null;
        notifyListeners();
      }
    }
  }

  void _startSceneTimeout() {
    _sceneTimeoutTimer?.cancel();
    _sceneTimeoutTimer = Timer(sceneTimeoutDuration, () {
      if (_manualSceneId != null) {
        DisplayLog.instance.log(
          'scenbyte',
          'scen: auto-återgång till schema',
        );
        _manualSceneId = null;
        _sceneTimeoutTimer = null;
        notifyListeners();
      }
    });
  }

  /// Visar en diskret kvittens nere till vänster i ca 1,5 sekunder.
  void showFeedback(String message) {
    _feedbackTimer?.cancel();
    _feedbackMessage = message;
    notifyListeners();

    _feedbackTimer = Timer(feedbackDuration, () {
      _feedbackMessage = null;
      notifyListeners();
    });
  }

  /// Huvudingång för alla kommandon på storskärmen.
  void handleCommand(String commandId) {
    final now = nowProvider();

    DisplayLog.instance.log('kommando', 'Kör: $commandId');

    if (commandId.startsWith('scene:')) {
      final sceneId = commandId.substring('scene:'.length).trim();
      _handleSetScene(sceneId);
      return;
    }

    switch (commandId) {
      case 'home':
        _handleHome();
        break;

      case 'week_prev':
        _handleWeekPrev(now);
        break;

      case 'week_next':
        _handleWeekNext(now);
        break;

      case 'night_toggle':
        _handleNightToggle(now);
        break;

      case 'low_stimuli_toggle':
        _handleLowStimuliToggle();
        break;

      case 'debug_toggle':
        _showDebugOverlay = !_showDebugOverlay;
        notifyListeners();
        break;

      case 'reload':
        showFeedback('Laddar om…');
        onReload();
        break;

      default:
        developer.log('Okänt kommando: $commandId');
        break;
    }
  }

  void _handleSetScene(String sceneId) {
    final cfg = currentConfig;
    if (cfg.scenes.containsKey(sceneId)) {
      _manualSceneId = sceneId;
      _startSceneTimeout();
      final name = cfg.scenes[sceneId]?.name ?? sceneId;
      showFeedback(name);
      DisplayLog.instance.log(
        'scenbyte',
        'Manuell scen "$sceneId" ($name) aktiverad via kommando',
      );
      notifyListeners();
    } else {
      DisplayLog.instance.log(
        'kommando',
        'Okänd scen i kommando: "$sceneId"',
      );
    }
  }

  void _handleHome() {
    _weekOffset = 0;
    _sceneTimeoutTimer?.cancel();
    _sceneTimeoutTimer = null;
    if (_manualSceneId != null) {
      _manualSceneId = null;
      DisplayLog.instance.log('scenbyte', 'Home-kommando: återgår till schema');
    }
    _autoHomeTimer?.cancel();
    _autoHomeTimer = null;
    showFeedback('Aktuell vecka');
    notifyListeners();
  }

  void _handleWeekPrev(DateTime now) {
    if (_weekOffset > -8) {
      _weekOffset--;
      _startOrExtendAutoHome();
      final targetDate = now.add(Duration(days: _weekOffset * 7));
      final weekNum = isoWeekNumber(targetDate);
      showFeedback('← Vecka $weekNum');
      notifyListeners();
    }
  }

  void _handleWeekNext(DateTime now) {
    if (_weekOffset < 8) {
      _weekOffset++;
      _startOrExtendAutoHome();
      final targetDate = now.add(Duration(days: _weekOffset * 7));
      final weekNum = isoWeekNumber(targetDate);
      showFeedback('→ Vecka $weekNum');
      notifyListeners();
    }
  }

  void _startOrExtendAutoHome() {
    _autoHomeTimer?.cancel();
    if (_weekOffset != 0) {
      _autoHomeTimer = Timer(autoHomeDuration, () {
        _weekOffset = 0;
        _autoHomeTimer = null;
        notifyListeners();
      });
    } else {
      _autoHomeTimer = null;
    }
  }

  void _handleNightToggle(DateTime now) {
    final cfg = currentConfig;
    final currentScene = effectiveSceneId(now, cfg);

    final String target;
    if (currentScene == 'natt') {
      // Visas natt nu -> väck skärmen till schemalagd dagscen eller standard
      final scheduled = resolveScheduledScene(now, cfg.schedule);
      target = scheduled != 'natt' ? scheduled : 'standard';
    } else {
      target = 'natt';
    }

    if (!cfg.scenes.containsKey(target)) {
      developer.log(
        'night_toggle: målscenen "$target" saknas i konfigurationen',
      );
      DisplayLog.instance.log(
        'kommando',
        'night_toggle avbruten: målscenen "$target" saknas i konfigurationen',
      );
      return;
    }

    _manualSceneId = target;
    final name = cfg.scenes[target]?.name ?? target;
    showFeedback(name);
    DisplayLog.instance.log(
      'scenbyte',
      'Manuell scen "$target" ($name) aktiverad (night_toggle ${target == 'natt' ? 'natt' : 'väck'})',
    );
    notifyListeners();
  }

  Future<void> _handleLowStimuliToggle() async {
    AppTheme.lowStimuli = !AppTheme.lowStimuli;
    showFeedback(AppTheme.lowStimuli ? 'Lågstimuli på' : 'Lågstimuli av');
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('lowStimuli', AppTheme.lowStimuli);
    } catch (e, stack) {
      developer.log('DisplayController: kunde inte spara lowStimuli',
          error: e, stackTrace: stack);
    }
  }

  @override
  void dispose() {
    _autoHomeTimer?.cancel();
    _feedbackTimer?.cancel();
    _sceneTimeoutTimer?.cancel();
    super.dispose();
  }
}
