import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../utils/schedule_time_utils.dart';
import 'member_avatar.dart';

/// Veckogrid: medlem × dag, Familjen-rad för events utan personer,
/// arbetspass som färgad rand i cellen.
class WeekGrid extends StatefulWidget {
  final List<UserModel> members;
  final List<QueryDocumentSnapshot> events;
  final List<QueryDocumentSnapshot> shifts;
  final DateTime weekStart;
  final void Function(UserModel member, DateTime day,
      List<QueryDocumentSnapshot> dayEvents) onCellTap;
  final void Function(DateTime day, List<QueryDocumentSnapshot> dayEvents)?
      onFamilyRowTap;

  const WeekGrid({
    super.key,
    required this.members,
    required this.events,
    required this.weekStart,
    required this.onCellTap,
    this.shifts = const [],
    this.onFamilyRowTap,
  });

  @override
  State<WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<WeekGrid> {
  static const double _compactCellW = 96;
  static const double _compactCellH = 72;
  static const double _wideCellH = 118;
  static const double _headerH = 40;
  static const double _avatarColW = 56;
  static const double _familyRowH = 56;

  /// uid → (dateKey → events)
  Map<String, Map<String, List<QueryDocumentSnapshot>>> _byMember = {};
  Map<String, List<QueryDocumentSnapshot>> _familyByDay = {};
  /// uid → (dateKey → shifts touching day)
  Map<String, Map<String, List<QueryDocumentSnapshot>>> _shiftsByMember = {};

  final Map<String, List<DateTime>> _recurrenceCache = {};

  @override
  void initState() {
    super.initState();
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(covariant WeekGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final weekChanged =
        dateKey(oldWidget.weekStart) != dateKey(widget.weekStart);
    if (weekChanged ||
        !identical(oldWidget.events, widget.events) ||
        !identical(oldWidget.members, widget.members) ||
        !identical(oldWidget.shifts, widget.shifts) ||
        oldWidget.events.length != widget.events.length ||
        oldWidget.members.length != widget.members.length ||
        oldWidget.shifts.length != widget.shifts.length) {
      _recurrenceCache.clear();
      _rebuildIndex();
    }
  }

  List<DateTime> _daysOfWeek() {
    return List.generate(
      7,
      (i) => DateTime(widget.weekStart.year, widget.weekStart.month,
          widget.weekStart.day + i),
    );
  }

  List<DateTime> _occurrenceDays(
      QueryDocumentSnapshot doc, Map<String, dynamic> d, List<DateTime> days) {
    final weekKey = dateKey(widget.weekStart);
    final cacheKey = '${doc.id}_$weekKey';
    final cached = _recurrenceCache[cacheKey];
    if (cached != null) return cached;

    final out = <DateTime>[];
    if (d['recurrence'] != null) {
      for (final day in days) {
        if (recurringOccursOnDay(d, day)) out.add(day);
      }
    } else {
      for (final day in days) {
        if (eventOccursOnDay(d, day)) out.add(day);
      }
    }
    _recurrenceCache[cacheKey] = out;
    return out;
  }

  void _rebuildIndex() {
    final days = _daysOfWeek();
    final map = <String, Map<String, List<QueryDocumentSnapshot>>>{};
    final shiftMap = <String, Map<String, List<QueryDocumentSnapshot>>>{};
    for (final m in widget.members) {
      map[m.uid] = {
        for (final day in days) dateKey(day): <QueryDocumentSnapshot>[]
      };
      shiftMap[m.uid] = {
        for (final day in days) dateKey(day): <QueryDocumentSnapshot>[]
      };
    }
    final family = {
      for (final day in days) dateKey(day): <QueryDocumentSnapshot>[]
    };

    for (final doc in widget.events) {
      final d = doc.data() as Map<String, dynamic>;
      final occ = _occurrenceDays(doc, d, days);
      if (occ.isEmpty) continue;

      if (eventHasNoPersons(d)) {
        for (final day in occ) {
          family[dateKey(day)]!.add(doc);
        }
        continue;
      }

      for (final m in widget.members) {
        if (!eventIncludesPerson(d, uid: m.uid, name: m.name)) continue;
        final byDay = map[m.uid]!;
        for (final day in occ) {
          byDay[dateKey(day)]!.add(doc);
        }
      }
    }

    for (final doc in widget.shifts) {
      final d = doc.data() as Map<String, dynamic>;
      for (final m in widget.members) {
        if (!assignedToPerson(d, uid: m.uid, name: m.name)) continue;
        final byDay = shiftMap[m.uid]!;
        for (final day in days) {
          if (shiftTouchesDay(d, day)) {
            byDay[dateKey(day)]!.add(doc);
          }
        }
      }
    }

    for (final byDay in map.values) {
      for (final list in byDay.values) {
        list.sort((a, b) {
          final ta = ((a.data() as Map)['time'] as String? ?? '99:99');
          final tb = ((b.data() as Map)['time'] as String? ?? '99:99');
          return ta.compareTo(tb);
        });
      }
    }
    for (final list in family.values) {
      list.sort((a, b) {
        final ta = ((a.data() as Map)['time'] as String? ?? '99:99');
        final tb = ((b.data() as Map)['time'] as String? ?? '99:99');
        return ta.compareTo(tb);
      });
    }

    _byMember = map;
    _familyByDay = family;
    _shiftsByMember = shiftMap;
  }

  List<QueryDocumentSnapshot> _eventsFor(UserModel m, DateTime day) =>
      _byMember[m.uid]?[dateKey(day)] ?? const [];

  List<QueryDocumentSnapshot> _shiftsFor(UserModel m, DateTime day) =>
      _shiftsByMember[m.uid]?[dateKey(day)] ?? const [];

  List<QueryDocumentSnapshot> _familyFor(DateTime day) =>
      _familyByDay[dateKey(day)] ?? const [];

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette();
    final today = DateTime.now();
    final wide = WindowSize.of(context).isWide;
    final cellH = wide ? _wideCellH : _compactCellH;
    final maxEvents = wide ? 4 : 2;
    final showFamily =
        _familyByDay.values.any((l) => l.isNotEmpty) || widget.onFamilyRowTap != null;

    Widget dayColumns({required double? cellW}) {
      return Row(
        children: List.generate(7, (i) {
          final day = DateTime(widget.weekStart.year, widget.weekStart.month,
              widget.weekStart.day + i);
          final isToday = day.year == today.year &&
              day.month == today.month &&
              day.day == today.day;
          final dayName = DateFormat('E d/M', 'sv').format(day);

          final column = Column(
            children: [
              SizedBox(
                height: _headerH,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppTheme.dayPalette(day.weekday).base
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isToday
                            ? AppTheme.getNpfTextColor(day.weekday)
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ),
              if (showFamily)
                _buildFamilyCell(day, isToday, palette, wide: wide),
              for (final m in widget.members)
                RepaintBoundary(
                  child: _buildCell(
                    context,
                    m,
                    day,
                    palette,
                    isToday,
                    cellH: cellH,
                    maxEvents: maxEvents,
                    rich: wide,
                  ),
                ),
            ],
          );

          if (cellW != null) {
            return SizedBox(width: cellW, child: column);
          }
          return Expanded(child: column);
        }),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            const SizedBox(height: _headerH),
            if (showFamily)
              SizedBox(
                height: _familyRowH,
                width: _avatarColW,
                child: Center(
                  child: Text(
                    'Familjen',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            for (final m in widget.members)
              RepaintBoundary(
                child: SizedBox(
                  height: cellH,
                  width: _avatarColW,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FamilyMemberAvatar(member: m, size: 34),
                        const SizedBox(height: 2),
                        Text(
                          m.name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: wide
              ? dayColumns(cellW: null)
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: dayColumns(cellW: _compactCellW),
                ),
        ),
      ],
    );
  }

  Widget _buildFamilyCell(
    DateTime day,
    bool isToday,
    DayPalette palette, {
    required bool wide,
  }) {
    final dayEvents = _familyFor(day);
    return InkWell(
      onTap: widget.onFamilyRowTap == null
          ? null
          : () => widget.onFamilyRowTap!(day, dayEvents),
      child: Container(
        height: _familyRowH,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday
                ? palette.base.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.05),
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: dayEvents.isEmpty
            ? const SizedBox.expand()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final doc in dayEvents.take(wide ? 2 : 1))
                    _miniEvent(doc.data() as Map<String, dynamic>, rich: wide),
                  if (dayEvents.length > (wide ? 2 : 1))
                    Text(
                      '+${dayEvents.length - (wide ? 2 : 1)}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: palette.deep,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    UserModel m,
    DateTime day,
    DayPalette palette,
    bool isToday, {
    required double cellH,
    required int maxEvents,
    required bool rich,
  }) {
    final dayEvents = _eventsFor(m, day);
    final dayShifts = _shiftsFor(m, day);
    final schedule = <QueryDocumentSnapshot>[];
    final activities = <QueryDocumentSnapshot>[];
    for (final doc in dayEvents) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') {
        schedule.add(doc);
      } else {
        activities.add(doc);
      }
    }

    final rows = <Widget>[];
    var slotsUsed = 0;

    if (schedule.isNotEmpty && slotsUsed < maxEvents) {
      rows.add(_scheduleBlock(schedule, rich: rich));
      slotsUsed++;
    }

    final activitySlots = maxEvents - slotsUsed;
    final shownActivities = activities.take(activitySlots).toList();
    for (final doc in shownActivities) {
      rows.add(
        _miniEvent(doc.data() as Map<String, dynamic>, rich: rich),
      );
    }
    final hiddenActivities = activities.length - shownActivities.length;

    late final Color memberColor;
    try {
      memberColor = Color(m.colorValue);
    } catch (_) {
      memberColor = palette.base;
    }

    return InkWell(
      onTap: () => widget.onCellTap(m, day, dayEvents),
      child: Container(
        height: cellH,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday
                ? palette.base.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.05),
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            if (dayShifts.isNotEmpty)
              Positioned(
                left: 0,
                top: 4,
                bottom: 4,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: memberColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(left: dayShifts.isNotEmpty ? 6 : 0),
              child: dayEvents.isEmpty && dayShifts.isEmpty
                  ? const SizedBox.expand()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (dayShifts.isNotEmpty && dayEvents.isEmpty)
                          Text(
                            '💼',
                            style: TextStyle(fontSize: rich ? 12 : 11),
                          ),
                        ...rows,
                        if (hiddenActivities > 0)
                          Text(
                            '+$hiddenActivities till',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: palette.deep,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleBlock(
    List<QueryDocumentSnapshot> scheduleDocs, {
    required bool rich,
  }) {
    String? minStart;
    String? maxEnd;
    for (final doc in scheduleDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final t = (d['time'] as String? ?? '').trim();
      if (t.isEmpty) continue;
      final endRaw = (d['endTime'] as String? ?? '').trim();
      final end = endRaw.isNotEmpty ? endRaw : t;
      if (minStart == null || t.compareTo(minStart) < 0) minStart = t;
      if (maxEnd == null || end.compareTo(maxEnd) > 0) maxEnd = end;
    }
    final label = (minStart != null && maxEnd != null)
        ? '🏫 $minStart–$maxEnd'
        : '🏫';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: rich ? 10.5 : 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _miniEvent(Map<String, dynamic> d, {required bool rich}) {
    final t = (d['time'] as String? ?? '').trim();
    final end = (d['endTime'] as String? ?? '').trim();
    final pik = d['piktogram'] as String? ?? '📅';
    final title = d['title'] as String? ?? '';
    final timeLabel =
        rich && t.isNotEmpty && end.isNotEmpty ? '$t–$end' : t;
    final label = rich
        ? (timeLabel.isEmpty ? title : '$timeLabel · $title')
        : (t.isEmpty ? title : '$t $title');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(pik, style: TextStyle(fontSize: rich ? 12 : 11)),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: rich ? 10.5 : 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
