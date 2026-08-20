import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/conflict_detector.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/member_presence.dart';
import '../utils/minute_ticker.dart';
import '../utils/permissions.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/busy_check_in_sheet.dart';
import '../widgets/family_notes_strip.dart';
import '../widgets/kalender_day_view.dart';
import '../widgets/member_avatar.dart';
import '../widgets/member_day_sheet.dart';
import '../widgets/quick_add_bar.dart';
import '../widgets/week_grid.dart';
import 'agenda_page.dart';
import 'calendar_import_page.dart';
import 'meal_planner_page.dart';
import 'work_schedule_page.dart';

enum KalenderLage { dag, vecka, manad, agenda }

const _lagePrefKey = 'kalender_lage';

/// Syssla utan `dueDate` visas alla dagar; med datum bara den dagen.
bool _choreVisibleOnDay(Map<String, dynamic> d, DateTime day) {
  final raw = d['dueDate'];
  if (raw == null) return true;
  if (raw is String && raw.isEmpty) return true;
  if (raw is String) {
    final parsed = parseDate(raw);
    if (parsed == null) return true;
    return isSameDay(parsed, day);
  }
  return true;
}

class KalenderPage extends StatefulWidget {
  const KalenderPage({super.key});

  @override
  State<KalenderPage> createState() => _KalenderPageState();
}

class _KalenderPageState extends State<KalenderPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  KalenderLage _lage = KalenderLage.dag;
  bool _lageLoaded = false;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  late DateTime _weekStart;
  String? _filterPerson;
  String? _filterPersonUid;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
    MinuteTicker.ensureRunning();
    _loadLage();
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  Future<void> _loadLage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_lagePrefKey);
      if (!mounted) return;
      if (saved != null) {
        KalenderLage? parsed;
        for (final e in KalenderLage.values) {
          if (e.name == saved) {
            parsed = e;
            break;
          }
        }
        if (parsed != null) {
          setState(() {
            _lage = parsed!;
            _lageLoaded = true;
          });
          return;
        }
      }
      final provider = context.read<FamilyProvider>();
      setState(() {
        _lage = (provider.currentUser?.isParent ?? false)
            ? KalenderLage.vecka
            : KalenderLage.dag;
        _lageLoaded = true;
      });
    } catch (e, stack) {
      developer.log('kalender_lage load', error: e, stackTrace: stack);
      if (mounted) setState(() => _lageLoaded = true);
    }
  }

  Future<void> _saveLage(KalenderLage lage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lagePrefKey, lage.name);
    } catch (e, stack) {
      developer.log('kalender_lage save', error: e, stackTrace: stack);
    }
  }

  Stream<QuerySnapshot>? _datedEventsStream(
    String? fid,
    DateTime from,
    DateTime to,
  ) {
    if (fid == null || fid.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('planner_events')
        .where('familyId', isEqualTo: fid)
        .where('date', isGreaterThanOrEqualTo: dateKey(from))
        .where('date', isLessThanOrEqualTo: dateKey(to))
        .snapshots();
  }

  Stream<QuerySnapshot>? _recurringEventsStream(String? fid) =>
      (fid == null || fid.isEmpty)
          ? null
          : FirebaseFirestore.instance
              .collection('planner_events')
              .where('familyId', isEqualTo: fid)
              .where('isRecurring', isEqualTo: true)
              .snapshots();

  Stream<QuerySnapshot>? _shiftsStream(String? fid) =>
      (fid == null || fid.isEmpty)
          ? null
          : FirebaseFirestore.instance
              .collection('work_shifts')
              .where('familyId', isEqualTo: fid)
              .snapshots();

  Stream<QuerySnapshot>? _busyStream(String? fid) =>
      (fid == null || fid.isEmpty)
          ? null
          : FirebaseFirestore.instance
              .collection('busy_sessions')
              .where('familyId', isEqualTo: fid)
              .snapshots();

  List<QueryDocumentSnapshot> _mergeEvents(
    List<QueryDocumentSnapshot> dated,
    List<QueryDocumentSnapshot> recurring,
  ) {
    final seen = <String>{};
    final out = <QueryDocumentSnapshot>[];
    for (final d in dated) {
      if (seen.add(d.id)) out.add(d);
    }
    for (final d in recurring) {
      if (seen.add(d.id)) out.add(d);
    }
    return out;
  }

  ({DateTime from, DateTime to, DateTime conflictStart, int conflictDays})
      _dateWindow() {
    final lage = _effectiveLage;
    switch (lage) {
      case KalenderLage.dag:
        final d = DateTime(
            _selectedDay.year, _selectedDay.month, _selectedDay.day);
        return (
          from: d.subtract(const Duration(days: 1)),
          to: d.add(const Duration(days: 1)),
          conflictStart: d,
          conflictDays: 1,
        );
      case KalenderLage.vecka:
        return (
          from: _weekStart.subtract(const Duration(days: 1)),
          to: _weekStart.add(const Duration(days: 6)),
          conflictStart: _weekStart,
          conflictDays: 7,
        );
      case KalenderLage.manad:
      case KalenderLage.agenda:
        final monthStart =
            DateTime(_focusedDay.year, _focusedDay.month, 1);
        final monthEnd =
            DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
        return (
          from: monthStart.subtract(const Duration(days: 7)),
          to: monthEnd.add(const Duration(days: 7)),
          conflictStart: _weekStart,
          conflictDays: 0,
        );
    }
  }

  List<QueryDocumentSnapshot> _eventsForDay(
    List<QueryDocumentSnapshot> all,
    DateTime day,
  ) {
    final filtered = all.where((doc) {
      try {
        final d = doc.data() as Map<String, dynamic>;
        if ((d['source'] as String?) == 'calendar') {
          final kind = d['planningImportKind'] as String? ?? 'schedule';
          if (kind != 'activity') return false;
        }
        if (!eventOccursOnDay(d, day)) return false;
        if (_filterPerson != null) {
          return eventIncludesPerson(d,
              uid: _filterPersonUid ?? '', name: _filterPerson!);
        }
        return true;
      } catch (_) {
        return false;
      }
    }).toList();

    filtered.sort((a, b) {
      final dA = parseDateTime(a.data() as Map<String, dynamic>);
      final dB = parseDateTime(b.data() as Map<String, dynamic>);
      if (dA == null && dB == null) return 0;
      if (dA == null) return 1;
      if (dB == null) return -1;
      return dA.compareTo(dB);
    });
    return filtered;
  }

  List<QueryDocumentSnapshot> _filterChoresForDay(
    List<QueryDocumentSnapshot> docs,
    DateTime day,
  ) {
    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!_choreVisibleOnDay(d, day)) return false;
      if (_filterPerson != null) {
        return assignedToPerson(d,
            uid: _filterPersonUid ?? '', name: _filterPerson!);
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = (a.data() as Map)['isDone'] == true ? 1 : 0;
        final db = (b.data() as Map)['isDone'] == true ? 1 : 0;
        return da.compareTo(db);
      });
  }

  void _openMemberToday(
    FamilyProvider provider,
    UserModel member,
    List<QueryDocumentSnapshot> todayEvents,
  ) {
    final chores = provider.chores.where((doc) {
      return assignedToPerson(doc.data() as Map<String, dynamic>,
          uid: member.uid, name: member.name);
    }).toList();
    final memberEvents = todayEvents.where((doc) {
      return eventIncludesPerson(doc.data() as Map<String, dynamic>,
          uid: member.uid, name: member.name);
    }).toList();
    final today = DateTime.now();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberDaySheet(
        member: member,
        currentUser: provider.currentUser,
        memberEvents: memberEvents,
        memberChores: chores,
        day: DateTime(today.year, today.month, today.day),
      ),
    );
  }

  void _openCell(
    FamilyProvider provider,
    UserModel member,
    DateTime day,
    List<QueryDocumentSnapshot> dayEvents,
  ) {
    final chores = provider.chores.where((doc) {
      return assignedToPerson(doc.data() as Map<String, dynamic>,
          uid: member.uid, name: member.name);
    }).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberDaySheet(
        member: member,
        currentUser: provider.currentUser,
        memberEvents: dayEvents,
        memberChores: chores,
        day: day,
      ),
    );
  }

  Future<void> _takeResponsibility(
      FamilyProvider provider, ScheduleConflict c) async {
    final me = provider.currentUser;
    if (me == null) return;
    final now = DateTime.now();
    final label =
        '${DateFormat('EEE', 'sv').format(c.day)} ${DateFormat('HH:mm').format(c.start)}';
    try {
      await FirebaseFirestore.instance.collection('family_notes').add({
        'familyId': me.familyId,
        'fromUid': me.uid,
        'fromName': me.name,
        'fromColor': me.color,
        'date': dateKey(c.day),
        'createdAt': FieldValue.serverTimestamp(),
        'text': '✋ ${me.name.split(' ').first} tar ansvar $label',
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Noterat på familjetavlan! ✋'),
            backgroundColor: Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('takeResponsibility misslyckades',
          error: e, stackTrace: stack);
    }
  }

  void _showConflict(FamilyProvider provider, ScheduleConflict c) {
    if (c.isPickup) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hämtning 🚗'),
          content: Text(c.pickupLabel ?? ''),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Stäng'),
            ),
            FilledButton.icon(
              icon: const Text('✋'),
              label: const Text('Jag tar det'),
              onPressed: () => _takeResponsibility(provider, c),
            ),
          ],
        ),
      );
      return;
    }

    final names = c.adults.map((a) => a.name.split(' ').first).join(' & ');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Krock i schemat 🚨'),
        content: Text(
          '${DateFormat('EEEE d/M', 'sv').format(c.day)} '
          '${DateFormat('HH:mm').format(c.start)}–${DateFormat('HH:mm').format(c.end)}\n\n'
          '$names är upptagna samtidigt. Vem tar hämtningar och barn under '
          'den tiden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stäng'),
          ),
          FilledButton.icon(
            icon: const Text('✋'),
            label: const Text('Jag tar det'),
            onPressed: () => _takeResponsibility(provider, c),
          ),
        ],
      ),
    );
  }

  void _showFamilyDaySheet(
      DateTime day, List<QueryDocumentSnapshot> dayEvents) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final label = DateFormat('EEEE d MMMM', 'sv').format(day);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Familjen — $label',
                    style: AppTheme.sectionTitleStyle),
                const SizedBox(height: 12),
                if (dayEvents.isEmpty)
                  const Text('Inga gemensamma händelser.')
                else
                  ...dayEvents.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final title = d['title'] as String? ?? '';
                    final t = d['time'] as String? ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(d['piktogram'] as String? ?? '📅'),
                      title: Text(title),
                      subtitle: t.isNotEmpty ? Text(t) : null,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shiftWeek(int weeks) => setState(() => _weekStart =
      DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks));

  void _shiftAgendaDay(int delta) {
    setState(() {
      _selectedDay = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day + delta,
      );
    });
  }

  KalenderLage get _effectiveLage {
    final isFocus =
        context.read<FamilyProvider>().currentUser?.isFocusMode ?? false;
    if (isFocus &&
        (_lage == KalenderLage.vecka || _lage == KalenderLage.manad)) {
      return KalenderLage.dag;
    }
    return _lage;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_lageLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    context.select((FamilyProvider p) => (
          p.currentUser?.familyId,
          p.familyMembers,
          p.chores,
          p.todayEvents,
        ));
    final provider = context.read<FamilyProvider>();
    final fid = provider.currentUser?.familyId;
    final members = provider.familyMembers;
    final user = provider.currentUser;
    final isFocus = user?.isFocusMode ?? false;
    final dayColor = AppTheme.getDayAccentColor();
    final window = _dateWindow();
    final effectiveLage = _effectiveLage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppTheme.getBackground(),
        child: StreamBuilder<QuerySnapshot>(
          stream: _datedEventsStream(fid, window.from, window.to),
          builder: (ctx, datedSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: _recurringEventsStream(fid),
              builder: (ctxR, recSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: _shiftsStream(fid),
                  builder: (ctxS, shSnap) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: _busyStream(fid),
                      builder: (ctxB, busySnap) {
                        final events = _mergeEvents(
                          datedSnap.data?.docs ?? const [],
                          recSnap.data?.docs ?? const [],
                        );
                        final shifts =
                            shSnap.data?.docs ?? const <QueryDocumentSnapshot>[];
                        final busyDocs =
                            busySnap.data?.docs ?? const <QueryDocumentSnapshot>[];

                        final conflicts = (effectiveLage == KalenderLage.dag ||
                                effectiveLage == KalenderLage.vecka)
                            ? detectAllConflicts(
                                members: members,
                                events: events,
                                shifts: shifts,
                                weekStart: window.conflictStart,
                                dayCount: window.conflictDays,
                              )
                            : const <ScheduleConflict>[];

                        return Column(
                          children: [
                            if (!isFocus) ...[
                              _buildHeader(context, user?.isParent ?? false),
                              QuickAddBar(
                                familyMembers: members,
                                familyId: fid ?? '',
                                onFallbackToForm: (raw) {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => AddEventSheet(
                                      selectedDay: _selectedDay,
                                      familyMembers: members,
                                      familyId: fid ?? '',
                                      initialTitle: raw,
                                    ),
                                  );
                                },
                              ),
                              const FamilyNotesStrip(),
                              _buildMemberPresenceRow(
                                provider,
                                members,
                                provider.todayEvents,
                                shifts,
                                busyDocs,
                              ),
                            ] else
                              _buildMinimalHeader(context),
                            _buildModeSelector(dayColor, isFocus),
                            if (conflicts.isNotEmpty)
                              _buildConflictStrip(provider, conflicts),
                            Expanded(
                              child: _buildModeContent(
                                provider,
                                members,
                                events,
                                shifts,
                                dayColor,
                                isFocus,
                                effectiveLage,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'kalender_busy',
        backgroundColor: dayColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.do_not_disturb_on_rounded),
        label: const Text('Jag är upptagen'),
        onPressed: () {
          final me = provider.currentUser;
          if (me == null || fid == null || fid.isEmpty) return;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => BusyCheckInSheet(
              familyId: fid,
              userName: me.name,
              userUid: me.uid,
            ),
          );
        },
      ),
    );
  }

  Widget _buildModeContent(
    FamilyProvider provider,
    List<UserModel> members,
    List<QueryDocumentSnapshot> events,
    List<QueryDocumentSnapshot> shifts,
    Color dayColor,
    bool isFocus,
    KalenderLage lage,
  ) {
    switch (lage) {
      case KalenderLage.dag:
        return KalenderDayView(
          members: members,
          selectedDay: _selectedDay,
          events: events,
          shifts: shifts,
          chores: provider.chores,
          currentUser: provider.currentUser,
          familyId: provider.currentUser?.familyId ?? '',
          onDayChanged: (d) => setState(() => _selectedDay = d),
          onOpenMember: (m) =>
              _openMemberToday(provider, m, provider.todayEvents),
        );
      case KalenderLage.vecka:
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildWeekNav()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: members.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : WeekGrid(
                        members: members,
                        events: events,
                        shifts: shifts,
                        weekStart: _weekStart,
                        onCellTap: (m, day, dayEvents) =>
                            _openCell(provider, m, day, dayEvents),
                        onFamilyRowTap: _showFamilyDaySheet,
                      ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      case KalenderLage.manad:
        return _buildMonthAgendaScroll(
          provider,
          members,
          events,
          dayColor,
          showCalendar: true,
        );
      case KalenderLage.agenda:
        return _buildMonthAgendaScroll(
          provider,
          members,
          events,
          dayColor,
          showCalendar: false,
        );
    }
  }

  Widget _buildMonthAgendaScroll(
    FamilyProvider provider,
    List<UserModel> members,
    List<QueryDocumentSnapshot> events,
    Color dayColor, {
    required bool showCalendar,
  }) {
    final activities = _eventsForDay(events, _selectedDay);
    final chores = _filterChoresForDay(provider.chores, _selectedDay);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (!showCalendar) SliverToBoxAdapter(child: _buildAgendaDayNav()),
        if (showCalendar) ...[
          SliverToBoxAdapter(child: _buildCalendar(events, dayColor)),
          SliverToBoxAdapter(child: _buildPersonFilter(members, dayColor)),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              DateFormat('EEEE d MMMM', 'sv').format(_selectedDay),
              style: AppTheme.sectionTitleStyle,
            ),
          ),
        ),
        if (activities.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Inga aktiviteter den här dagen.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => AgendaActivityRow(
                doc: activities[i],
                dayColor: dayColor,
                listDay: _selectedDay,
                familyMembers: members,
                familyId: provider.currentUser?.familyId ?? '',
                currentUser: provider.currentUser,
              ),
              childCount: activities.length,
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text('SYSSLOR', style: AppTheme.sectionLabelStyle),
          ),
        ),
        if (chores.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Inga sysslor just nu.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => AgendaChoreRow(
                doc: chores[i],
                dayColor: dayColor,
                familyMembers: members,
                familyId: provider.currentUser?.familyId ?? '',
                currentUser: provider.currentUser,
                allowDrag: canEditDoc(
                  provider.currentUser,
                  chores[i].data() as Map<String, dynamic>,
                ),
                onComplete: () {},
              ),
              childCount: chores.length,
            ),
          ),
        const SliverToBoxAdapter(
            child: SizedBox(height: WindowSize.navScrollPadding)),
      ],
    );
  }

  Widget _buildAgendaDayNav() {
    final palette = AppTheme.dayPalette();
    final isToday = isSameDay(_selectedDay, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _shiftAgendaDay(-1),
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('EEEE d MMMM', 'sv').format(_selectedDay),
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
                setState(() => _selectedDay =
                    DateTime(now.year, now.month, now.day));
              },
              child: Text('Idag',
                  style: TextStyle(
                      color: palette.deep, fontWeight: FontWeight.w700)),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _shiftAgendaDay(1),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(List<QueryDocumentSnapshot> all, Color dayColor) {
    final calStyle = CalendarStyle(
      cellMargin: EdgeInsets.zero,
      selectedDecoration:
          BoxDecoration(color: dayColor, shape: BoxShape.circle),
      todayDecoration: BoxDecoration(
          color: dayColor.withValues(alpha: 0.3), shape: BoxShape.circle),
      markerDecoration:
          BoxDecoration(color: dayColor, shape: BoxShape.circle),
      markersMaxCount: 1,
      markerSize: 5,
      markerMargin: const EdgeInsets.only(top: 2),
      outsideDaysVisible: false,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: AppTheme.cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: TableCalendar(
          firstDay: DateTime.utc(2020),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          startingDayOfWeek: StartingDayOfWeek.monday,
          availableGestures: AvailableGestures.horizontalSwipe,
          selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
          eventLoader: (day) {
            try {
              return _eventsForDay(all, day).map((e) => e.id).toList();
            } catch (_) {
              return [];
            }
          },
          onDaySelected: (s, f) =>
              setState(() { _selectedDay = s; _focusedDay = f; }),
          onPageChanged: (f) => setState(() => _focusedDay = f),
          locale: 'sv',
          calendarStyle: calStyle,
          calendarBuilders: CalendarBuilders(
            selectedBuilder: (context, day, focusedDay) =>
                _monthDayCellWithChoreDrop(
              context,
              day,
              dayColor,
              calStyle,
              decoration: calStyle.selectedDecoration,
              textStyle: calStyle.selectedTextStyle,
            ),
            todayBuilder: (context, day, focusedDay) =>
                _monthDayCellWithChoreDrop(
              context,
              day,
              dayColor,
              calStyle,
              decoration: calStyle.todayDecoration,
              textStyle: calStyle.todayTextStyle,
            ),
            defaultBuilder: (context, day, focusedDay) {
              final weekend = day.weekday == DateTime.saturday ||
                  day.weekday == DateTime.sunday;
              return _monthDayCellWithChoreDrop(
                context,
                day,
                dayColor,
                calStyle,
                decoration: weekend
                    ? calStyle.weekendDecoration
                    : calStyle.defaultDecoration,
                textStyle: weekend
                    ? calStyle.weekendTextStyle
                    : calStyle.defaultTextStyle,
              );
            },
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _monthDayCellWithChoreDrop(
    BuildContext context,
    DateTime day,
    Color dayColor,
    CalendarStyle calStyle, {
    required Decoration? decoration,
    required TextStyle? textStyle,
  }) {
    final text = '${day.day}';
    final deco = decoration ?? const BoxDecoration();
    final txt = textStyle ?? const TextStyle();

    Widget cell(Duration duration, {bool dropHighlight = false}) {
      return AnimatedContainer(
        duration: duration,
        margin: calStyle.cellMargin,
        padding: calStyle.cellPadding,
        alignment: calStyle.cellAlignment,
        decoration: deco,
        foregroundDecoration: dropHighlight
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: dayColor, width: 2.5),
              )
            : null,
        child: Text(text, style: txt),
      );
    }

    return DragTarget<DocumentReference>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) async {
        try {
          await details.data.update({'dueDate': dateKey(day)});
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Syssla flyttad till ${DateFormat.E('sv').format(day)}',
              ),
              backgroundColor: const Color(0xFF6BAE75),
            ),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bara föräldrar eller den som skapat sysslan kan flytta den',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      builder: (context, candidate, rejected) {
        final hi = candidate.isNotEmpty;
        return cell(
          hi
              ? const Duration(milliseconds: 150)
              : const Duration(milliseconds: 250),
          dropHighlight: hi,
        );
      },
    );
  }

  Widget _buildPersonFilter(List<UserModel> familyMembers, Color dayColor) {
    if (familyMembers.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          _FilterPill(
            label: 'Alla',
            selected: _filterPerson == null,
            color: dayColor,
            onTap: () => setState(() {
              _filterPerson = null;
              _filterPersonUid = null;
            }),
          ),
          ...familyMembers.map((m) {
            Color mc;
            try {
              mc = Color(m.colorValue);
            } catch (_) {
              mc = dayColor;
            }
            return _FilterPill(
              label: m.name.split(' ').first,
              selected: _filterPerson == m.name,
              color: mc,
              onTap: () => setState(() {
                if (_filterPerson == m.name) {
                  _filterPerson = null;
                  _filterPersonUid = null;
                } else {
                  _filterPerson = m.name;
                  _filterPersonUid = m.uid;
                }
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isParent) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Kalender',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          if (isParent)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: textColor),
              onSelected: (v) {
                switch (v) {
                  case 'import':
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const CalendarImportPage(),
                      ),
                    );
                    break;
                  case 'mat':
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const MealPlannerPage(),
                      ),
                    );
                    break;
                  case 'schema':
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const WorkSchedulePage(),
                      ),
                    );
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'import',
                  child: Text('Kalenderimport'),
                ),
                PopupMenuItem(value: 'mat', child: Text('Mat')),
                PopupMenuItem(value: 'schema', child: Text('Schema')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMinimalHeader(BuildContext context) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context, bottom: 8),
      child: Text(
        'Kalender',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildModeSelector(Color dayColor, bool isFocus) {
    final segments = isFocus
        ? [
            ButtonSegment(
              value: KalenderLage.dag,
              label: const Text('Dag'),
            ),
            ButtonSegment(
              value: KalenderLage.agenda,
              label: const Text('Agenda'),
            ),
          ]
        : const [
            ButtonSegment(value: KalenderLage.dag, label: Text('Dag')),
            ButtonSegment(value: KalenderLage.vecka, label: Text('Vecka')),
            ButtonSegment(value: KalenderLage.manad, label: Text('Månad')),
            ButtonSegment(value: KalenderLage.agenda, label: Text('Agenda')),
          ];

    final selected = isFocus
        ? (_lage == KalenderLage.agenda
            ? {KalenderLage.agenda}
            : {KalenderLage.dag})
        : {_lage};

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SegmentedButton<KalenderLage>(
        showSelectedIcon: false,
        segments: segments,
        selected: selected,
        onSelectionChanged: (s) {
          final next = s.first;
          setState(() => _lage = next);
          _saveLage(next);
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return dayColor;
            return Colors.white;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return AppTheme.getTextColor();
          }),
        ),
      ),
    );
  }

  Widget _buildMemberPresenceRow(
    FamilyProvider provider,
    List<UserModel> members,
    List<QueryDocumentSnapshot> todayEvents,
    List<QueryDocumentSnapshot> shiftDocs,
    List<QueryDocumentSnapshot> busyDocs,
  ) {
    if (members.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: members.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final m = members[i];
          final memberEvents = todayEvents.where((doc) {
            return eventIncludesPerson(doc.data() as Map<String, dynamic>,
                uid: m.uid, name: m.name);
          }).toList();
          final presence = computeMemberPresence(
            m,
            memberTodayEvents: memberEvents,
            familyShiftDocs: shiftDocs,
            familyBusyDocs: busyDocs,
          );

          return GestureDetector(
            onTap: () => _openMemberToday(provider, m, todayEvents),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    FamilyMemberAvatar(member: m, size: 44, borderWidth: 0),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: presence.ringColor,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  m.name.split(' ').first,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWeekNav() {
    final palette = AppTheme.dayPalette();
    final weekEnd = DateTime(
        _weekStart.year, _weekStart.month, _weekStart.day + 6);
    final label =
        '${DateFormat('d MMM', 'sv').format(_weekStart)} – ${DateFormat('d MMM', 'sv').format(weekEnd)}';
    final isThisWeek = _weekStart == _mondayOf(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _shiftWeek(-1),
          ),
          Expanded(
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          if (!isThisWeek)
            TextButton(
              onPressed: () =>
                  setState(() => _weekStart = _mondayOf(DateTime.now())),
              child: Text('Idag',
                  style: TextStyle(
                      color: palette.deep, fontWeight: FontWeight.w700)),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _shiftWeek(1),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictStrip(
      FamilyProvider provider, List<ScheduleConflict> conflicts) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: conflicts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = conflicts[i];
          final label = c.isPickup
              ? (c.pickupLabel ?? 'Hämtning')
              : () {
                  final names =
                      c.adults.map((a) => a.name.split(' ').first).join(' & ');
                  final time =
                      '${DateFormat('EEE', 'sv').format(c.day)} ${DateFormat('HH:mm').format(c.start)}';
                  return '$time — $names';
                }();
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _showConflict(provider, c),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.isPickup
                      ? const Color(0xFFFFF3E0)
                      : const Color(0xFFFDECEA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: c.isPickup
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFE57368),
                  ),
                ),
                child: Row(
                  children: [
                    Text(c.isPickup ? '🚗' : '🚨',
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.isPickup
                            ? const Color(0xFF8D5A00)
                            : const Color(0xFF93331F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.getTextColor(),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
}
