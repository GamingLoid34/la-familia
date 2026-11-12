import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../display_log.dart';
import '../display_module_registry.dart';
import '../display_palette.dart';
import '../display_scene_models.dart';

/// En enskild avgång från Trafiklab.
class TransitDeparture {
  final String line;
  final String mode; // 'bus' eller 'train'
  final String destination;
  final String scheduled; // 'HH:mm'
  final String realtime; // 'HH:mm'
  final int delayedMin;
  final bool cancelled;
  final String stopId;
  final String stopName;
  final String stopIcon;

  const TransitDeparture({
    required this.line,
    required this.mode,
    required this.destination,
    required this.scheduled,
    required this.realtime,
    required this.delayedMin,
    required this.cancelled,
    required this.stopId,
    required this.stopName,
    required this.stopIcon,
  });

  factory TransitDeparture.fromMap(
    Map<String, dynamic> map, {
    String stopId = '',
    String stopName = '',
    String stopIcon = '🚌',
  }) {
    return TransitDeparture(
      line: (map['line'] as String? ?? '').trim(),
      mode: (map['mode'] as String? ?? 'bus').trim(),
      destination: (map['destination'] as String? ?? '').trim(),
      scheduled: (map['scheduled'] as String? ?? '').trim(),
      realtime: (map['realtime'] as String? ?? '').trim(),
      delayedMin: (map['delayedMin'] as num?)?.toInt() ?? 0,
      cancelled: map['cancelled'] as bool? ?? false,
      stopId: stopId,
      stopName: stopName,
      stopIcon: stopIcon,
    );
  }
}

/// Beräknar återstående minuter mellan klockslag [timeStr] ('HH:mm') och referenstidpunkten [now].
///
/// Hanterar wrap över midnatt om differensen är nära 24 timmar.
/// Returnerar negativt värde om klockslaget redan har passerat idag.
int calculateMinutesUntil(String timeStr, DateTime now) {
  final parts = timeStr.split(':');
  if (parts.length < 2) return -999;
  final h = int.tryParse(parts[0].trim()) ?? 0;
  final m = int.tryParse(parts[1].trim()) ?? 0;

  final nowMinutes = now.hour * 60 + now.minute;
  var depMinutes = h * 60 + m;

  // Wrap över midnatt: om avgång är 00:15 och nu är 23:50
  if (depMinutes < nowMinutes - 720) {
    depMinutes += 1440;
  } else if (depMinutes > nowMinutes + 720) {
    // Om avgång är 23:50 och nu är 00:15 (passerad gårdagsavgång)
    depMinutes -= 1440;
  }

  return depMinutes - nowMinutes;
}

/// Beräknar backoff-intervall i sekunder vid nätverks-/API-fel:
/// 60s -> 120s -> 300s (max 5 min).
int computeTransitBackoff(int currentIntervalSeconds) {
  final next = currentIntervalSeconds * 2;
  return next > 300 ? 300 : next;
}

/// Beräknar gå-differens i minuter relativt tidtabellstid:
/// gåOm = scheduledMin - walkMinutes
int calculateWalkMinutes(int scheduledMinutesUntil, {int walkMinutes = 5}) {
  return scheduledMinutesUntil - walkMinutes;
}

/// Formaterar gå-etikett (FAS 5.3 & FAS 5.7):
/// gåOm > 60: "gå kl HH:mm" (absolut avmarschtid)
/// 1 < gåOm <= 60: "gå om X min"
/// gåOm == 1 || gåOm == 0: "GÅ NU"
/// gåOm < 0: "hinns ej"
String formatWalkingLabel(int gaOm, {DateTime? now}) {
  if (gaOm > 60) {
    final ref = now ?? DateTime.now();
    final walkTime = ref.add(Duration(minutes: gaOm));
    final hh = walkTime.hour.toString().padLeft(2, '0');
    final mm = walkTime.minute.toString().padLeft(2, '0');
    return 'gå kl $hh:$mm';
  }
  if (gaOm > 1) return 'gå om $gaOm min';
  if (gaOm >= 0) return 'GÅ NU';
  return 'hinns ej';
}

/// Skapar en målorienterad destinationsetikett för presentation (FAS 5.3):
/// - Terminus innehåller "Linköping" eller "Norrköping" -> "Tåg mot Linköping"
///   (Norrköpingståg går via Linköping — man kliver av där)
/// - Terminus innehåller "Mjölby" -> "Tåg mot Linköping · byte i Mjölby"
///   (bytet som dämpad badge)
/// Rå destination behålls i kontraktet/datat — endast presentationen ändras.
String formatTransitDestinationLabel(
  String rawDestination, {
  String mode = 'train',
}) {
  final destLower = rawDestination.toLowerCase();
  if (mode == 'train') {
    if (destLower.contains('linköping') || destLower.contains('norrköping')) {
      return 'Tåg mot Linköping';
    }
    if (destLower.contains('mjölby')) {
      return 'Tåg mot Linköping · byte i Mjölby';
    }
    return 'Tåg mot $rawDestination';
  }
  return 'Buss mot $rawDestination';
}

/// Kontrollerar om en avgång matchar konfigurerat destinations- och modfilter.
/// Standardfilter (FAS 5): tåg mot Mjölby, Linköping eller Norrköping (delsträng, case-insensitive).
bool matchesTransitFilter(
  TransitDeparture d, {
  List<String> allowedModes = const ['train'],
  List<String> allowedDestinations = const ['mjölby', 'linköping', 'norrköping'],
}) {
  if (allowedModes.isNotEmpty) {
    final modeLower = d.mode.toLowerCase();
    if (!allowedModes.any((m) => m.toLowerCase() == modeLower)) {
      return false;
    }
  }

  if (allowedDestinations.isNotEmpty) {
    final destLower = d.destination.toLowerCase();
    final matched = allowedDestinations.any(
      (target) => destLower.contains(target.toLowerCase()),
    );
    if (!matched) return false;
  }

  return true;
}

/// Formaterar en avgång för footerkortet (FAS 5.3):
/// T.ex: "🚆 Tåg mot Linköping · gå om 27 min (07:17)"
/// eller: "🚆 Tåg mot Linköping · byte i Mjölby · gå om 27 min (07:17)"
/// gåOm räknas ALLTID på TIDTABELLSTID (scheduled), aldrig realtid.
String formatFooterDeparture(
  TransitDeparture d,
  DateTime now, {
  int walkMinutes = 5,
}) {
  final icon = d.mode == 'train' ? '🚆' : (d.stopIcon.isNotEmpty ? d.stopIcon : '🚌');
  final targetLabel = formatTransitDestinationLabel(d.destination, mode: d.mode);
  final schedTime = d.scheduled;

  if (d.cancelled) {
    return '$icon $targetLabel · Inställd ($schedTime)';
  }

  final scheduledMinutesUntil = calculateMinutesUntil(d.scheduled, now);
  final gaOm = calculateWalkMinutes(scheduledMinutesUntil, walkMinutes: walkMinutes);
  final gaLabel = formatWalkingLabel(gaOm, now: now);

  // Varningsbadge vid försening: (07:49, +4 min sen) vs (07:49)
  final timeBadge = d.delayedMin > 0
      ? '($schedTime, +${d.delayedMin} min sen)'
      : '($schedTime)';

  return '$icon $targetLabel · $gaLabel $timeBadge';
}

/// Filtrerar bort passerade avgångar (på scheduled-tid) samt icke-matchande
/// destinationer/modes, och sorterar stigande efter tidtabellstid.
List<TransitDeparture> filterAndSortUpcomingDepartures(
  List<TransitDeparture> departures,
  DateTime now, {
  int limit = 3,
  List<String> allowedModes = const ['train'],
  List<String> allowedDestinations = const ['mjölby', 'linköping', 'norrköping'],
}) {
  final upcoming = departures.where((d) {
    if (!matchesTransitFilter(
      d,
      allowedModes: allowedModes,
      allowedDestinations: allowedDestinations,
    )) {
      return false;
    }

    final diff = calculateMinutesUntil(d.scheduled, now);
    return diff >= 0; // Ta med avgångar som avgår nu eller i framtiden enligt tidtabell
  }).toList();

  upcoming.sort((a, b) {
    final diffA = calculateMinutesUntil(a.scheduled, now);
    final diffB = calculateMinutesUntil(b.scheduled, now);
    return diffA.compareTo(diffB);
  });

  return upcoming.take(limit).toList();
}

/// Modul: Avgångar ("avgangar") (FAS 5).
///
/// Pollar Cloud Function displayTransit var 60:e sekund medan modulen är monterad.
/// Implementerar adaptiv rendering (footerkort 88px vs större zon).
class AvgangarModule extends StatefulWidget {
  final DisplayModuleContext moduleContext;

  const AvgangarModule({super.key, required this.moduleContext});

  @override
  State<AvgangarModule> createState() => _AvgangarModuleState();
}

class _AvgangarModuleState extends State<AvgangarModule> {
  Timer? _pollTimer;
  int _intervalSeconds = 60;
  bool _hasError = false;
  bool _isLoading = false;

  // Senast kända avgångar per stopId
  Map<String, List<TransitDeparture>> _departuresByStop = {};

  @override
  void initState() {
    super.initState();
    // Själva nätverkspollningen och cache-intervallen följer verklig väggtid (DateTime.now()),
    // medan UI-rendering och minutnedräkning beräknas dynamiskt mot moduleContext.now (testtidskompatibel).
    _pollTransit();
    _startTimer();
  }

  void _startTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (_) => _pollTransit(),
    );
  }

  List<DisplayTransitStop> _configuredStops() {
    final cfg = widget.moduleContext.transitConfig;
    if (cfg != null) {
      return cfg.stops;
    }
    // Fallback till standardhållplatser för Tranås om config saknas helt
    return DisplayConfig.defaultConfig().transit.stops;
  }

  Future<void> _pollTransit() async {
    if (_isLoading) return;
    _isLoading = true;

    final stops = _configuredStops();
    if (stops.isEmpty) {
      if (mounted) {
        setState(() {
          _departuresByStop = {};
          _isLoading = false;
        });
      }
      return;
    }
    final stopIds = stops.map((s) => s.id).toList();

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('displayTransit');

      final result = await callable.call<Map<String, dynamic>>({
        'stopIds': stopIds,
        'limit': 20,
      });

      final data = result.data;
      final rawStops = data['stops'];

      final nextMap = <String, List<TransitDeparture>>{};
      final logSummary = <String>[];

      if (rawStops is List) {
        for (final item in rawStops) {
          if (item is Map) {
            final sId = (item['stopId'] as String? ?? '').trim();
            final sName = (item['stopName'] as String? ?? '').trim();
            final matchedCfg = stops.firstWhere(
              (s) => s.id == sId,
              orElse: () => DisplayTransitStop(id: sId, name: sName, icon: '🚌'),
            );

            final rawDeps = item['departures'];
            final depList = <TransitDeparture>[];
            if (rawDeps is List) {
              for (final d in rawDeps) {
                if (d is Map) {
                  depList.add(TransitDeparture.fromMap(
                    Map<String, dynamic>.from(d),
                    stopId: sId,
                    stopName: sName.isNotEmpty ? sName : matchedCfg.name,
                    stopIcon: matchedCfg.icon,
                  ));
                }
              }
            }
            nextMap[sId] = depList;
            logSummary.add('$sName: ${depList.length} avgångar');
          }
        }
      }

      DisplayLog.instance.log(
        'transit',
        'displayTransit hämtat (${logSummary.join(', ')})',
      );

      if (mounted) {
        setState(() {
          _departuresByStop = nextMap;
          _hasError = false;
          _isLoading = false;
          _intervalSeconds = 60;
        });
      }
    } catch (e, stack) {
      developer.log('AvgangarModule: fel vid poling', error: e, stackTrace: stack);
      DisplayLog.instance.log(
        'transit-fel',
        'Fel vid anrop till displayTransit: $e — backar intervall',
      );

      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _intervalSeconds = computeTransitBackoff(_intervalSeconds);
        });
        _startTimer();
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.moduleContext.now;
    final stops = _configuredStops();
    final transitCfg = widget.moduleContext.transitConfig;
    final fallbackModes = transitCfg?.modes ?? const ['train'];
    final fallbackDestinations =
        transitCfg?.destinations ?? const ['mjölby', 'linköping', 'norrköping'];
    final defaultWalkMinutes = transitCfg?.walkMinutes ?? 5;

    // Samla alla avgångar över alla hållplatser, filtrerade per hållplats för footerkortet
    final allUpcoming = <TransitDeparture>[];
    for (final s in stops) {
      final list = _departuresByStop[s.id] ?? const [];
      final stopModes = s.filter != null ? s.filter!.modes : fallbackModes;
      final stopDest = s.filter != null ? s.filter!.destinations : fallbackDestinations;
      final upcomingForStop = filterAndSortUpcomingDepartures(
        list,
        now,
        limit: 3,
        allowedModes: stopModes,
        allowedDestinations: stopDest,
      );
      allUpcoming.addAll(upcomingForStop);
    }

    allUpcoming.sort((a, b) {
      final diffA = calculateMinutesUntil(a.scheduled, now);
      final diffB = calculateMinutesUntil(b.scheduled, now);
      return diffA.compareTo(diffB);
    });

    final upcomingAll = allUpcoming.take(3).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 130) {
          return _buildFooterCard(upcomingAll, now, stops, defaultWalkMinutes);
        }
        return _buildLargeZone(
          stops,
          now,
          allowedModes: fallbackModes,
          allowedDestinations: fallbackDestinations,
          defaultWalkMinutes: defaultWalkMinutes,
        );
      },
    );
  }

  /// Footerkort-läge (<= 130 px höjd, t.ex. DisplayTheme.footerHeight = 112)
  Widget _buildFooterCard(
    List<TransitDeparture> departures,
    DateTime now,
    List<DisplayTransitStop> stops,
    int defaultWalkMinutes,
  ) {
    final palette = DisplayPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              const Text('🚆', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                'Avgångar',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.textMuted,
                ),
              ),
              if (_hasError) ...[
                const SizedBox(width: 6),
                const Text(
                  '⚠',
                  style: TextStyle(color: Colors.amber, fontSize: 13),
                ),
              ],
              const Spacer(),
              Text(
                'data från Trafiklab.se',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 10,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (stops.isEmpty)
            Text(
              'Inga hållplatser konfigurerade',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontStyle: FontStyle.italic,
                color: palette.textMuted,
              ),
            )
          else if (departures.isEmpty)
            Text(
              'Inga avgångar den närmaste timmen',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontStyle: FontStyle.italic,
                color: palette.textMuted,
              ),
            )
          else
            ...departures.map((d) {
              final stop = stops.firstWhere(
                (s) => s.id == d.stopId,
                orElse: () => DisplayTransitStop(
                  id: d.stopId,
                  name: d.stopName,
                  icon: d.stopIcon,
                  walkMinutes: defaultWalkMinutes,
                ),
              );
              return _buildFooterDepartureRow(
                d,
                now,
                walkMinutes: stop.walkMinutes,
                palette: palette,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildFooterDepartureRow(
    TransitDeparture d,
    DateTime now, {
    required int walkMinutes,
    required DisplayPalette palette,
  }) {
    final icon = d.mode == 'train' ? '🚆' : (d.stopIcon.isNotEmpty ? d.stopIcon : '🚌');
    final schedTime = d.scheduled;
    final destLower = d.destination.toLowerCase();
    final hasTransfer = d.mode == 'train' && destLower.contains('mjölby');

    final baseTargetText = d.mode == 'train'
        ? 'Tåg mot Linköping'
        : 'Buss mot ${d.destination}';

    if (d.cancelled) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.0),
        child: Text(
          '$icon $baseTargetText · Inställd ($schedTime)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFFE53935),
          ),
        ),
      );
    }

    final scheduledMinutesUntil = calculateMinutesUntil(d.scheduled, now);
    final gaOm = calculateWalkMinutes(scheduledMinutesUntil, walkMinutes: walkMinutes);
    final gaLabel = formatWalkingLabel(gaOm, now: now);
    final timeBadge = d.delayedMin > 0
        ? '($schedTime, +${d.delayedMin} min sen)'
        : '($schedTime)';
    final isGoNow = gaOm >= 0 && gaOm <= 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Row(
        children: [
          Text(
            '$icon $baseTargetText',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          if (hasTransfer) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: palette.isDark
                    ? const Color(0xFF2A3140)
                    : const Color(0xFFEFF1F5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: palette.isDark
                      ? const Color(0xFF3B4455)
                      : const Color(0xFFD4D8E2),
                ),
              ),
              child: Text(
                'byte i Mjölby',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '· $gaLabel $timeBadge',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isGoNow ? const Color(0xFFD97706) : palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Större zon (en kolumn per hållplats)
  Widget _buildLargeZone(
    List<DisplayTransitStop> stops,
    DateTime now, {
    List<String> allowedModes = const ['train'],
    List<String> allowedDestinations = const ['mjölby', 'linköping', 'norrköping'],
    int defaultWalkMinutes = 5,
  }) {
    final palette = DisplayPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gemensam rubrikrad med Trafiklab-attribution
          Row(
            children: [
              const Text('🚆', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                'Avgångar & Kollektivtrafik',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
              if (_hasError) ...[
                const SizedBox(width: 6),
                const Text(
                  '⚠',
                  style: TextStyle(color: Colors.amber, fontSize: 16),
                ),
              ],
              const Spacer(),
              const Text(
                'data från Trafiklab.se',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 11,
                  color: Color(0xFF888888),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: palette.divider),
          const SizedBox(height: 12),

          // Kolumner per hållplats
          Expanded(
            child: stops.isEmpty
                ? Center(
                    child: Text(
                      'Inga hållplatser konfigurerade',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                        color: palette.textMuted,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < stops.length; i++) ...[
                        if (i > 0) VerticalDivider(width: 24, color: palette.divider),
                        Expanded(
                          child: _buildStopColumn(
                            stops[i],
                            now,
                            palette: palette,
                            fallbackModes: allowedModes,
                            fallbackDestinations: allowedDestinations,
                            defaultWalkMinutes: defaultWalkMinutes,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopColumn(
    DisplayTransitStop stop,
    DateTime now, {
    required DisplayPalette palette,
    List<String> fallbackModes = const ['train'],
    List<String> fallbackDestinations = const ['mjölby', 'linköping', 'norrköping'],
    int defaultWalkMinutes = 5,
  }) {
    final rawDeps = _departuresByStop[stop.id] ?? const [];
    final stopModes = stop.filter != null ? stop.filter!.modes : fallbackModes;
    final stopDest = stop.filter != null ? stop.filter!.destinations : fallbackDestinations;
    final upcoming = filterAndSortUpcomingDepartures(
      rawDeps,
      now,
      limit: 6,
      allowedModes: stopModes,
      allowedDestinations: stopDest,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hållplatsrubrik
        Row(
          children: [
            Text(stop.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                stop.name,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (upcoming.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'Inga avgångar den närmaste timmen',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  color: palette.textMuted,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: upcoming.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final d = upcoming[index];
                return _buildDepartureRow(
                  d,
                  now,
                  palette: palette,
                  walkMinutes: stop.walkMinutes,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDepartureRow(
    TransitDeparture d,
    DateTime now, {
    required DisplayPalette palette,
    int walkMinutes = 5,
  }) {
    final scheduledMinutesUntil = calculateMinutesUntil(d.scheduled, now);
    final gaOm = calculateWalkMinutes(scheduledMinutesUntil, walkMinutes: walkMinutes);
    final gaLabel = formatWalkingLabel(gaOm, now: now);
    final destLower = d.destination.toLowerCase();
    final hasTransfer = d.mode == 'train' && destLower.contains('mjölby');
    final baseTargetText = d.mode == 'train'
        ? 'Tåg mot Linköping'
        : 'Buss mot ${d.destination}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.isDark ? palette.background : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Linjepill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: d.mode == 'train'
                  ? (palette.isDark
                      ? const Color(0xFF2A6F97).withValues(alpha: 0.35)
                      : const Color(0xFF2A6F97).withValues(alpha: 0.14))
                  : (palette.isDark
                      ? const Color(0xFF4C566A).withValues(alpha: 0.35)
                      : const Color(0xFF4C566A).withValues(alpha: 0.12)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              d.line,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: d.mode == 'train'
                    ? (palette.isDark ? const Color(0xFF90CAF9) : const Color(0xFF2A6F97))
                    : (palette.isDark ? const Color(0xFFD8DEE9) : const Color(0xFF2E3440)),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Destination
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    baseTargetText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      decoration: d.cancelled ? TextDecoration.lineThrough : null,
                      color: d.cancelled ? Colors.grey : palette.textPrimary,
                    ),
                  ),
                ),
                if (hasTransfer) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: palette.isDark
                          ? const Color(0xFF2A3140)
                          : const Color(0xFFEFF1F5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: palette.isDark
                            ? const Color(0xFF3B4455)
                            : const Color(0xFFD4D8E2),
                      ),
                    ),
                    child: Text(
                      'byte i Mjölby',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Tid / status
          if (d.cancelled)
            Text(
              'Inställd (${d.scheduled})',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.red.shade700,
                decoration: TextDecoration.lineThrough,
              ),
            )
          else if (d.delayedMin > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$gaLabel (${d.scheduled}',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  ', +${d.delayedMin} min sen)',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            )
          else
            Text(
              '$gaLabel (${d.scheduled})',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
        ],
      ),
    );
  }
}
