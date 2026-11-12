import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/schedule_display.dart';
import '../utils/schedule_time_utils.dart';
import '../utils/week_bucketing.dart';
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
  final void Function(UserModel member)? onMemberAvatarTap;
  final Map<String, Color>? presenceRingByUid;

  const WeekGrid({
    super.key,
    required this.members,
    required this.events,
    required this.weekStart,
    required this.onCellTap,
    this.shifts = const [],
    this.onFamilyRowTap,
    this.onMemberAvatarTap,
    this.presenceRingByUid,
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

  late WeekBucketingResult _bucketing;
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
        !identical(oldWidget.presenceRingByUid, widget.presenceRingByUid) ||
        oldWidget.events.length != widget.events.length ||
        oldWidget.members.length != widget.members.length ||
        oldWidget.shifts.length != widget.shifts.length) {
      _recurrenceCache.clear();
      _rebuildIndex();
    }
  }

  void _rebuildIndex() {
    _bucketing = bucketWeekData(
      members: widget.members,
      events: widget.events,
      shifts: widget.shifts,
      weekStart: widget.weekStart,
      recurrenceCache: _recurrenceCache,
    );
  }

  List<QueryDocumentSnapshot> _eventsFor(UserModel m, DateTime day) =>
      _bucketing.eventsFor(m, day);

  List<QueryDocumentSnapshot> _shiftsFor(UserModel m, DateTime day) =>
      _bucketing.shiftsFor(m, day);

  List<QueryDocumentSnapshot> _familyFor(DateTime day) =>
      _bucketing.familyFor(day);

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette();
    final today = DateTime.now();
    final wide = WindowSize.of(context).isWide;
    final cellH = wide ? _wideCellH : _compactCellH;
    final maxEvents = wide ? 4 : 2;
    final showFamily =
        _bucketing.hasFamilyEvents || widget.onFamilyRowTap != null;

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
                    child: GestureDetector(
                      onTap: widget.onMemberAvatarTap == null
                          ? null
                          : () => widget.onMemberAvatarTap!(m),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FamilyMemberAvatar(
                            member: m,
                            size: 34,
                            presenceColor:
                                widget.presenceRingByUid?[m.uid],
                          ),
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

    // Vecka: alltid klumpa skolan (clumpSchool: true).
    for (final entry in buildScheduleDisplay(
      schedule,
      clumpSchool: true,
    )) {
      if (slotsUsed >= maxEvents) break;
      if (entry is ScheduleClusterEntry) {
        rows.add(_scheduleBlock(entry.docs, rich: rich, label: entry.label));
        slotsUsed++;
      }
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
    String? label,
  }) {
    final text = label ??
        scheduleBlockLabel(
          scheduleDocs.map((d) => d.data() as Map<String, dynamic>),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
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
