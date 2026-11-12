import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../services/chore_service.dart';
import '../utils/chore_utils.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../utils/schedule_time_utils.dart';
import '../screens/staddag_page.dart';
import 'activity_detail_sheet.dart';
import 'add_event_sheet.dart';

/// Förberäknad pill per dag — byggs en gång per (events, chores, månad).
class MonthDayPills {
  final List<MonthPill> activityPills;
  final MonthPill? schoolPill;
  final MonthPill? chorePill;
  final List<QueryDocumentSnapshot> events;
  final List<QueryDocumentSnapshot> chores;

  const MonthDayPills({
    required this.activityPills,
    this.schoolPill,
    this.chorePill,
    required this.events,
    required this.chores,
  });

  List<MonthPill> visiblePills({required int maxSlots}) {
    final out = <MonthPill>[];
    if (schoolPill != null) out.add(schoolPill!);
    for (final p in activityPills) {
      if (out.length >= maxSlots) break;
      out.add(p);
    }
    if (chorePill != null && out.length < maxSlots) {
      out.add(chorePill!);
    }
    return out;
  }

  int hiddenCount({required int maxSlots}) {
    var total = (schoolPill != null ? 1 : 0) + activityPills.length;
    if (chorePill != null) total++;
    final shown = visiblePills(maxSlots: maxSlots).length;
    return (total - shown).clamp(0, 999);
  }
}

class MonthPill {
  final Color background;
  final String label;
  final bool thin;

  const MonthPill({
    required this.background,
    required this.label,
    this.thin = false,
  });
}

/// Bygger dag→pills-index för synlig månad (inkl. utfyllnadsdagar).
Map<String, MonthDayPills> buildMonthDayIndex({
  required DateTime month,
  required List<QueryDocumentSnapshot> events,
  required List<QueryDocumentSnapshot> chores,
  required List<UserModel> members,
  required Color accent,
}) {
  final first = DateTime(month.year, month.month, 1);
  final startOffset = (first.weekday - DateTime.monday) % 7;
  final gridStart = first.subtract(Duration(days: startOffset));
  final days = List.generate(42, (i) => DateTime(
        gridStart.year,
        gridStart.month,
        gridStart.day + i,
      ));

  final eventsByDay = <String, List<QueryDocumentSnapshot>>{
    for (final d in days) dateKey(d): <QueryDocumentSnapshot>[],
  };
  final choresByDay = <String, List<QueryDocumentSnapshot>>{
    for (final d in days) dateKey(d): <QueryDocumentSnapshot>[],
  };

  for (final doc in events) {
    final d = doc.data() as Map<String, dynamic>;
    for (final day in days) {
      if (eventOccursOnDay(d, day)) {
        eventsByDay[dateKey(day)]!.add(doc);
      }
    }
  }

  for (final doc in chores) {
    final d = doc.data() as Map<String, dynamic>;
    for (final day in days) {
      if (choreOccursOnDay(d, day)) {
        choresByDay[dateKey(day)]!.add(doc);
      }
    }
  }

  Color colorForEvent(Map<String, dynamic> d) {
    final uids = (d['personUids'] as List?)?.cast<String>() ?? const [];
    if (uids.isNotEmpty) {
      for (final m in members) {
        if (m.uid == uids.first) {
          try {
            return Color(m.colorValue);
          } catch (_) {}
        }
      }
    }
    final persons = (d['persons'] as List? ?? []).cast<String>();
    if (persons.isNotEmpty) {
      for (final m in members) {
        if (m.name == persons.first) {
          try {
            return Color(m.colorValue);
          } catch (_) {}
        }
      }
    }
    return accent;
  }

  final out = <String, MonthDayPills>{};
  for (final day in days) {
    final key = dateKey(day);
    final dayEvents = eventsByDay[key]!;
    final dayChores = choresByDay[key]!;

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
    activities.sort((a, b) {
      final ta = (a.data() as Map)['time'] as String? ?? '99:99';
      final tb = (b.data() as Map)['time'] as String? ?? '99:99';
      return ta.compareTo(tb);
    });

    MonthPill? school;
    if (schedule.isNotEmpty) {
      final firstMap = schedule.first.data() as Map<String, dynamic>;
      final c = colorForEvent(firstMap);
      final pik = schemaPiktogramFor(firstMap);
      school = MonthPill(background: c, label: pik);
    }

    final activityPills = <MonthPill>[];
    for (final doc in activities) {
      final d = doc.data() as Map<String, dynamic>;
      final title = (d['title'] as String? ?? '').trim();
      final pik = (d['piktogram'] as String? ?? '').trim();
      final label = title.isEmpty
          ? (pik.isEmpty ? '•' : pik)
          : (pik.isEmpty ? title : '$pik $title');
      activityPills.add(MonthPill(
        background: eventHasNoPersons(d) ? accent : colorForEvent(d),
        label: label,
      ));
    }

    final stadDocs = dayChores.where((c) {
      final d = c.data() as Map<String, dynamic>;
      final k = d['stadKey'] as String?;
      return k != null && k.isNotEmpty;
    }).toList();
    final otherChores = dayChores.where((c) {
      final d = c.data() as Map<String, dynamic>;
      final k = d['stadKey'] as String?;
      return k == null || k.isEmpty;
    }).toList();

    MonthPill? chorePill;
    final otherOpen = otherChores
        .where((c) => !choreDoneOnDay(c.data() as Map<String, dynamic>, day))
        .length;
    final hasOpenStad = stadDocs.isNotEmpty &&
        stadDocs.any((c) => !choreDoneOnDay(c.data() as Map<String, dynamic>, day));

    if (hasOpenStad && otherOpen > 0) {
      chorePill = MonthPill(
        background: const Color(0xFF6BAE75),
        label: '🧹 +$otherOpen',
        thin: true,
      );
    } else if (hasOpenStad) {
      chorePill = const MonthPill(
        background: Color(0xFF6BAE75),
        label: '🧹',
        thin: true,
      );
    } else if (otherOpen > 0) {
      chorePill = MonthPill(
        background: const Color(0xFF6BAE75),
        label: otherOpen == 1 ? '✅' : '✅ ×$otherOpen',
        thin: true,
      );
    }

    out[key] = MonthDayPills(
      activityPills: activityPills,
      schoolPill: school,
      chorePill: chorePill,
      events: [...schedule, ...activities],
      chores: dayChores,
    );
  }
  return out;
}

/// Helskärms månadsvy med veckonummer + event-pills + dag-sheet.
class KalenderMonthView extends StatefulWidget {
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final List<QueryDocumentSnapshot> events;
  final List<QueryDocumentSnapshot> chores;
  final List<UserModel> members;
  final UserModel? currentUser;
  final String familyId;
  final ValueChanged<DateTime> onFocusedMonthChanged;
  final ValueChanged<DateTime> onSelectedDayChanged;

  const KalenderMonthView({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.events,
    required this.chores,
    required this.members,
    required this.familyId,
    required this.onFocusedMonthChanged,
    required this.onSelectedDayChanged,
    this.currentUser,
  });

  @override
  State<KalenderMonthView> createState() => _KalenderMonthViewState();
}

class _KalenderMonthViewState extends State<KalenderMonthView> {
  late PageController _pageController;
  late DateTime _baseMonth;
  Map<String, MonthDayPills> _index = {};

  static const _weekColW = 28.0;

  @override
  void initState() {
    super.initState();
    _baseMonth = DateTime(widget.focusedMonth.year, widget.focusedMonth.month);
    // Stor page-index så vi kan swipe:a bakåt/framåt.
    _pageController = PageController(initialPage: 1000);
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(covariant KalenderMonthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final monthChanged = oldWidget.focusedMonth.year != widget.focusedMonth.year ||
        oldWidget.focusedMonth.month != widget.focusedMonth.month;
    if (monthChanged ||
        !identical(oldWidget.events, widget.events) ||
        !identical(oldWidget.chores, widget.chores) ||
        !identical(oldWidget.members, widget.members) ||
        oldWidget.events.length != widget.events.length ||
        oldWidget.chores.length != widget.chores.length) {
      _rebuildIndex();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _rebuildIndex() {
    final accent = AppTheme.getDayAccentColor();
    _index = buildMonthDayIndex(
      month: DateTime(widget.focusedMonth.year, widget.focusedMonth.month),
      events: widget.events,
      chores: widget.chores,
      members: widget.members,
      accent: accent,
    );
  }

  DateTime _monthAtPage(int page) {
    final delta = page - 1000;
    return DateTime(_baseMonth.year, _baseMonth.month + delta);
  }

  void _goToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    widget.onSelectedDayChanged(today);
    widget.onFocusedMonthChanged(DateTime(today.year, today.month));
    final delta =
        (today.year - _baseMonth.year) * 12 + (today.month - _baseMonth.month);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(1000 + delta);
    }
  }

  void _openDaySheet(DateTime day) {
    widget.onSelectedDayChanged(day);
    final pills = _index[dateKey(day)];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MonthDaySheet(
        day: day,
        events: pills?.events ?? const [],
        chores: pills?.chores ?? const [],
        members: widget.members,
        currentUser: widget.currentUser,
        familyId: widget.familyId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette();
    final title = DateFormat('MMMM y', 'sv').format(
      DateTime(widget.focusedMonth.year, widget.focusedMonth.month),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () {
                  if (_pageController.hasClients) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
              Expanded(
                child: Text(
                  title[0].toUpperCase() + title.substring(1),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _goToday,
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
                onPressed: () {
                  if (_pageController.hasClients) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        _weekdayHeader(),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (page) {
              final m = _monthAtPage(page);
              widget.onFocusedMonthChanged(DateTime(m.year, m.month));
            },
            itemBuilder: (context, page) {
              final month = _monthAtPage(page);
              final isFocused = month.year == widget.focusedMonth.year &&
                  month.month == widget.focusedMonth.month;
              final index = isFocused
                  ? _index
                  : buildMonthDayIndex(
                      month: month,
                      events: widget.events,
                      chores: widget.chores,
                      members: widget.members,
                      accent: AppTheme.getDayAccentColor(),
                    );
              return _MonthGridPage(
                month: month,
                selectedDay: widget.selectedDay,
                index: index,
                weekColW: _weekColW,
                onDayTap: _openDaySheet,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _weekdayHeader() {
    const names = ['mån', 'tis', 'ons', 'tor', 'fre', 'lör', 'sön'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Row(
        children: [
          SizedBox(
            width: _weekColW,
            child: Text(
              'v',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          for (final n in names)
            Expanded(
              child: Text(
                n,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGridPage extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final Map<String, MonthDayPills> index;
  final double weekColW;
  final ValueChanged<DateTime> onDayTap;

  const _MonthGridPage({
    required this.month,
    required this.selectedDay,
    required this.index,
    required this.weekColW,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final startOffset = (first.weekday - DateTime.monday) % 7;
    final gridStart = first.subtract(Duration(days: startOffset));
    final today = DateTime.now();
    final todayKey = dateKey(DateTime(today.year, today.month, today.day));
    final selectedKey = dateKey(selectedDay);
    final low = AppTheme.lowStimuli;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowH = constraints.maxHeight / 6;
        // Ungefärlig pill-höjd → max antal rader.
        final maxSlots = rowH >= 110 ? 4 : (rowH >= 88 ? 3 : 2);

        return Column(
          children: List.generate(6, (row) {
            final rowDay = DateTime(
              gridStart.year,
              gridStart.month,
              gridStart.day + row * 7,
            );
            final weekNo = isoWeekNumber(rowDay);
            return SizedBox(
              height: rowH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: weekColW,
                    child: Center(
                      child: Text(
                        '$weekNo',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: _DayCell(
                        day: DateTime(
                          gridStart.year,
                          gridStart.month,
                          gridStart.day + row * 7 + col,
                        ),
                        inMonth: DateTime(
                                  gridStart.year,
                                  gridStart.month,
                                  gridStart.day + row * 7 + col,
                                ).month ==
                            month.month,
                        isToday: dateKey(DateTime(
                              gridStart.year,
                              gridStart.month,
                              gridStart.day + row * 7 + col,
                            )) ==
                            todayKey,
                        isSelected: dateKey(DateTime(
                              gridStart.year,
                              gridStart.month,
                              gridStart.day + row * 7 + col,
                            )) ==
                            selectedKey,
                        pills: index[dateKey(DateTime(
                              gridStart.year,
                              gridStart.month,
                              gridStart.day + row * 7 + col,
                            ))],
                        maxSlots: maxSlots,
                        lowStimuli: low,
                        onTap: onDayTap,
                      ),
                    ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final MonthDayPills? pills;
  final int maxSlots;
  final bool lowStimuli;
  final ValueChanged<DateTime> onTap;

  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.pills,
    required this.maxSlots,
    required this.lowStimuli,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.dayPalette(day.weekday).base;
    final shown = pills?.visiblePills(maxSlots: maxSlots) ?? const [];
    final hidden = pills?.hiddenCount(maxSlots: maxSlots) ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(day),
        child: Container(
          margin: const EdgeInsets.all(1),
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: lowStimuli ? 0.18 : 0.12)
                : (inMonth ? Colors.white : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? accent
                  : (isSelected
                      ? accent.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.04)),
              width: isToday ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${day.day}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: inMonth
                      ? (isToday ? accent : AppTheme.getTextColor())
                      : Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 1),
              Expanded(
                child: Column(
                  children: [
                    for (final p in shown)
                      _PillChip(pill: p, lowStimuli: lowStimuli),
                    if (hidden > 0)
                      Text(
                        '+$hidden',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  final MonthPill pill;
  final bool lowStimuli;

  const _PillChip({required this.pill, required this.lowStimuli});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 1),
      padding: EdgeInsets.symmetric(
        horizontal: 3,
        vertical: pill.thin ? 0 : 1,
      ),
      decoration: BoxDecoration(
        color: lowStimuli
            ? pill.background.withValues(alpha: 0.55)
            : pill.background,
        borderRadius: BorderRadius.circular(lowStimuli ? 3 : 6),
      ),
      child: Text(
        pill.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: pill.thin ? 8 : 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

class _MonthDaySheet extends StatefulWidget {
  final DateTime day;
  final List<QueryDocumentSnapshot> events;
  final List<QueryDocumentSnapshot> chores;
  final List<UserModel> members;
  final UserModel? currentUser;
  final String familyId;

  const _MonthDaySheet({
    required this.day,
    required this.events,
    required this.chores,
    required this.members,
    required this.familyId,
    this.currentUser,
  });

  @override
  State<_MonthDaySheet> createState() => _MonthDaySheetState();
}

class _MonthDaySheetState extends State<_MonthDaySheet> {
  final Map<String, bool> _doneOverride = {};
  bool _schoolExpanded = false;

  bool _isDone(QueryDocumentSnapshot doc) {
    if (_doneOverride.containsKey(doc.id)) return _doneOverride[doc.id]!;
    return choreDoneOnDay(doc.data() as Map<String, dynamic>, widget.day);
  }

  Color _memberColor(Map<String, dynamic> d) {
    final uids = (d['personUids'] as List?)?.cast<String>() ?? const [];
    if (uids.isNotEmpty) {
      for (final m in widget.members) {
        if (m.uid == uids.first) {
          try {
            return Color(m.colorValue);
          } catch (_) {}
        }
      }
    }
    final persons = (d['persons'] as List? ?? []).cast<String>();
    if (persons.isNotEmpty) {
      for (final m in widget.members) {
        if (m.name == persons.first) {
          try {
            return Color(m.colorValue);
          } catch (_) {}
        }
      }
    }
    return AppTheme.getDayAccentColor(widget.day.weekday);
  }

  Future<void> _toggleChore(QueryDocumentSnapshot doc) async {
    final next = !_isDone(doc);
    try {
      await ChoreService.completeChore(
        choreId: doc.id,
        done: next,
        dayKey: dateKey(widget.day),
      );
      if (next) {
        await NotificationService.cancelChoreInstance(doc.id, widget.day);
      }
      if (mounted) setState(() => _doneOverride[doc.id] = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte spara: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor(widget.day.weekday);
    final title = DateFormat('EEEE d MMMM', 'sv').format(widget.day);

    final schedule = <QueryDocumentSnapshot>[];
    final activities = <QueryDocumentSnapshot>[];
    for (final doc in widget.events) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') {
        schedule.add(doc);
      } else {
        activities.add(doc);
      }
    }
    activities.sort((a, b) {
      final ta = (a.data() as Map)['time'] as String? ?? '99:99';
      final tb = (b.data() as Map)['time'] as String? ?? '99:99';
      return ta.compareTo(tb);
    });
    schedule.sort((a, b) {
      final ta = (a.data() as Map)['time'] as String? ?? '99:99';
      final tb = (b.data() as Map)['time'] as String? ?? '99:99';
      return ta.compareTo(tb);
    });
    final chores = widget.chores;
    final stadDocs = chores.where((c) {
      final d = c.data() as Map<String, dynamic>;
      final k = d['stadKey'] as String?;
      return k != null && k.isNotEmpty;
    }).toList();
    final otherChores = chores.where((c) {
      final d = c.data() as Map<String, dynamic>;
      final k = d['stadKey'] as String?;
      return k == null || k.isEmpty;
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.48,
      minChildSize: 0.28,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F7F7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title[0].toUpperCase() + title.substring(1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: dayColor),
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => AddEventSheet(
                          selectedDay: widget.day,
                          familyMembers: widget.members,
                          familyId: widget.familyId,
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (schedule.isEmpty && activities.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Inga aktiviteter.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              if (schedule.isNotEmpty) ...[
                _SchoolClusterRow(
                  docs: schedule,
                  expanded: _schoolExpanded,
                  onToggle: () =>
                      setState(() => _schoolExpanded = !_schoolExpanded),
                  color: _memberColor(
                      schedule.first.data() as Map<String, dynamic>),
                  onLessonTap: (doc) {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) =>
                          ActivityDetailSheet(docSnapshot: doc),
                    );
                  },
                ),
              ],
              for (final doc in activities)
                _EventRow(
                  doc: doc,
                  color: _memberColor(doc.data() as Map<String, dynamic>),
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) =>
                          ActivityDetailSheet(docSnapshot: doc),
                    );
                  },
                ),
              const SizedBox(height: 16),
              Text('SYSSLOR', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              if (chores.isEmpty)
                Text(
                  'Inga sysslor med förfallodatum den här dagen.',
                  style: TextStyle(color: Colors.grey.shade600),
                )
              else ...[
                if (stadDocs.isNotEmpty)
                  _buildStaddagCard(
                    context,
                    stadDocs: stadDocs,
                    dayColor: dayColor,
                  ),
                for (final doc in otherChores)
                  _ChoreCheckRow(
                    doc: doc,
                    dayColor: dayColor,
                    done: _isDone(doc),
                    onToggle: () => _toggleChore(doc),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStaddagCard(
    BuildContext context, {
    required List<QueryDocumentSnapshot> stadDocs,
    required Color dayColor,
  }) {
    final doneCount = stadDocs.where((c) => _isDone(c)).length;
    final totalCount = stadDocs.length;
    final isAllDone = totalCount > 0 && doneCount == totalCount;

    String recText = 'varje lördag';
    if (stadDocs.isNotEmpty) {
      final firstD = stadDocs.first.data() as Map<String, dynamic>;
      if (choreIsRecurring(firstD)) {
        recText = recurrenceLabel(firstD);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaddagPage()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Text('🧹', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Städdag · $doneCount av $totalCount klara',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration:
                              isAllDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🔁 $recText',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAllDone)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF6BAE75),
                    size: 22,
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SchoolClusterRow extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final bool expanded;
  final VoidCallback onToggle;
  final Color color;
  final ValueChanged<QueryDocumentSnapshot> onLessonTap;

  const _SchoolClusterRow({
    required this.docs,
    required this.expanded,
    required this.onToggle,
    required this.color,
    required this.onLessonTap,
  });

  @override
  Widget build(BuildContext context) {
    final maps = docs.map((d) => d.data() as Map<String, dynamic>);
    final label = scheduleBlockLabel(maps);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(
                    AppTheme.lowStimuli ? 6 : 12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final doc in docs)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: InkWell(
                  onTap: () => onLessonTap(doc),
                  child: Builder(builder: (context) {
                    final d = doc.data() as Map<String, dynamic>;
                    final t = (d['time'] as String? ?? '').trim();
                    final end = (d['endTime'] as String? ?? '').trim();
                    final title = d['title'] as String? ?? '';
                    final time =
                        t.isEmpty ? '' : (end.isEmpty ? t : '$t–$end');
                    return Text(
                      time.isEmpty ? title : '$time  $title',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }),
                ),
              ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Color color;
  final VoidCallback onTap;

  const _EventRow({
    required this.doc,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? '';
    final t = (d['time'] as String? ?? '').trim();
    final end = (d['endTime'] as String? ?? '').trim();
    final timeLabel = t.isEmpty
        ? ''
        : (end.isEmpty ? t : '$t–$end');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                timeLabel.isEmpty ? '–' : timeLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(
                      AppTheme.lowStimuli ? 6 : 12),
                ),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoreCheckRow extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;
  final bool done;
  final VoidCallback onToggle;

  const _ChoreCheckRow({
    required this.doc,
    required this.dayColor,
    required this.done,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text(pik, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration:
                          done ? TextDecoration.lineThrough : null,
                      color: done ? Colors.grey : null,
                    ),
                  ),
                ),
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: done ? dayColor : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
