import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../providers/family_provider.dart';
import 'display_clock.dart';
import 'display_controller.dart';

/// En loggpost för display-lägets telemetri.
class DisplayLogEntry {
  final DateTime timestamp;
  final String category;
  final String message;

  const DisplayLogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
  });
}

/// Ringbuffert för display-lägets loggar (max 100 poster).
/// Fungerar som telemetri-nav och kan observeras av [DisplayDebugOverlay].
class DisplayLog extends ChangeNotifier {
  DisplayLog._() {
    loadVersion();
  }
  static final DisplayLog instance = DisplayLog._();

  static const String _compileTimeVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '');
  static String _runtimeVersion = '';
  static String get appVersion {
    if (_compileTimeVersion.isNotEmpty) {
      return _compileTimeVersion;
    }
    if (_runtimeVersion.isNotEmpty) {
      return '$_runtimeVersion (runtime)';
    }
    return '1.0.0 (runtime)';
  }

  static Future<void> loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      final b = info.buildNumber.trim();
      if (v.isNotEmpty && b.isNotEmpty) {
        _runtimeVersion = '$v+$b';
      } else if (v.isNotEmpty) {
        _runtimeVersion = v;
      }
      instance.notifyListeners();
    } catch (e) {
      developer.log('DisplayLog: kunde inte läsa package_info: $e');
    }
  }

  static const int maxEntries = 100;

  final List<DisplayLogEntry> _entries = [];
  // Undantag (FAS 4.2): Driftloggens starttid ska mäta verklig tid
  final DateTime startedAt = DateTime.now();

  int activeWeekSubscriptions = 3;

  bool syncOk = true;
  bool transitOk = true;
  bool weatherOk = true;

  List<DisplayLogEntry> get entries => List.unmodifiable(_entries);

  void log(String category, String message) {
    developer.log('[$category] $message');
    if (_entries.length >= maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(DisplayLogEntry(
      // Undantag (FAS 4.2): Driftloggens tidsstämplar ska läsa verklig drifttid
      timestamp: DateTime.now(),
      category: category,
      message: message,
    ));

    // Uppdatera hälsoflaggor baserat på loggkategori
    final cat = category.toLowerCase();
    final msg = message.toLowerCase();
    if (cat.contains('strömfel') || cat.contains('synk-fel')) {
      syncOk = false;
    } else if (cat.contains('synk') || cat.contains('konfig')) {
      syncOk = true;
    }

    if (cat.contains('transit-fel') || (cat.contains('transit') && msg.contains('fel'))) {
      transitOk = false;
    } else if (cat.contains('transit') && !msg.contains('fel')) {
      transitOk = true;
    }

    if (cat.contains('väder') && (msg.contains('väderfel') || msg.contains('fel') || msg.contains('misslyckades'))) {
      weatherOk = false;
    } else if (cat.contains('väder') && (msg.contains('väder hämtat') || msg.contains('färsk data'))) {
      weatherOk = true;
    }

    notifyListeners();
  }

  /// Hämtar senaste loggade fel eller varning (om någon finns).
  String? get lastError {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final entry = _entries[i];
      final cat = entry.category.toLowerCase();
      if (cat.contains('fel') || cat.contains('error') || cat.contains('krasch') || cat.contains('render')) {
        return '${entry.category}: ${entry.message}';
      }
    }
    return null;
  }

  void clear() {
    _entries.clear();
    syncOk = true;
    transitOk = true;
    weatherOk = true;
    notifyListeners();
  }
}

/// Halvtransparent debug-overlay som togglas via tangent D eller 'debug_toggle'.
/// Visar appversion, uptime, lastSyncAt, aktiva prenumerationer, natt-/vecko-status
/// samt de ~20 senaste loggraderna i monospace.
class DisplayDebugOverlay extends StatelessWidget {
  final DisplayController controller;

  const DisplayDebugOverlay({super.key, required this.controller});

  String _formatUptime(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'scenbyte':
        return const Color(0xFF5BC0BE);
      case 'konfig':
        return const Color(0xFFF39C12);
      case 'konfig-fallback':
        return const Color(0xFFE74C3C);
      case 'strömfel':
        return const Color(0xFFFF6B6B);
      case 'tick-hopp':
        return const Color(0xFFFFD166);
      case 'kommando':
        return const Color(0xFF4D96FF);
      case 'omladdningsbeslut':
        return const Color(0xFFBB86FC);
      case 'väder':
        return const Color(0xFF6BCB77);
      case 'lifecycle/resume':
        return const Color(0xFF06D6A0);
      case 'testtid':
        return const Color(0xFFFFD166);
      case 'prenumeration':
      default:
        return const Color(0xFFE0E0E0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DisplayLog.instance,
      builder: (context, _) {
        final provider = context.watch<FamilyProvider>();
        final log = DisplayLog.instance;
    // Undantag (FAS 4.2): uptime och driftmätning ska läsa verklig tid
    final uptime = DateTime.now().difference(log.startedAt);
    final lastSync = provider.lastSyncAt;
    final syncStr = lastSync != null
        ? DateFormat('HH:mm:ss').format(lastSync)
        : 'Ingen ännu';
    final activeSubs = provider.activeSubscriptionsCount + log.activeWeekSubscriptions;

    final cfg = controller.currentConfig;
    // Visningstid för scenupplösning i overlayt följer DisplayClock (FAS 4.2)
    final now = DisplayClock.now();
    final activeSceneId = controller.effectiveSceneId(now, cfg);
    final activeSceneName = cfg.scenes[activeSceneId]?.name ?? activeSceneId;
    final isManual = controller.manualSceneId != null;

    final recentEntries = log.entries.reversed.take(20).toList().reversed.toList();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        child: Container(
          width: 820,
          constraints: const BoxConstraints(maxHeight: 620),
          decoration: BoxDecoration(
            color: const Color(0xFF141923).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Text(
                    '🛠️ Storskärm Telemetri (FAS 2.2 & 3)',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Tryck D för att stänga',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Status-fält
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _statusBadge('Version', DisplayLog.appVersion),
                  _statusBadge('Uptime', _formatUptime(uptime)),
                  _statusBadge(
                    'Senaste synk',
                    syncStr,
                    color: provider.syncError ? Colors.amber : null,
                  ),
                  _statusBadge(
                    'Synkstatus',
                    provider.syncError ? '⚠ Fel' : 'OK',
                    color: provider.syncError ? Colors.amber : Colors.greenAccent,
                  ),
                  _statusBadge('Prenumerationer', '$activeSubs aktiva'),
                  _statusBadge('Vecko-offset', '${controller.weekOffset}'),
                  _statusBadge(
                    'Aktiv scen',
                    '$activeSceneName (${isManual ? "Manuell" : "Schema"})',
                  ),
                  if (controller.spotlightIndex != null)
                    _statusBadge(
                      'Spotlight',
                      '${controller.getSpotlightMemberName() ?? "Person ${controller.spotlightIndex}"} (#${controller.spotlightIndex})',
                      color: const Color(0xFF64B5F6),
                    ),
                  _statusBadge('Konfigversion', 'v${cfg.version}'),
                  if (DisplayClock.isTestTime)
                    _statusBadge(
                      'Tidskälla',
                      'TESTTID (${DisplayClock.formatOffset(DisplayClock.offset)})',
                      color: const Color(0xFFFFD166),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Loggruta (~20 senaste i monospace)
              const Text(
                'Senaste händelser i loggen:',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: recentEntries.isEmpty
                      ? const Center(
                          child: Text(
                            'Inga loggposter ännu',
                            style: TextStyle(
                              fontFamily: 'Courier',
                              color: Colors.white38,
                              fontSize: 18,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: recentEntries.length,
                          itemBuilder: (context, index) {
                            final entry = recentEntries[index];
                            final timeStr = DateFormat('HH:mm:ss')
                                .format(entry.timestamp);
                            final catColor = _categoryColor(entry.category);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 18,
                                    height: 1.25,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '[$timeStr] ',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '[${entry.category}] ',
                                      style: TextStyle(
                                        color: catColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: entry.message,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
  }

  Widget _statusBadge(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              color: Colors.white60,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
