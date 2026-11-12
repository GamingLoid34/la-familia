import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Datamodell för storskärmens driftstatus (FAS 6b).
class DisplayStatusData {
  final DateTime? lastSeen;
  final String activeScene;
  final String sceneSource;
  final String buildVersion;
  final DateTime? startedAt;
  final bool testMode;
  final String? lastError;
  final int configVersion;
  final bool syncOk;
  final bool transitOk;
  final bool weatherOk;
  final bool lowStimuli;

  const DisplayStatusData({
    this.lastSeen,
    this.activeScene = '',
    this.sceneSource = '',
    this.buildVersion = '',
    this.startedAt,
    this.testMode = false,
    this.lastError,
    this.configVersion = 10,
    this.syncOk = true,
    this.transitOk = true,
    this.weatherOk = true,
    this.lowStimuli = false,
    this.theme = 'light',
    this.themeMode = 'light',
  });

  final String theme;
  final String themeMode;

  /// Storskärmen räknas som online om senaste hjärtslag är inom 12 minuter.
  bool isOnline([DateTime? now]) {
    if (lastSeen == null) return false;
    final current = now ?? DateTime.now();
    return current.difference(lastSeen!).inMinutes < 12;
  }

  /// Formaterar statusetikett (t.ex. "Online" eller "Offline sedan 14:25").
  String formatStatusText([DateTime? now]) {
    if (lastSeen == null) return 'Offline (ej ansluten)';
    final current = now ?? DateTime.now();
    if (isOnline(current)) return 'Online';

    final ls = lastSeen!;
    final timeStr = DateFormat('HH:mm').format(ls);
    final isToday = ls.year == current.year &&
        ls.month == current.month &&
        ls.day == current.day;

    if (isToday) {
      return 'Offline sedan $timeStr';
    } else {
      final dateStr = DateFormat('d/M').format(ls);
      return 'Offline sedan $dateStr $timeStr';
    }
  }

  /// Formaterar drifttid sedan start.
  String formatUptime([DateTime? now]) {
    if (startedAt == null) return '–';
    final current = now ?? DateTime.now();
    final diff = current.difference(startedAt!);
    if (diff.isNegative) return 'Nyss startad';

    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;

    if (days > 0) {
      return '$days d $hours h';
    } else if (hours > 0) {
      return '$hours h $minutes min';
    } else {
      return '$minutes min';
    }
  }

  /// Formaterar scen och källa till en läsvänlig sträng (t.ex. "Morgon (schema)").
  String formatSceneWithSource() {
    if (activeScene.isEmpty) return '–';
    final capitalized = activeScene[0].toUpperCase() + activeScene.substring(1);
    if (sceneSource.isEmpty) return capitalized;

    String sourceLabel = sceneSource;
    switch (sceneSource) {
      case 'schedule':
        sourceLabel = 'schema';
        break;
      case 'manual':
        sourceLabel = 'manuell';
        break;
      case 'night_toggle':
        sourceLabel = 'nattknapp';
        break;
      case 'person':
        sourceLabel = 'person';
        break;
    }
    return '$capitalized ($sourceLabel)';
  }

  /// Formaterar temat till text för hälsoraden (t.ex. "Tema mörkt (auto)" eller "Tema ljust").
  String formatThemeText() {
    final isDark = theme == 'dark';
    if (themeMode == 'auto') {
      return isDark ? 'Tema mörkt (auto)' : 'Tema ljust (auto)';
    }
    return isDark ? 'Tema mörkt' : 'Tema ljust';
  }

  /// Formaterar hälsoraden till text ("Synk ✓ · Tåg ✓ · Väder ⚠ · v10 · Lågstimuli av · Tema ljust").
  String formatHealthRowText() {
    final s = syncOk ? 'Synk ✓' : 'Synk ⚠';
    final t = transitOk ? 'Tåg ✓' : 'Tåg ⚠';
    final w = weatherOk ? 'Väder ✓' : 'Väder ⚠';
    final v = 'v$configVersion';
    final ls = lowStimuli ? 'Lågstimuli på' : 'Lågstimuli av';
    final th = formatThemeText();
    return '$s · $t · $w · $v · $ls · $th';
  }

  factory DisplayStatusData.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const DisplayStatusData();

    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return DisplayStatusData(
      lastSeen: parseDate(data['lastSeen']),
      activeScene: (data['activeScene'] ?? data['activeSceneId'] ?? '').toString(),
      sceneSource: (data['sceneSource'] ?? '').toString(),
      buildVersion: (data['buildVersion'] ?? data['appVersion'] ?? '').toString(),
      startedAt: parseDate(data['startedAt']),
      testMode: data['testMode'] == true,
      lastError: data['lastError']?.toString(),
      configVersion: (data['configVersion'] as num?)?.toInt() ?? 10,
      syncOk: data['syncOk'] != false,
      transitOk: data['transitOk'] != false,
      weatherOk: data['weatherOk'] != false,
      lowStimuli: data['lowStimuli'] == true,
      theme: (data['theme'] ?? 'light').toString(),
      themeMode: (data['themeMode'] ?? 'light').toString(),
    );
  }
}

/// Driftstatuskort som visar storskärmens hjärtslag i mobilappen (FAS 6b).
class DisplayStatusCard extends StatelessWidget {
  final String familyId;
  final Color dayColor;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? statusStream;

  const DisplayStatusCard({
    super.key,
    required this.familyId,
    required this.dayColor,
    this.statusStream,
  });

  @override
  Widget build(BuildContext context) {
    if (familyId.isEmpty) return const SizedBox.shrink();

    Stream<DocumentSnapshot<Map<String, dynamic>>>? stream = statusStream;
    if (stream == null) {
      try {
        if (Firebase.apps.isNotEmpty) {
          stream = FirebaseFirestore.instance
              .collection('families')
              .doc(familyId)
              .collection('display_state')
              .doc('status')
              .snapshots();
        }
      } catch (_) {
        // Om Firebase inte är initierat (t.ex. i widget-tester)
      }
    }

    if (stream == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final status = DisplayStatusData.fromMap(data);
        final online = status.isOnline();

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: online ? Colors.green.shade200 : Colors.grey.shade200,
              width: online ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Huvudrad: Status, Online/Offline, Testtidsbadge
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: online ? const Color(0xFF4CAF50) : const Color(0xFF9E9E9E),
                      boxShadow: online
                          ? [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.4),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status.formatStatusText(),
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: online ? const Color(0xFF2E7D32) : const Color(0xFF616161),
                    ),
                  ),
                  const Spacer(),
                  if (status.testMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 14, color: Colors.amber.shade900),
                          const SizedBox(width: 4),
                          Text(
                            'TESTTID',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Detaljrader: Scen, Version, Drifttid
              Row(
                children: [
                  _buildDetailCol(
                    label: 'Aktiv scen',
                    value: status.formatSceneWithSource(),
                    icon: Icons.wallpaper_rounded,
                  ),
                  _buildDetailCol(
                    label: 'Version',
                    value: status.buildVersion.isNotEmpty
                        ? status.buildVersion
                        : '–',
                    icon: Icons.code_rounded,
                  ),
                  _buildDetailCol(
                    label: 'Drifttid',
                    value: status.formatUptime(),
                    icon: Icons.timer_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Kompakt hälsorad: "Synk ✓ · Tåg ✓ · Väder ⚠ · v9 · Lågstimuli av"
              _buildHealthRow(status),

              // Varning för senaste fel (om fel rapporterats)
              if (status.lastError != null && status.lastError!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          status.lastError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailCol({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthRow(DisplayStatusData status) {
    InlineSpan buildFlag(String name, bool ok) {
      return TextSpan(
        children: [
          TextSpan(text: '$name '),
          TextSpan(
            text: ok ? '✓' : '⚠',
            style: TextStyle(
              color: ok ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
          ),
          children: [
            buildFlag('Synk', status.syncOk),
            const TextSpan(text: ' · '),
            buildFlag('Tåg', status.transitOk),
            const TextSpan(text: ' · '),
            buildFlag('Väder', status.weatherOk),
            const TextSpan(text: ' · '),
            TextSpan(text: 'v${status.configVersion}'),
            const TextSpan(text: ' · '),
            TextSpan(text: status.lowStimuli ? 'Lågstimuli på' : 'Lågstimuli av'),
            const TextSpan(text: ' · '),
            TextSpan(text: status.formatThemeText()),
          ],
        ),
      ),
    );
  }
}
