import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/chore_service.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../utils/schedule_time_utils.dart';
import 'activity_detail_sheet.dart';
import 'add_event_sheet.dart';
import 'member_avatar.dart';

/// Syssla utan `dueDate` visas alla dagar; med datum bara den dagen.
bool _choreVisibleOnDay(Map<String, dynamic> d, DateTime day) {
  final raw = d['dueDate'];
  if (raw == null) return true;
  if (raw is String && raw.isEmpty) return true;
  if (raw is String) {
    final parsed = parseDate(raw);
    if (parsed == null) return true;
    return parsed.year == day.year &&
        parsed.month == day.month &&
        parsed.day == day.day;
  }
  return true;
}

/// Dagvy inspirerad av FamilyWall — en kolumn per familjemedlem.
class KalenderDayView extends StatelessWidget {
  final List<UserModel> members;
  final DateTime selectedDay;
  final List<QueryDocumentSnapshot> events;
  final List<QueryDocumentSnapshot> shifts;
  final List<QueryDocumentSnapshot> chores;
  final ValueChanged<DateTime> onDayChanged;
  final UserModel? currentUser;
  final String familyId;
  final void Function(UserModel member)? onOpenMember;

  const KalenderDayView({
    super.key,
    required this.members,
    required this.selectedDay,
    required this.events,
    required this.shifts,
    required this.chores,
    required this.onDayChanged,
    this.currentUser,
    required this.familyId,
    this.onOpenMember,
  });

  List<QueryDocumentSnapshot> _familyEventsForDay() {
    return events.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!eventHasNoPersons(d)) return false;
      return eventOccursOnDay(d, selectedDay);
    }).toList()
      ..sort((a, b) {
        final ta = ((a.data() as Map)['time'] as String? ?? '99:99');
        final tb = ((b.data() as Map)['time'] as String? ?? '99:99');
        return ta.compareTo(tb);
      });
  }

  List<QueryDocumentSnapshot> _memberEvents(UserModel member) {
    return events.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (eventHasNoPersons(d)) return false;
      if (!eventOccursOnDay(d, selectedDay)) return false;
      return eventIncludesPerson(d, uid: member.uid, name: member.name);
    }).toList();
  }

  List<QueryDocumentSnapshot> _memberShifts(UserModel member) {
    return shifts.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!assignedToPerson(d, uid: member.uid, name: member.name)) {
        return false;
      }
      return shiftTouchesDay(d, selectedDay);
    }).toList()
      ..sort((a, b) {
        final ta = timeSortKey(a.data() as Map<String, dynamic>, isWork: true);
        final tb = timeSortKey(b.data() as Map<String, dynamic>, isWork: true);
        return ta.compareTo(tb);
      });
  }

  List<QueryDocumentSnapshot> _memberChores(UserModel member) {
    return chores.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!_choreVisibleOnDay(d, selectedDay)) return false;
      return assignedToPerson(d, uid: member.uid, name: member.name);
    }).toList()
      ..sort((a, b) {
        final da = (a.data() as Map)['isDone'] == true ? 1 : 0;
        final db = (b.data() as Map)['isDone'] == true ? 1 : 0;
        return da.compareTo(db);
      });
  }

  void _shiftDay(int delta) {
    final d = selectedDay;
    onDayChanged(DateTime(d.year, d.month, d.day + delta));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette(selectedDay.weekday);
    final isToday = _isSameCalendarDay(selectedDay, DateTime.now());
    final familyEvents = _familyEventsForDay();
    final wide = WindowSize.of(context).isWide;
    final dayLabel = DateFormat('EEEE d MMMM', 'sv').format(selectedDay);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity;
        if (v == null) return;
        if (v > 200) _shiftDay(-1);
        if (v < -200) _shiftDay(1);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDateRow(context, dayLabel, isToday, palette),
          if (familyEvents.isNotEmpty)
            _buildFamilyStrip(context, familyEvents),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: members
                        .map((m) => Expanded(
                              child: _MemberColumn(
                                member: m,
                                selectedDay: selectedDay,
                                events: _memberEvents(m),
                                shifts: _memberShifts(m),
                                chores: _memberChores(m),
                                familyId: familyId,
                                familyMembers: members,
                                currentUser: currentUser,
                                onOpenMember: onOpenMember,
                              ),
                            ))
                        .toList(),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: members
                          .map((m) => SizedBox(
                                width: 148,
                                child: _MemberColumn(
                                  member: m,
                                  selectedDay: selectedDay,
                                  events: _memberEvents(m),
                                  shifts: _memberShifts(m),
                                  chores: _memberChores(m),
                                  familyId: familyId,
                                  familyMembers: members,
                                  currentUser: currentUser,
                                  onOpenMember: onOpenMember,
                                ),
                              ))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(
    BuildContext context,
    String dayLabel,
    bool isToday,
    DayPalette palette,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _shiftDay(-1),
          ),
          Expanded(
            child: Center(
              child: Text(
                dayLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (!isToday)
            TextButton(
              onPressed: () {
                final now = DateTime.now();
                onDayChanged(
                    DateTime(now.year, now.month, now.day));
              },
              child: Text(
                'Idag',
                style: TextStyle(
                  color: palette.deep,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _shiftDay(1),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyStrip(
    BuildContext context,
    List<QueryDocumentSnapshot> familyEvents,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Familjen',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          ...familyEvents.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final t = (d['time'] as String? ?? '').trim();
            final end = (d['endTime'] as String? ?? '').trim();
            final pik = d['piktogram'] as String? ?? '📅';
            final title = d['title'] as String? ?? '';
            final timeLabel = t.isNotEmpty && end.isNotEmpty
                ? '$t–$end'
                : (t.isNotEmpty ? t : '');
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () => _openActivity(context, doc),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Text(pik, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        timeLabel.isEmpty ? title : '$timeLabel · $title',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _openActivity(BuildContext context, QueryDocumentSnapshot doc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ActivityDetailSheet(docSnapshot: doc),
    );
  }
}

class _MemberColumn extends StatelessWidget {
  final UserModel member;
  final DateTime selectedDay;
  final List<QueryDocumentSnapshot> events;
  final List<QueryDocumentSnapshot> shifts;
  final List<QueryDocumentSnapshot> chores;
  final String familyId;
  final List<UserModel> familyMembers;
  final UserModel? currentUser;
  final void Function(UserModel member)? onOpenMember;

  const _MemberColumn({
    required this.member,
    required this.selectedDay,
    required this.events,
    required this.shifts,
    required this.chores,
    required this.familyId,
    required this.familyMembers,
    this.currentUser,
    this.onOpenMember,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette(selectedDay.weekday);
    final items = _buildSortedItems(context);

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onOpenMember == null ? null : () => onOpenMember!(member),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
              child: Column(
                children: [
                  FamilyMemberAvatar(member: member, size: 36),
                  const SizedBox(height: 4),
                  Text(
                    member.name.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'Inget',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    children: items,
                  ),
          ),
          InkWell(
            onTap: () => _openAddEvent(context),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: palette.base.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Icon(Icons.add_rounded, color: palette.deep, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  void _openAddEvent(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEventSheet(
        selectedDay: selectedDay,
        familyMembers: familyMembers,
        familyId: familyId,
        initialPersonUids: [member.uid],
      ),
    );
  }

  List<Widget> _buildSortedItems(BuildContext context) {
    final schedule = <QueryDocumentSnapshot>[];
    final activities = <QueryDocumentSnapshot>[];
    for (final doc in events) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') {
        schedule.add(doc);
      } else {
        activities.add(doc);
      }
    }

    activities.sort((a, b) {
      final ta = timeSortKey(a.data() as Map<String, dynamic>);
      final tb = timeSortKey(b.data() as Map<String, dynamic>);
      return ta.compareTo(tb);
    });

    final sorted = <({String key, Widget widget})>[];

    if (schedule.isNotEmpty) {
      sorted.add((
        key: _scheduleSortKey(schedule),
        widget: _ScheduleBlock(docs: schedule),
      ));
    }

    for (final doc in shifts) {
      final d = doc.data() as Map<String, dynamic>;
      final start = (d['startTime'] as String? ?? '').trim();
      final end = (d['endTime'] as String? ?? '').trim();
      final label = start.isNotEmpty && end.isNotEmpty
          ? '💼 $start–$end'
          : '💼 $start';
      sorted.add((
        key: timeSortKey(d, isWork: true),
        widget: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ));
    }

    for (final doc in activities) {
      final d = doc.data() as Map<String, dynamic>;
      sorted.add((
        key: timeSortKey(d),
        widget: _ActivityTile(
          doc: doc,
          data: d,
          onTap: () {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => ActivityDetailSheet(docSnapshot: doc),
            );
          },
        ),
      ));
    }

    for (final doc in chores) {
      sorted.add((
        key: 'z_${doc.id}',
        widget: _DayChoreTile(
          doc: doc,
          selectedDay: selectedDay,
        ),
      ));
    }

    sorted.sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => e.widget).toList();
  }

  String _scheduleSortKey(List<QueryDocumentSnapshot> docs) {
    String? minStart;
    for (final doc in docs) {
      final t = ((doc.data() as Map)['time'] as String? ?? '').trim();
      if (t.isEmpty) continue;
      if (minStart == null || t.compareTo(minStart) < 0) minStart = t;
    }
    return minStart ?? '00:00';
  }
}

class _ScheduleBlock extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const _ScheduleBlock({required this.docs});

  @override
  Widget build(BuildContext context) {
    String? minStart;
    String? maxEnd;
    for (final doc in docs) {
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F0FE),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ActivityTile({
    required this.doc,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = (data['time'] as String? ?? '').trim();
    final pik = data['piktogram'] as String? ?? '📅';
    final title = data['title'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.isNotEmpty)
                  SizedBox(
                    width: 42,
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                Text(pik, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChoreTile extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final DateTime selectedDay;

  const _DayChoreTile({
    required this.doc,
    required this.selectedDay,
  });

  @override
  State<_DayChoreTile> createState() => _DayChoreTileState();
}

class _DayChoreTileState extends State<_DayChoreTile> {
  bool _saving = false;

  Future<void> _toggle(bool current) async {
    setState(() => _saving = true);
    try {
      await ChoreService.completeChore(
        choreId: widget.doc.id,
        done: !current,
        dayKey: dateKey(widget.selectedDay),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final isDone = d['isDone'] == true;
    final dayColor = AppTheme.getDayAccentColor(widget.selectedDay.weekday);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _saving ? null : () => _toggle(isDone),
            child: SizedBox(
              width: 22,
              height: 22,
              child: _saving
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Container(
                      decoration: BoxDecoration(
                        color: isDone ? dayColor : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDone ? dayColor : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: isDone
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : null,
                    ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: isDone ? TextDecoration.lineThrough : null,
                color: isDone ? Colors.grey : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
