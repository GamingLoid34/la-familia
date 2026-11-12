import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../utils/conflict_detector.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../utils/schedule_display.dart';
import '../utils/schedule_time_utils.dart';
import 'activity_detail_sheet.dart';

/// Veckolista för mobil: vertikal 7-dagarsvy (Mån–Sön).
/// Kronologiska rader, medlemsprickar, nattpass, inline-konflikter och expandering.
class WeekList extends StatefulWidget {
  final List<UserModel> members;
  final List<QueryDocumentSnapshot> events;
  final List<QueryDocumentSnapshot> shifts;
  final DateTime weekStart;
  final void Function(UserModel member, DateTime day,
      List<QueryDocumentSnapshot> dayEvents)? onCellTap;
  final void Function(DateTime day, List<QueryDocumentSnapshot> dayEvents)?
      onFamilyRowTap;
  final void Function(UserModel member)? onMemberAvatarTap;
  final void Function(ScheduleConflict conflict)? onConflictTap;
  final Map<String, Color>? presenceRingByUid;

  const WeekList({
    super.key,
    required this.members,
    required this.events,
    required this.weekStart,
    this.onCellTap,
    this.shifts = const [],
    this.onFamilyRowTap,
    this.onMemberAvatarTap,
    this.onConflictTap,
    this.presenceRingByUid,
  });

  @override
  State<WeekList> createState() => _WeekListState();
}

class _WeekListState extends State<WeekList> {
  final Set<int> _expandedDays = {};
  final Set<String> _expandedClusters = {};
  late final List<GlobalKey> _dayKeys;
  bool _hasAutoScrolled = false;

  @override
  void initState() {
    super.initState();
    _dayKeys = List.generate(7, (_) => GlobalKey());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTodayIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant WeekList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (dateKey(oldWidget.weekStart) != dateKey(widget.weekStart)) {
      _expandedDays.clear();
      _expandedClusters.clear();
      _hasAutoScrolled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTodayIfNeeded();
      });
    }
  }

  List<DateTime> _daysOfWeek() {
    return List.generate(
      7,
      (i) => DateTime(widget.weekStart.year, widget.weekStart.month,
          widget.weekStart.day + i),
    );
  }

  void _scrollToTodayIfNeeded() {
    if (_hasAutoScrolled || !mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = _daysOfWeek();

    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      if (d.year == today.year && d.month == today.month && d.day == today.day) {
        final keyContext = _dayKeys[i].currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(
            keyContext,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.08,
          );
        }
        _hasAutoScrolled = true;
        break;
      }
    }
  }

  void _openEventDetail(QueryDocumentSnapshot doc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ActivityDetailSheet(docSnapshot: doc),
    );
  }

  UserModel? _findMemberByUidOrName(String uid, String name) {
    for (final m in widget.members) {
      if (uid.isNotEmpty && m.uid == uid) return m;
      if (name.isNotEmpty && m.name == name) return m;
    }
    return null;
  }

  String _schedulePersonKey(Map<String, dynamic> d) {
    final uids = (d['personUids'] as List?)?.cast<String>() ?? const [];
    if (uids.isNotEmpty) return 'u:${uids.first}';
    final whoUid = (d['whoUid'] as String? ?? '').trim();
    if (whoUid.isNotEmpty) return 'u:$whoUid';
    final persons = (d['persons'] as List? ?? []).cast<String>();
    if (persons.isNotEmpty) return 'n:${persons.first}';
    final who = (d['who'] as String? ?? '').trim();
    if (who.isNotEmpty) return 'n:$who';
    return 'shared';
  }

  UserModel? _findMemberFromKey(String key, List<UserModel> members) {
    if (key.startsWith('u:')) {
      final uid = key.substring(2);
      for (final m in members) {
        if (m.uid == uid) return m;
      }
    }
    if (key.startsWith('n:')) {
      final name = key.substring(2);
      for (final m in members) {
        if (m.name == name) return m;
      }
    }
    return null;
  }

  List<UserModel> _membersForEvent(Map<String, dynamic> d) {
    final out = <UserModel>[];
    final uids = (d['personUids'] as List?)?.cast<String>() ?? [];
    final names = (d['persons'] as List?)?.cast<String>() ?? [];

    for (final u in uids) {
      final m = _findMemberByUidOrName(u, '');
      if (m != null && !out.any((x) => x.uid == m.uid)) {
        out.add(m);
      }
    }
    for (final n in names) {
      final m = _findMemberByUidOrName('', n);
      if (m != null && !out.any((x) => x.uid == m.uid)) {
        out.add(m);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysOfWeek();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isLowStimuli = AppTheme.lowStimuli;

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      itemCount: 7,
      itemBuilder: (context, dayIndex) {
        final day = days[dayIndex];
        final isDayToday =
            day.year == today.year && day.month == today.month && day.day == today.day;
        final dayColor = AppTheme.getDayAccentColor(day.weekday);

        // Händelser för dagen
        final dayEvents = widget.events.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          if (d['recurrence'] != null) {
            return recurringOccursOnDay(d, day);
          }
          return eventOccursOnDay(d, day);
        }).toList();

        // Arbetspass som berör dagen (inklusive nattpass)
        final dayShifts = widget.shifts.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return shiftTouchesDay(d, day);
        }).toList();

        // Konflikter för denna dag
        final dayConflicts = detectAllConflicts(
          members: widget.members,
          events: widget.events,
          shifts: widget.shifts,
          weekStart: day,
          dayCount: 1,
        );

        // Separera schemahändelser och vanliga aktiviteter
        final scheduleByPerson = <String, List<QueryDocumentSnapshot>>{};
        final untimedEvents = <QueryDocumentSnapshot>[];
        final timedEvents = <QueryDocumentSnapshot>[];

        for (final doc in dayEvents) {
          final d = doc.data() as Map<String, dynamic>;
          if (d['planningImportKind'] == 'schedule') {
            final key = _schedulePersonKey(d);
            scheduleByPerson.putIfAbsent(key, () => []).add(doc);
          } else {
            final timeStr = (d['time'] as String? ?? '').trim();
            if (timeStr.isEmpty) {
              untimedEvents.add(doc);
            } else {
              timedEvents.add(doc);
            }
          }
        }

        timedEvents.sort((a, b) {
          final da = a.data() as Map<String, dynamic>;
          final db = b.data() as Map<String, dynamic>;
          final ta = (da['time'] as String? ?? '').trim();
          final tb = (db['time'] as String? ?? '').trim();
          return ta.compareTo(tb);
        });

        // Samla alla rader för dagen
        final allEntries = <_WeekListEntry>[];

        // 1. Skolklumpar (clumpSchool: true per person)
        for (final entry in scheduleByPerson.entries) {
          final docs = List<QueryDocumentSnapshot>.from(entry.value);
          if (docs.isEmpty) continue;
          final firstDoc = docs.first.data() as Map<String, dynamic>;
          final schemaLabel = schemaLabelFor(firstDoc);
          final schemaPik = schemaPiktogramFor(firstDoc);
          final member = _findMemberFromKey(entry.key, widget.members);

          final dispList = buildScheduleDisplay(
            docs,
            clumpSchool: true,
            title: schemaLabel,
            piktogram: schemaPik,
          );
          for (final disp in dispList) {
            if (disp is ScheduleClusterEntry) {
              allEntries.add(_WeekListEntry.scheduleCluster(
                cluster: disp,
                member: member,
              ));
            }
          }
        }

        // 2. Otidsatta aktiviteter
        for (final doc in untimedEvents) {
          allEntries.add(_WeekListEntry.event(doc: doc, isUntimed: true));
        }

        // 3. Tidsatta aktiviteter
        for (final doc in timedEvents) {
          allEntries.add(_WeekListEntry.event(doc: doc, isUntimed: false));
        }

        // 4. Arbetspass
        for (final shiftDoc in dayShifts) {
          allEntries.add(_WeekListEntry.shift(shiftDoc: shiftDoc, currentDay: day));
        }

        // Sortera kronologiskt
        allEntries.sort((a, b) {
          if (a.isUntimed && !b.isUntimed) return -1;
          if (!a.isUntimed && b.isUntimed) return 1;
          return a.sortKey.compareTo(b.sortKey);
        });

        final totalEntriesCount = allEntries.length;
        final isExpanded = _expandedDays.contains(dayIndex);
        final visibleEntries = isExpanded
            ? allEntries
            : allEntries.take(4).toList();
        final hasMore = totalEntriesCount > 4 && !isExpanded;

        String dayName;
        try {
          dayName = DateFormat('EEEE d MMM', 'sv').format(day);
        } catch (_) {
          dayName = DateFormat('EEEE d MMM').format(day);
        }
        if (dayName.isNotEmpty) {
          dayName = '${dayName[0].toUpperCase()}${dayName.substring(1)}';
        }

        return Container(
          key: _dayKeys[dayIndex],
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AppTheme.cardDecoration(radius: 16).copyWith(
            border: isDayToday
                ? Border.all(color: dayColor, width: 2)
                : Border.all(color: Colors.grey.shade200),
            boxShadow: isLowStimuli || !isDayToday
                ? null
                : [
                    BoxShadow(
                      color: dayColor.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dagrubrik
              Material(
                color: isDayToday
                    ? dayColor.withValues(alpha: 0.12)
                    : const Color(0xFFFAFAFA),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: InkWell(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  onTap: () {
                    widget.onFamilyRowTap?.call(day, dayEvents);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        if (isDayToday) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: dayColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'IDAG',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          dayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDayToday ? dayColor : AppTheme.getTextColor(),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),

              // Inline-konflikter
              if (dayConflicts.isNotEmpty) ...[
                for (final conflict in dayConflicts)
                  _buildInlineConflictRow(conflict, dayColor),
              ],

              // Rader för dagen
              if (allEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Text(
                    'Inget planerat',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade400,
                    ),
                  ),
                )
              else ...[
                for (var i = 0; i < visibleEntries.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF5F5F5)),
                  _buildEntryRow(visibleEntries[i], dayColor, day),
                ],

                // "＋N till" knapp
                if (hasMore)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedDays.add(dayIndex);
                      });
                    },
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: Text(
                          '＋${totalEntriesCount - 4} till',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: dayColor,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (isExpanded && totalEntriesCount > 4)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedDays.remove(dayIndex);
                      });
                    },
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          'Visa färre',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineConflictRow(ScheduleConflict conflict, Color dayColor) {
    String conflictText;
    if (conflict.isPickup) {
      conflictText = conflict.pickupLabel ?? 'Hämtningskrock';
    } else {
      final timeStr = DateFormat('HH:mm').format(conflict.start);
      conflictText = '$timeStr — båda upptagna';
    }

    return Material(
      color: const Color(0xFFFFF1F2),
      child: InkWell(
        onTap: () {
          widget.onConflictTap?.call(conflict);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Text('🚨', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conflictText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFBE123C),
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: Color(0xFFBE123C),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryRow(_WeekListEntry entry, Color dayColor, DateTime day) {
    if (entry.isScheduleCluster) {
      return _buildClusterRow(entry, dayColor, day);
    }
    if (entry.isShift) {
      return _buildShiftRow(entry, dayColor);
    }
    return _buildEventRow(entry, dayColor);
  }

  Widget _buildClusterRow(_WeekListEntry entry, Color dayColor, DateTime day) {
    final docs = entry.clusterDocs ?? const [];
    if (docs.isEmpty) return const SizedBox.shrink();

    final firstDoc = docs.first.data() as Map<String, dynamic>;
    final piktogram = schemaPiktogramFor(firstDoc);
    final schemaLabel = schemaLabelFor(firstDoc);
    final maps = docs.map((d) => d.data() as Map<String, dynamic>);
    final span = scheduleTimeSpan(maps);
    final timeStr = span.minStart != null && span.maxEnd != null
        ? '${span.minStart}–${span.maxEnd}'
        : (span.minStart ?? '');
    final member = entry.member;
    final personName = member?.name ?? (firstDoc['who'] as String? ?? '');

    Color personColor = dayColor;
    if (member != null) {
      try {
        personColor = Color(member.colorValue);
      } catch (_) {}
    }

    final clusterKey = '${dateKey(day)}_${member?.uid ?? personName}_${entry.sortKey}';
    final isExpanded = _expandedClusters.contains(clusterKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedClusters.remove(clusterKey);
              } else {
                _expandedClusters.add(clusterKey);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    timeStr.isNotEmpty ? timeStr : '—',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: timeStr.isNotEmpty
                          ? Colors.grey.shade700
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(piktogram, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    schemaLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (personName.isNotEmpty) ...[
                      Text(
                        personName.split(' ').first,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: personColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            color: const Color(0xFFE8F0FE).withValues(alpha: 0.35),
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Column(
              children: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final t = (d['time'] as String? ?? '').trim();
                final end = (d['endTime'] as String? ?? '').trim();
                final title = (d['title'] as String? ?? 'Lektion').trim();
                final room = (d['location'] as String? ?? d['room'] as String? ?? '').trim();
                final pik = (d['piktogram'] as String? ?? '📚').trim();
                final lessonTime = t.isEmpty ? '' : (end.isEmpty ? t : '$t–$end');

                return InkWell(
                  onTap: () => _openEventDetail(doc),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(36, 6, 14, 6),
                    child: Row(
                      children: [
                        if (lessonTime.isNotEmpty) ...[
                          SizedBox(
                            width: 54,
                            child: Text(
                              lessonTime,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(pik, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            room.isNotEmpty ? '$title ($room)' : title,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildEventRow(_WeekListEntry entry, Color dayColor) {
    final doc = entry.doc!;
    final d = doc.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? 'Aktivitet';
    final piktogram = d['piktogram'] as String? ?? '📅';
    final timeStr = (d['time'] as String?)?.trim() ?? '';
    final endTimeStr = (d['endTime'] as String?)?.trim() ?? '';

    String displayTime = '—';
    if (timeStr.isNotEmpty) {
      displayTime = endTimeStr.isNotEmpty ? '$timeStr–$endTimeStr' : timeStr;
    }

    final involvedMembers = _membersForEvent(d);
    final hasNoPersons = eventHasNoPersons(d);

    return InkWell(
      onTap: () => _openEventDetail(doc),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Tid
            SizedBox(
              width: 58,
              child: Text(
                displayTime,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: timeStr.isNotEmpty
                      ? Colors.grey.shade700
                      : Colors.grey.shade400,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Piktogram
            Text(piktogram, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            // Titel
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Medlemsprickar eller familjeikon
            if (hasNoPersons || involvedMembers.isEmpty)
              const Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 14))
            else if (involvedMembers.length == 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    involvedMembers.first.name.split(' ').first,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: () {
                        try {
                          return Color(involvedMembers.first.colorValue);
                        } catch (_) {
                          return dayColor;
                        }
                      }(),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: involvedMembers.map((m) {
                  Color c;
                  try {
                    c = Color(m.colorValue);
                  } catch (_) {
                    c = dayColor;
                  }
                  return Container(
                    margin: const EdgeInsets.only(left: 3),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftRow(_WeekListEntry entry, Color dayColor) {
    final doc = entry.shiftDoc!;
    final d = doc.data() as Map<String, dynamic>;
    final personName = (d['who'] as String? ?? '').trim();
    final whoUid = (d['whoUid'] as String? ?? '').trim();
    final member = _findMemberByUidOrName(whoUid, personName);

    Color personColor = dayColor;
    if (member != null) {
      try {
        personColor = Color(member.colorValue);
      } catch (_) {}
    }

    final startStr = (d['startTime'] as String? ?? d['start'] as String? ?? '').trim();
    final endStr = (d['endTime'] as String? ?? d['end'] as String? ?? '').trim();
    final isNight = isNightShift(d);

    String timeLabel = '';
    if (startStr.isNotEmpty && endStr.isNotEmpty) {
      timeLabel = '$startStr–$endStr';
    } else if (startStr.isNotEmpty) {
      timeLabel = startStr;
    } else {
      timeLabel = 'Pass';
    }

    final shiftTitle = isNight ? '🌙 Nattpass' : 'Arbetspass';

    return Container(
      color: personColor.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: personColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Text('💼', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shiftTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (personName.isNotEmpty) ...[
                  Text(
                    personName.split(' ').first,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: personColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekListEntry {
  final QueryDocumentSnapshot? doc;
  final QueryDocumentSnapshot? shiftDoc;
  final List<QueryDocumentSnapshot>? clusterDocs;
  final String? clusterLabel;
  final UserModel? member;
  final bool isShift;
  final bool isScheduleCluster;
  final bool isUntimed;
  final String sortKey;

  _WeekListEntry._({
    this.doc,
    this.shiftDoc,
    this.clusterDocs,
    this.clusterLabel,
    this.member,
    required this.isShift,
    required this.isScheduleCluster,
    required this.isUntimed,
    required this.sortKey,
  });

  factory _WeekListEntry.event({
    required QueryDocumentSnapshot doc,
    required bool isUntimed,
  }) {
    final d = doc.data() as Map<String, dynamic>;
    final timeStr = (d['time'] as String? ?? '').trim();
    return _WeekListEntry._(
      doc: doc,
      isShift: false,
      isScheduleCluster: false,
      isUntimed: isUntimed,
      sortKey: timeStr.isEmpty ? '99:99' : timeStr,
    );
  }

  factory _WeekListEntry.shift({
    required QueryDocumentSnapshot shiftDoc,
    required DateTime currentDay,
  }) {
    final d = shiftDoc.data() as Map<String, dynamic>;
    final startStr = (d['startTime'] as String? ?? d['start'] as String? ?? '').trim();
    return _WeekListEntry._(
      shiftDoc: shiftDoc,
      isShift: true,
      isScheduleCluster: false,
      isUntimed: false,
      sortKey: startStr.isEmpty ? '12:00' : startStr,
    );
  }

  factory _WeekListEntry.scheduleCluster({
    required ScheduleClusterEntry cluster,
    required UserModel? member,
  }) {
    return _WeekListEntry._(
      clusterDocs: cluster.docs,
      clusterLabel: cluster.label,
      member: member,
      isShift: false,
      isScheduleCluster: true,
      isUntimed: false,
      sortKey: cluster.sortKey,
    );
  }
}

