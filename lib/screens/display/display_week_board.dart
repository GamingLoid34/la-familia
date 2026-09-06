import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../../models/user_model.dart';
import '../../services/weather_service.dart';
import '../../utils/date_utils.dart';
import '../../utils/schedule_display.dart';
import '../../utils/schedule_time_utils.dart';
import '../../utils/week_bucketing.dart';
import 'display_chips.dart';
import 'display_formatters.dart';
import 'display_log.dart';
import 'display_theme.dart';

/// Beräknar backoff-intervall för väderhämtning (FAS 2.2 Beslut 4).
/// 1 fel: 1 min, 2 fel: 2 min, 3+ fel: 5 min.
Duration computeWeatherBackoff(int failureCount) {
  if (failureCount <= 1) return const Duration(minutes: 1);
  if (failureCount == 2) return const Duration(minutes: 2);
  return const Duration(minutes: 5);
}

/// Kontrollerar om en manuell väderhämtning ska hoppas över p.g.a. färsk data (< 5 min) (FAS 3.1).
bool shouldSkipManualWeatherFetch({
  required DateTime now,
  required DateTime? lastSuccessfulFetch,
  Duration freshThreshold = const Duration(minutes: 5),
}) {
  if (lastSuccessfulFetch == null) return false;
  return now.difference(lastSuccessfulFetch) < freshThreshold;
}

/// Storskärmens Veckotavla (FAS 1.2 & 2.2).
/// - Tydlig visuell hierarki: Ramhändelser viskar (1-rad, 10% färg), aktiviteter ropar (vit chip, 3px vänsterkant, 2 rader)
/// - Kompakt tidsformat (17, 8:15–14, 7:30–16)
/// - Familjefold: Händelser för alla medlemmar foldas till Familjen-raden (👨👩👧👦)
/// - Färgidentitet: Varje medlem har sin unika färg på avatar och aktivitetschip
/// - Ökad kontrast och skarp typografi (klocka 72, medlemsnamn 24, chip-titel 21, chip-tid 20)
/// - Material-ikoner i footern (restaurant_rounded, check_circle_rounded, push_pin_rounded)
/// - Timer-driven väderuppdatering (var 30:e min + backoff vid fel)
/// - Synkstämpel 'Synk HH:mm · La Familia' i footerns hörn
class DisplayWeekBoard extends StatefulWidget {
  final WeekBucketingResult data;
  final Set<String> foldedDocIds;
  final DateTime weekStart;
  final DateTime now;
  final List<UserModel> members;
  final double? homeLat;
  final double? homeLon;
  final int weekOffset;
  final int weatherRefreshEpoch;
  final bool hasSyncError;
  final bool isLoading;

  const DisplayWeekBoard({
    super.key,
    required this.data,
    this.foldedDocIds = const {},
    required this.weekStart,
    required this.now,
    required this.members,
    this.homeLat,
    this.homeLon,
    this.weekOffset = 0,
    this.weatherRefreshEpoch = 0,
    this.hasSyncError = false,
    this.isLoading = false,
  });

  @override
  State<DisplayWeekBoard> createState() => _DisplayWeekBoardState();
}

class _DisplayWeekBoardState extends State<DisplayWeekBoard> {
  WeatherSnapshot? _weather;
  Timer? _weatherTimer;
  bool _isFetchingWeather = false;
  int _consecutiveFailures = 0;
  DateTime? _lastSuccessfulWeatherFetch;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  @override
  void didUpdateWidget(covariant DisplayWeekBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeLat != widget.homeLat ||
        oldWidget.homeLon != widget.homeLon) {
      _consecutiveFailures = 0;
      _fetchWeather();
    } else if (oldWidget.weatherRefreshEpoch != widget.weatherRefreshEpoch) {
      _fetchWeather(isManualTrigger: true);
    }
  }

  @override
  void dispose() {
    _weatherTimer?.cancel();
    super.dispose();
  }

  void _scheduleNextWeather(Duration delay) {
    _weatherTimer?.cancel();
    _weatherTimer = Timer(delay, () => _fetchWeather());
  }

  Future<void> _fetchWeather({bool isManualTrigger = false}) async {
    final now = DateTime.now();
    if (isManualTrigger &&
        shouldSkipManualWeatherFetch(
          now: now,
          lastSuccessfulFetch: _lastSuccessfulWeatherFetch,
        )) {
      DisplayLog.instance.log('väder', 'Hoppar över — färsk data');
      return;
    }
    if (_isFetchingWeather) return;
    final lat = widget.homeLat;
    final lon = widget.homeLon;
    if (lat == null || lon == null) return;

    _isFetchingWeather = true;
    try {
      DisplayLog.instance.log(
        'väder',
        'Hämtar SMHI-väder ($lat, $lon)${isManualTrigger ? " [manuell trigger]" : ""}',
      );
      final res = await WeatherService.instance.forecastFor(lat, lon);
      if (res != null) {
        if (mounted) setState(() => _weather = res);
        _consecutiveFailures = 0;
        _lastSuccessfulWeatherFetch = DateTime.now();
        DisplayLog.instance.log(
          'väder',
          'Väder hämtat (${res.daily.length} dagar). Nästa om 30 min.',
        );
        _scheduleNextWeather(const Duration(minutes: 30));
      } else {
        throw Exception('Inget svar från SMHI (null)');
      }
    } catch (e, stack) {
      _consecutiveFailures++;
      final backoff = computeWeatherBackoff(_consecutiveFailures);
      developer.log('Veckotavlan: väderhämtning misslyckades',
          error: e, stackTrace: stack);
      DisplayLog.instance.log(
        'väder',
        'Väderfel: $e. Försök $_consecutiveFailures misslyckades, återförsök om ${backoff.inMinutes} min',
      );
      _scheduleNextWeather(backoff);
    } finally {
      _isFetchingWeather = false;
    }
  }

  String _formatSwedishDate(DateTime dt) {
    final raw = DateFormat('EEEE d MMMM', 'sv_SE').format(dt);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  DailyForecast? _forecastForDay(DateTime day) {
    if (_weather == null) return null;
    for (final f in _weather!.daily) {
      if (sameCalendarDay(f.date, day)) return f;
    }
    return null;
  }

  Color _memberColor(UserModel m, DayPalette palette) {
    try {
      if (m.color.isNotEmpty) {
        return AppTheme.colorFromHex(m.color);
      }
      return Color(m.colorValue);
    } catch (_) {
      return palette.base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette(widget.now.weekday);
    final weekEnd = widget.weekStart.add(const Duration(days: 6));
    final weekNum = isoWeekNumber(widget.weekStart);
    final isLowStimuli = AppTheme.lowStimuli;

    final weekRangeStr =
        '${DateFormat('d MMM', 'sv').format(widget.weekStart)} – ${DateFormat('d MMM', 'sv').format(weekEnd)}';
    final timeStr = DateFormat('HH:mm').format(widget.now);
    final dateStr = _formatSwedishDate(widget.now);

    return Column(
      children: [
        // ─── 1. HEADER (~96 px) ─────────────────────────────────────────
              SizedBox(
                height: DisplayTheme.headerHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Vänster: Veckonummer + datumintervall + ev. synk-varning
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('V.$weekNum',
                                style: DisplayTheme.weekNumStyle
                                    .copyWith(color: const Color(0xFF1A1A2E))),
                            const SizedBox(width: 14),
                            Text(weekRangeStr,
                                style: DisplayTheme.dateRangeStyle.copyWith(
                                    color: const Color(0xFF5C6877))),
                            if (widget.weekOffset != 0) ...[
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: palette.base.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: palette.base.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  'Visar v.$weekNum · återgår strax',
                                  style: DisplayTheme.headerIndicatorStyle.copyWith(
                                    color: palette.deep,
                                  ),
                                ),
                              ),
                            ],
                            if (widget.hasSyncError) ...[
                              const SizedBox(width: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.amber.shade400),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.warning_amber_rounded,
                                        size: 16, color: Colors.amber.shade900),
                                    const SizedBox(width: 4),
                                    Text(
                                      '⚠ Uppdateras inte',
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Höger: Klocka + Dagens datum
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(timeStr,
                            style: DisplayTheme.clockStyle
                                .copyWith(color: const Color(0xFF1A1A2E))),
                        const SizedBox(height: 2),
                        Text(dateStr,
                            style: DisplayTheme.dateRangeStyle.copyWith(
                                color: const Color(0xFF5C6877),
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),

              // ─── 2. DAGSHUVUD-RAD (~74 px) ──────────────────────────────────
              SizedBox(
                height: DisplayTheme.dayHeaderHeight,
                child: Row(
                  children: [
                    const SizedBox(width: DisplayTheme.memberColWidth),
                    for (final day in widget.data.days)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildDayHeader(day, palette, isLowStimuli),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // ─── 3. GRID (EXPANDED) ─────────────────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hasFamily = widget.data.hasFamilyEvents;
                    final memberCount = widget.members.length;
                    final totalRows = memberCount + (hasFamily ? 0.88 : 0.0);
                    final effectiveRows = totalRows > 0 ? totalRows : 1.0;
                    final rowHeight =
                        (constraints.maxHeight / effectiveRows).clamp(64.0, 180.0);

                    return Column(
                      children: [
                        if (hasFamily)
                          SizedBox(
                            height: rowHeight * 0.88,
                            child: _buildFamilyRow(palette, isLowStimuli),
                          ),
                        for (final m in widget.members)
                          Expanded(
                            child: _buildMemberRow(m, palette, isLowStimuli),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
  }

  // ─── Byggstenar ───────────────────────────────────────────────────────────

  Widget _buildDayHeader(DateTime day, DayPalette palette, bool isLowStimuli) {
    final isToday = sameCalendarDay(day, widget.now);
    final isPast = day.isBefore(
      DateTime(widget.now.year, widget.now.month, widget.now.day),
    );
    final dayLabel = DateFormat('E d', 'sv').format(day);
    final dayCapitalized = dayLabel[0].toUpperCase() + dayLabel.substring(1);
    final forecast = _forecastForDay(day);

    if (isToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          gradient: isLowStimuli ? null : palette.gradient,
          color: isLowStimuli ? palette.base : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: palette.base.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'IDAG',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  dayCapitalized,
                  style: DisplayTheme.dayNameStyle.copyWith(
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            if (forecast != null) ...[
              const SizedBox(height: 2),
              Text(
                '${forecast.emoji} ${forecast.maxTemp?.round() ?? ""}°${forecast.minTemp != null ? "/${forecast.minTemp?.round()}°" : ""}',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: DisplayTheme.weatherFontSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Passerade eller framtida dagar
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE2E5EE),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dayCapitalized,
            style: DisplayTheme.dayNameStyle.copyWith(
              color: isPast
                  ? Colors.grey.shade400
                  : const Color(0xFF2C3E50),
            ),
          ),
          if (!isPast && forecast != null) ...[
            const SizedBox(height: 2),
            Text(
              '${forecast.emoji} ${forecast.maxTemp?.round() ?? ""}°${forecast.minTemp != null ? "/${forecast.minTemp?.round()}°" : ""}',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: DisplayTheme.weatherFontSize,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF5C6877),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFamilyRow(DayPalette palette, bool isLowStimuli) {
    return Row(
      children: [
        // Rad-etikett: Familjen (~190 px)
        SizedBox(
          width: DisplayTheme.memberColWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.base,
                    shape: BoxShape.circle,
                    boxShadow: isLowStimuli
                        ? null
                        : [
                            BoxShadow(
                              color: palette.base.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: const Center(
                    child: Text('👥', style: TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Familjen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DisplayTheme.memberNameStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 7 celler
        for (final day in widget.data.days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: _buildCell(
                day: day,
                palette: palette,
                events: widget.data.familyFor(day),
                shifts: const [],
                memberColor: palette.base,
                isLowStimuli: isLowStimuli,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMemberRow(
      UserModel m, DayPalette palette, bool isLowStimuli) {
    final memberColor = _memberColor(m, palette);
    final initial =
        m.name.trim().isNotEmpty ? m.name.trim()[0].toUpperCase() : '?';
    final firstName = m.name.split(' ').first;

    return Row(
      children: [
        // Rad-etikett: Avatar i medlemsfärg + Förnamn (~190 px)
        SizedBox(
          width: DisplayTheme.memberColWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: memberColor,
                    shape: BoxShape.circle,
                    boxShadow: isLowStimuli
                        ? null
                        : [
                            BoxShadow(
                              color: memberColor.withValues(alpha: 0.35),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DisplayTheme.memberNameStyle.copyWith(
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 7 Dags-celler
        for (final day in widget.data.days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: _buildCell(
                day: day,
                palette: palette,
                events: widget.data.eventsFor(m, day),
                shifts: widget.data.shiftsFor(m, day),
                memberColor: memberColor,
                isLowStimuli: isLowStimuli,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCell({
    required DateTime day,
    required DayPalette palette,
    required List<QueryDocumentSnapshot> events,
    required List<QueryDocumentSnapshot> shifts,
    required Color memberColor,
    required bool isLowStimuli,
  }) {
    final isToday = sameCalendarDay(day, widget.now);
    final isPast = day.isBefore(
      DateTime(widget.now.year, widget.now.month, widget.now.day),
    );

    // Separera skola/schema från vanliga aktiviteter
    final scheduleDocs = <QueryDocumentSnapshot>[];
    final activityDocs = <QueryDocumentSnapshot>[];
    for (final doc in events) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') {
        scheduleDocs.add(doc);
      } else {
        activityDocs.add(doc);
      }
    }

    final renderedItems = <_CellItem>[];

    // 1. Arbetspass / Skift (Ramhändelse)
    for (final doc in shifts) {
      final d = doc.data() as Map<String, dynamic>;
      final interval = shiftInterval(d);
      final isNight = isNightShift(d);

      String pik = '💼';
      String label = 'Jobb';
      String timeStr;

      if (interval != null) {
        final sHm = DateFormat('HH:mm').format(interval.start);
        final eHm = DateFormat('HH:mm').format(interval.end);
        if (isNight) {
          pik = '🌙';
          label = 'Natt';
          if (sameCalendarDay(interval.start, day)) {
            timeStr = formatCompactTime(sHm, eHm);
          } else {
            timeStr = formatCompactTime('–$eHm');
          }
        } else {
          timeStr = formatCompactTime(sHm, eHm);
        }
      } else {
        final startField = (d['startTime'] ?? d['start']) as String? ?? '';
        final endField = (d['endTime'] ?? d['end']) as String? ?? '';
        timeStr = formatCompactTime(startField, endField);
      }

      final displayText = timeStr.isNotEmpty
          ? '$pik · $label · $timeStr'
          : '$pik · $label';

      renderedItems.add(_CellItem(
        isRam: true,
        widget: DisplayRamPlate(text: displayText, memberColor: memberColor),
      ));
    }

    // 2. Skolklumpning via buildScheduleDisplay (Ramhändelse)
    for (final entry in buildScheduleDisplay(scheduleDocs, clumpSchool: true)) {
      if (entry is ScheduleClusterEntry) {
        final maps = entry.docs.map((d) => d.data() as Map<String, dynamic>);
        final pik = maps.isNotEmpty ? schemaPiktogramFor(maps.first) : '🏫';
        final label = maps.isNotEmpty ? schemaLabelFor(maps.first) : 'Skola';
        final span = scheduleTimeSpan(maps);
        final timeStr = formatCompactTime(span.minStart ?? '', span.maxEnd);

        final displayText = timeStr.isNotEmpty
            ? '$pik · $label · $timeStr'
            : '$pik · $label';

        renderedItems.add(_CellItem(
          isRam: true,
          widget: DisplayRamPlate(text: displayText, memberColor: memberColor),
        ));
      }
    }

    // 3. Vanliga aktiviteter (Aktivitetschip: 3px vänsterkant, 2 rader)
    for (final doc in activityDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final isFolded = widget.foldedDocIds.contains(doc.id);
      renderedItems.add(_CellItem(
        isRam: false,
        widget: DisplayActivityCard(
          data: d,
          memberColor: memberColor,
          isFolded: isFolded,
          isLowStimuli: isLowStimuli,
        ),
      ));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellH = constraints.maxHeight;

        // Dynamisk beräkning av hur många element som ryms utan scroll/overflow:
        // Ramhändelse ≈ 36 px (inkl margin), Aktivitet ≈ 58 px (inkl margin), +N till ≈ 26 px
        var currentH = 0.0;
        var shownCount = 0;

        for (var i = 0; i < renderedItems.length; i++) {
          final isLast = i == renderedItems.length - 1;
          final itemH = renderedItems[i].isRam ? 36.0 : 58.0;
          final neededExact = currentH + itemH;
          final neededWithMore = currentH + itemH + 26.0;

          if (isLast && neededExact <= cellH) {
            shownCount++;
            currentH += itemH;
          } else if (!isLast && neededWithMore <= cellH) {
            shownCount++;
            currentH += itemH;
          } else if (shownCount == 0 && neededExact <= cellH) {
            shownCount++;
            currentH += itemH;
          } else {
            break;
          }
        }

        final hasMore = shownCount < renderedItems.length;
        final overflowCount = renderedItems.length - shownCount;

        return Opacity(
          opacity: isPast ? 0.45 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: isToday
                  ? palette.base.withValues(alpha: 0.09)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isToday
                    ? palette.base
                    : const Color(0xFFE2E5EE),
                width: isToday ? 2.0 : 1.0,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: renderedItems.isEmpty
                ? const SizedBox.expand()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < shownCount; i++) ...[
                        if (i > 0) const SizedBox(height: 4),
                        renderedItems[i].widget,
                      ],
                      if (hasMore) ...[
                        const SizedBox(height: 3),
                        Text(
                          '+$overflowCount till',
                          style: DisplayTheme.moreCountStyle.copyWith(
                            color: palette.deep,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

}

class _CellItem {
  final bool isRam;
  final Widget widget;

  _CellItem({required this.isRam, required this.widget});
}
