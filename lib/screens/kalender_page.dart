import 'dart:async';
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
import '../utils/chore_utils.dart';
import '../utils/conflict_detector.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/member_presence.dart';
import '../utils/minute_ticker.dart';
import '../services/user_service.dart';
import '../utils/permissions.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/busy_check_in_sheet.dart';
import '../widgets/family_notes_strip.dart';
import '../utils/schedule_display.dart';
import '../utils/schedule_time_utils.dart';
import '../widgets/activity_detail_sheet.dart';
import '../widgets/kalender_month_view.dart';
import '../widgets/member_day_sheet.dart';
import '../widgets/quick_add_bar.dart';
import '../widgets/week_grid.dart';
import '../widgets/week_list.dart';
import '../widgets/weather_widgets.dart';
import '../utils/event_actions.dart';
import 'agenda_page.dart';
import 'staddag_page.dart';

enum KalenderLage { dag, vecka, manad }

const _lagePrefKey = 'kalender_lage';
const _fullscreenPrefKey = 'kalender_fullscreen';

class KalenderPage extends StatefulWidget {
  const KalenderPage({super.key});

  @override
  State<KalenderPage> createState() => _KalenderPageState();
}

class _KalenderPageState extends State<KalenderPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  KalenderLage _lage = KalenderLage.dag;
  bool _lageLoaded = false;
  bool _fullscreen = false;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  late DateTime _weekStart;
  String? _filterPerson;
  String? _filterPersonUid;
  /// dateKey för "idag" när valet senast synkades — för midnatts-/resume-roll.
  String _anchoredTodayKey = dateKey(DateTime.now());
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _weekStart = _mondayOf(DateTime.now());
    MinuteTicker.ensureRunning();
    MinuteTicker.now.addListener(_onMinuteTick);
    _scheduleMidnightRoll();
    _loadLage();
  }

  @override
  void dispose() {
    MinuteTicker.now.removeListener(_onMinuteTick);
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<FamilyProvider>().ensureDateSubscriptionsFresh();
      _maybeRollSelectedToToday();
    }
  }

  void _onMinuteTick() => _maybeRollSelectedToToday();

  void _scheduleMidnightRoll() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(next.difference(now), () {
      _maybeRollSelectedToToday();
      _scheduleMidnightRoll();
    });
  }

  /// Om vald dag var gamla "idag" → flytta till nya idag (alla lägen).
  void _maybeRollSelectedToToday() {
    final now = DateTime.now();
    final nowKey = dateKey(now);
    if (nowKey == _anchoredTodayKey) return;
    final oldToday = parseDate(_anchoredTodayKey);
    final wasOnOldToday =
        oldToday != null && isSameDay(_selectedDay, oldToday);
    _anchoredTodayKey = nowKey;
    if (!wasOnOldToday || !mounted) return;
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedDay = today;
      _focusedDay = today;
      _weekStart = _mondayOf(today);
    });
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  Future<void> _loadLage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_lagePrefKey);
      final fs = prefs.getBool(_fullscreenPrefKey) ?? false;
      if (!mounted) return;
      if (saved != null) {
        if (saved == 'agenda') {
          setState(() {
            _lage = KalenderLage.dag;
            _fullscreen = fs;
            _lageLoaded = true;
          });
          return;
        }
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
            _fullscreen = fs;
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
        _fullscreen = fs;
        _lageLoaded = true;
      });
    } catch (e, stack) {
      developer.log('kalender_lage load', error: e, stackTrace: stack);
      if (mounted) setState(() => _lageLoaded = true);
    }
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_fullscreenPrefKey, next);
    } catch (e, stack) {
      developer.log('kalender_fullscreen save', error: e, stackTrace: stack);
    }
  }

  Map<String, Color> _presenceMap(
    List<UserModel> members,
    List<QueryDocumentSnapshot> todayEvents,
    List<QueryDocumentSnapshot> shifts,
    List<QueryDocumentSnapshot> busyDocs,
  ) {
    final out = <String, Color>{};
    for (final m in members) {
      final memberEvents = todayEvents.where((doc) {
        return eventIncludesPerson(
          doc.data() as Map<String, dynamic>,
          uid: m.uid,
          name: m.name,
        );
      }).toList();
      final p = computeMemberPresence(
        m,
        memberTodayEvents: memberEvents,
        familyShiftDocs: shifts,
        familyBusyDocs: busyDocs,
      );
      out[m.uid] = p.ringColor;
    }
    return out;
  }

  Future<void> _saveLage(KalenderLage lage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lagePrefKey, lage.name);
    } catch (e, stack) {
      developer.log('kalender_lage save', error: e, stackTrace: stack);
    }
  }

  void _setLage(KalenderLage next) {
    setState(() {
      _lage = next;
      if (next == KalenderLage.manad) {
        _focusedDay = DateTime(_selectedDay.year, _selectedDay.month);
      }
    });
    _saveLage(next);
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
          from: d.subtract(const Duration(days: 7)),
          to: d.add(const Duration(days: 7)),
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
        final monthStart =
            DateTime(_focusedDay.year, _focusedDay.month, 1);
        final monthEnd =
            DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
        var from = monthStart.subtract(const Duration(days: 7));
        var to = monthEnd.add(const Duration(days: 7));
        final sel = DateTime(
            _selectedDay.year, _selectedDay.month, _selectedDay.day);
        if (sel.isBefore(from)) {
          from = sel.subtract(const Duration(days: 1));
        }
        if (sel.isAfter(to)) {
          to = sel.add(const Duration(days: 1));
        }
        return (
          from: from,
          to: to,
          conflictStart: _weekStart,
          conflictDays: 0,
        );
    }
  }

  List<QueryDocumentSnapshot> _eventsForDay(
    List<QueryDocumentSnapshot> all,
    DateTime day, {
    bool includeSchedule = false,
  }) {
    final filtered = all.where((doc) {
      try {
        final d = doc.data() as Map<String, dynamic>;
        if ((d['source'] as String?) == 'calendar') {
          final kind = d['planningImportKind'] as String? ?? 'schedule';
          if (kind == 'schedule' && !includeSchedule) return false;
          if (kind != 'activity' && kind != 'schedule') return false;
        }
        if (!eventOccursOnDay(d, day)) return false;
        if (_filterPerson != null) {
          if (eventHasNoPersons(d)) return true;
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
      if (!choreOccursOnDay(d, day)) return false;
      if (_filterPerson != null) {
        return choreAssignedToOnDay(d, day,
            uid: _filterPersonUid ?? '', name: _filterPerson!);
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = choreDoneOnDay(a.data() as Map<String, dynamic>, day) ? 1 : 0;
        final db = choreDoneOnDay(b.data() as Map<String, dynamic>, day) ? 1 : 0;
        return da.compareTo(db);
      });
  }

  void _openMemberToday(
    FamilyProvider provider,
    UserModel member, [
    List<QueryDocumentSnapshot>? todayEvents,
  ]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberDaySheet(
        member: member,
        currentUser: provider.currentUser,
        initialDay: DateTime.now(),
      ),
    );
  }

  void _openCell(
    FamilyProvider provider,
    UserModel member,
    DateTime day, [
    List<QueryDocumentSnapshot>? dayEvents,
  ]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberDaySheet(
        member: member,
        currentUser: provider.currentUser,
        initialDay: day,
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
    final provider = context.read<FamilyProvider>();
    final members = provider.familyMembers;
    final fid = provider.currentUser?.familyId ?? '';
    final currentUser = provider.currentUser;

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
                    final canEdit = canEditDoc(currentUser, d);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(d['piktogram'] as String? ?? '📅'),
                      title: Text(title),
                      subtitle: t.isNotEmpty ? Text(t) : null,
                      trailing: canEdit
                          ? PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded,
                                  color: Colors.grey.shade400, size: 20),
                              onSelected: (v) {
                                Navigator.pop(ctx);
                                handleEventMenuAction(
                                  context,
                                  action: v,
                                  doc: doc,
                                  listDay: day,
                                  familyMembers: members,
                                  familyId: fid,
                                );
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Redigera'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded,
                                          size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Ta bort',
                                          style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : null,
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
      _focusedDay = _selectedDay;
    });
  }

  KalenderLage get _effectiveLage {
    final isFocus =
        context.read<FamilyProvider>().currentUser?.isFocusMode ?? false;
    if (isFocus && _lage == KalenderLage.manad) {
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

                        final presenceByUid = _presenceMap(
                          members,
                          provider.todayEvents,
                          shifts,
                          busyDocs,
                        );

                        return Column(
                          children: [
                            if (_fullscreen)
                              _buildFullscreenBar(
                                  dayColor, isFocus, effectiveLage)
                            else if (!isFocus) ...[
                              _buildCompactHeader(
                                context,
                                user?.isParent ?? false,
                                provider,
                              ),
                              QuickAddBar(
                                dense: true,
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
                              if (conflicts.isNotEmpty &&
                                  !(effectiveLage == KalenderLage.vecka &&
                                      !WindowSize.of(context).isExpanded))
                                _buildConflictStrip(provider, conflicts),
                              _buildModeSelector(dayColor, isFocus),
                              _buildPersonFilter(members, dayColor),
                            ] else ...[
                              _buildMinimalHeader(context),
                              _buildModeSelector(dayColor, isFocus),
                              _buildPersonFilter(members, dayColor),
                            ],
                            Expanded(
                              child: _buildModeContent(
                                provider,
                                members,
                                events,
                                shifts,
                                dayColor,
                                isFocus,
                                effectiveLage,
                                presenceByUid,
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
    Map<String, Color> presenceByUid,
  ) {
    final effectiveMembers = _filterPerson == null
        ? members
        : members.where((m) =>
            (_filterPersonUid != null && m.uid == _filterPersonUid) ||
            m.name == _filterPerson).toList();

    final effectiveEvents = _filterPerson == null
        ? events
        : events.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            if (eventHasNoPersons(d)) return true;
            return eventIncludesPerson(d,
                uid: _filterPersonUid ?? '', name: _filterPerson!);
          }).toList();

    final effectiveShifts = _filterPerson == null
        ? shifts
        : shifts.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return assignedToPerson(d,
                uid: _filterPersonUid ?? '', name: _filterPerson!);
          }).toList();

    final effectiveChores = _filterPerson == null
        ? provider.chores
        : provider.chores.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return choreAssignedToOnDay(d, _selectedDay,
                uid: _filterPersonUid ?? '', name: _filterPerson!);
          }).toList();

    switch (lage) {
      case KalenderLage.dag:
        return _buildAgendaDayScroll(
          provider,
          members,
          events,
          dayColor,
        );
      case KalenderLage.vecka:
        if (WindowSize.of(context).isExpanded) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              if (!_fullscreen) SliverToBoxAdapter(child: _buildWeekNav()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: members.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : WeekGrid(
                          members: effectiveMembers,
                          events: effectiveEvents,
                          shifts: effectiveShifts,
                          weekStart: _weekStart,
                          presenceRingByUid: presenceByUid,
                          onCellTap: (m, day, dayEvents) =>
                              _openCell(provider, m, day, dayEvents),
                          onFamilyRowTap: _showFamilyDaySheet,
                          onMemberAvatarTap: (m) =>
                              _openMemberToday(provider, m, provider.todayEvents),
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: navSafeBottom(context).bottom),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              if (!_fullscreen) _buildWeekNav(),
              Expanded(
                child: members.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : WeekList(
                        members: members,
                        events: effectiveEvents,
                        shifts: effectiveShifts,
                        weekStart: _weekStart,
                        presenceRingByUid: presenceByUid,
                        onCellTap: (m, day, dayEvents) =>
                            _openCell(provider, m, day, dayEvents),
                        onFamilyRowTap: _showFamilyDaySheet,
                        onMemberAvatarTap: (m) =>
                            _openMemberToday(provider, m, provider.todayEvents),
                        onConflictTap: (c) => _showConflict(provider, c),
                      ),
              ),
            ],
          );
        }
      case KalenderLage.manad:
        return KalenderMonthView(
          focusedMonth: _focusedDay,
          selectedDay: _selectedDay,
          events: effectiveEvents,
          chores: effectiveChores,
          members: effectiveMembers,
          currentUser: provider.currentUser,
          familyId: provider.currentUser?.familyId ?? '',
          onFocusedMonthChanged: (m) => setState(() => _focusedDay = m),
          onSelectedDayChanged: (d) => setState(() {
            _selectedDay = d;
            _focusedDay = DateTime(d.year, d.month);
          }),
        );
    }
  }

  /// Agenda: tidslinje (aktiviteter + tidssatta sysslor + skolklump) +
  /// undersektion "Sysslor utan tid".
  Widget _buildAgendaDayScroll(
    FamilyProvider provider,
    List<UserModel> members,
    List<QueryDocumentSnapshot> events,
    Color dayColor,
  ) {
    final day = _selectedDay;
    final dayEvents = _eventsForDay(events, day, includeSchedule: true);
    final chores = _filterChoresForDay(provider.chores, day);

    final scheduleByPerson = <String, List<QueryDocumentSnapshot>>{};
    final activities = <QueryDocumentSnapshot>[];
    for (final doc in dayEvents) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') {
        final key = _agendaPersonKey(d);
        scheduleByPerson.putIfAbsent(key, () => []).add(doc);
      } else {
        activities.add(doc);
      }
    }

    final stadChores = <QueryDocumentSnapshot>[];
    final timedChores = <QueryDocumentSnapshot>[];
    final untimedChores = <QueryDocumentSnapshot>[];
    for (final doc in chores) {
      final d = doc.data() as Map<String, dynamic>;
      final stadKey = d['stadKey'] as String?;
      if (stadKey != null && stadKey.isNotEmpty) {
        stadChores.add(doc);
        continue;
      }
      final dueTime = (d['dueTime'] as String? ?? '').trim();
      if (dueTime.isNotEmpty) {
        timedChores.add(doc);
      } else {
        untimedChores.add(doc);
      }
    }

    final timeline = <({String sort, Widget widget})>[];

    for (final entry in scheduleByPerson.entries) {
      final docs = List<QueryDocumentSnapshot>.from(entry.value);
      final firstDoc = docs.isNotEmpty
          ? (docs.first.data() as Map<String, dynamic>)
          : const <String, dynamic>{};
      final schemaLabel = schemaLabelFor(firstDoc);
      final schemaPik = schemaPiktogramFor(firstDoc);
      final who = _agendaPersonLabel(entry.key, members);
      final title = who.isEmpty ? schemaLabel : '$schemaLabel · $who';
      // Agenda: alltid klumpa (clumpSchool: true).
      for (final disp in buildScheduleDisplay(
        docs,
        clumpSchool: true,
        title: title,
        piktogram: schemaPik,
      )) {
        if (disp is ScheduleClusterEntry) {
          timeline.add((
            sort: disp.sortKey,
            widget: _AgendaSchoolCluster(
              label: disp.label,
              docs: disp.docs,
              dayColor: dayColor,
            ),
          ));
        }
      }
    }

    for (final doc in activities) {
      final d = doc.data() as Map<String, dynamic>;
      final t = (d['time'] as String? ?? '').trim();
      timeline.add((
        sort: t.isEmpty ? '99:99' : t,
        widget: AgendaActivityRow(
          doc: doc,
          dayColor: dayColor,
          listDay: day,
          familyMembers: members,
          familyId: provider.currentUser?.familyId ?? '',
          currentUser: provider.currentUser,
        ),
      ));
    }

    for (final doc in timedChores) {
      final d = doc.data() as Map<String, dynamic>;
      final t = (d['dueTime'] as String? ?? '').trim();
      timeline.add((
        sort: t,
        widget: AgendaChoreRow(
          doc: doc,
          day: day,
          dayColor: dayColor,
          familyMembers: members,
          familyId: provider.currentUser?.familyId ?? '',
          currentUser: provider.currentUser,
          allowDrag: canEditDoc(provider.currentUser, d),
          onComplete: () {},
        ),
      ));
    }

    timeline.sort((a, b) => a.sort.compareTo(b.sort));

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildAgendaDayNav()),
        if (timeline.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Inga tidssatta poster den här dagen.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          ...timeline.map((e) => SliverToBoxAdapter(child: e.widget)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text('SYSSLOR UTAN TID', style: AppTheme.sectionLabelStyle),
          ),
        ),
        if (stadChores.isEmpty && untimedChores.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Center(
                child: Text(
                  'Inga sysslor utan tid.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else ...[
          if (stadChores.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildStaddagAgendaCard(
                context: context,
                stadDocs: stadChores,
                day: day,
                dayColor: dayColor,
              ),
            ),
          if (untimedChores.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => AgendaChoreRow(
                  doc: untimedChores[i],
                  day: day,
                  dayColor: dayColor,
                  familyMembers: members,
                  familyId: provider.currentUser?.familyId ?? '',
                  currentUser: provider.currentUser,
                  allowDrag: canEditDoc(
                    provider.currentUser,
                    untimedChores[i].data() as Map<String, dynamic>,
                  ),
                  onComplete: () {},
                ),
                childCount: untimedChores.length,
              ),
            ),
        ],
        SliverToBoxAdapter(
            child: SizedBox(height: navSafeBottom(context).bottom)),
      ],
    );
  }

  Widget _buildStaddagAgendaCard({
    required BuildContext context,
    required List<QueryDocumentSnapshot> stadDocs,
    required DateTime day,
    required Color dayColor,
  }) {
    final doneCount = stadDocs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return choreDoneOnDay(d, day);
    }).length;
    final totalCount = stadDocs.length;
    final isAllDone = totalCount > 0 && doneCount == totalCount;

    String recText = 'varje lördag';
    if (stadDocs.isNotEmpty) {
      final firstD = stadDocs.first.data() as Map<String, dynamic>;
      if (choreIsRecurring(firstD)) {
        recText = recurrenceLabel(firstD);
      }
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isAllDone ? 0.65 : 1.0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: AppTheme.cardDecoration(radius: 16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StaddagPage()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('🧹', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Städdag · $doneCount av $totalCount klara',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            decoration:
                                isAllDone ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '🔁 $recText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
      ),
    );
  }

  String _agendaPersonKey(Map<String, dynamic> d) {
    final uids = (d['personUids'] as List?)?.cast<String>() ?? const [];
    if (uids.isNotEmpty) return 'u:${uids.first}';
    final persons = (d['persons'] as List? ?? []).cast<String>();
    if (persons.isNotEmpty) return 'n:${persons.first}';
    return 'shared';
  }

  String _agendaPersonLabel(String key, List<UserModel> members) {
    if (key == 'shared') return '';
    if (key.startsWith('u:')) {
      final uid = key.substring(2);
      for (final m in members) {
        if (m.uid == uid) return m.name.split(' ').first;
      }
    }
    if (key.startsWith('n:')) return key.substring(2).split(' ').first;
    return '';
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

  void _openBusySheet(FamilyProvider provider) {
    final me = provider.currentUser;
    final fid = me?.familyId;
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
  }

  Widget _buildCompactHeader(
    BuildContext context,
    bool isParent,
    FamilyProvider provider,
  ) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(
        context,
        horizontal: 12,
        extraBelowStatus: 6,
        bottom: 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Kalender',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          if (provider.hasHomeLocation) ...[
            WeatherHeaderBadge(
              lat: provider.homeLat!,
              lon: provider.homeLon!,
              placeName: provider.homeName,
              textColor: textColor,
            ),
            const SizedBox(width: 4),
          ],
          TextButton.icon(
            onPressed: () => _openBusySheet(provider),
            icon: Icon(
              Icons.do_not_disturb_on_rounded,
              color: textColor,
              size: 18,
            ),
            label: Text(
              'Upptagen',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
              foregroundColor: textColor,
            ),
          ),
          IconButton(
            tooltip: _fullscreen ? 'Avsluta helskärm' : 'Helskärm',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: Icon(
              _fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: textColor,
            ),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenBar(
    Color dayColor,
    bool isFocus,
    KalenderLage effectiveLage,
  ) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    final provider = context.read<FamilyProvider>();
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(
        context,
        horizontal: 4,
        extraBelowStatus: 4,
        bottom: 4,
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.chevron_left_rounded, color: textColor),
            onPressed: () => _shiftPeriod(-1, effectiveLage),
          ),
          Expanded(
            child: Text(
              _periodLabel(effectiveLage),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.chevron_right_rounded, color: textColor),
            onPressed: () => _shiftPeriod(1, effectiveLage),
          ),
          Flexible(
            child: _buildCompactModeChips(dayColor, isFocus),
          ),
          IconButton(
            tooltip: 'Jag är upptagen',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.do_not_disturb_on_rounded, color: textColor),
            onPressed: () => _openBusySheet(provider),
          ),
          IconButton(
            tooltip: 'Avsluta helskärm',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.fullscreen_exit_rounded, color: textColor),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  String _periodLabel(KalenderLage lage) {
    switch (lage) {
      case KalenderLage.dag:
        return DateFormat('EEE d MMM', 'sv').format(_selectedDay);
      case KalenderLage.vecka:
        final end = _weekStart.add(const Duration(days: 6));
        return '${DateFormat('d MMM', 'sv').format(_weekStart)}-${DateFormat('d MMM', 'sv').format(end)}';
      case KalenderLage.manad:
        return DateFormat('MMMM y', 'sv').format(_focusedDay);
    }
  }

  void _shiftPeriod(int delta, KalenderLage lage) {
    setState(() {
      switch (lage) {
        case KalenderLage.dag:
          _selectedDay = DateTime(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day + delta,
          );
          _focusedDay = _selectedDay;
          break;
        case KalenderLage.vecka:
          _weekStart = DateTime(
            _weekStart.year,
            _weekStart.month,
            _weekStart.day + 7 * delta,
          );
          break;
        case KalenderLage.manad:
          _focusedDay = DateTime(
            _focusedDay.year,
            _focusedDay.month + delta,
            1,
          );
          break;
      }
    });
  }

  Widget _buildCompactModeChips(Color dayColor, bool isFocus) {
    final modes = isFocus
        ? const [KalenderLage.dag, KalenderLage.vecka]
        : KalenderLage.values;
    final labels = {
      KalenderLage.dag: 'D',
      KalenderLage.vecka: 'V',
      KalenderLage.manad: 'M',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in modes)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(labels[m]!, style: const TextStyle(fontSize: 12)),
                selected: _effectiveLage == m ||
                    (_lage == m && !(isFocus && m == KalenderLage.manad)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selectedColor: dayColor,
                labelStyle: TextStyle(
                  color: (_effectiveLage == m) ? Colors.white : null,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: (_) => _setLage(m),
              ),
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
        ? const [
            ButtonSegment(
              value: KalenderLage.dag,
              label: Text('Dag'),
            ),
            ButtonSegment(
              value: KalenderLage.vecka,
              label: Text('Vecka'),
            ),
          ]
        : const [
            ButtonSegment(value: KalenderLage.dag, label: Text('Dag')),
            ButtonSegment(value: KalenderLage.vecka, label: Text('Vecka')),
            ButtonSegment(value: KalenderLage.manad, label: Text('Månad')),
          ];

    final selected = isFocus
        ? (_lage == KalenderLage.vecka
            ? {KalenderLage.vecka}
            : {KalenderLage.dag})
        : {_lage};

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<KalenderLage>(
            showSelectedIcon: false,
            segments: segments,
            selected: selected,
            onSelectionChanged: (s) {
              _setLage(s.first);
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
          if (isFocus) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '🔎 Förenklad vy',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: dayColor,
                  ),
                  onPressed: () async {
                    final user = context.read<FamilyProvider>().currentUser;
                    if (user == null) return;
                    final normalMode = user.isParent
                        ? 'parent'
                        : (user.role == 'youth' ? 'youth' : 'child');
                    await UserService.updateViewMode(user.uid, normalMode);
                  },
                  child: const Text(
                    'Visa allt',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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

class _AgendaSchoolCluster extends StatefulWidget {
  final String label;
  final List<QueryDocumentSnapshot> docs;
  final Color dayColor;

  const _AgendaSchoolCluster({
    required this.label,
    required this.docs,
    required this.dayColor,
  });

  @override
  State<_AgendaSchoolCluster> createState() => _AgendaSchoolClusterState();
}

class _AgendaSchoolClusterState extends State<_AgendaSchoolCluster> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: const Color(0xFFE8F0FE),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: widget.dayColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            for (final doc in widget.docs)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 20, right: 8),
                title: Builder(builder: (context) {
                  final d = doc.data() as Map<String, dynamic>;
                  final t = (d['time'] as String? ?? '').trim();
                  final end = (d['endTime'] as String? ?? '').trim();
                  final title = d['title'] as String? ?? '';
                  final time =
                      t.isEmpty ? '' : (end.isEmpty ? t : '$t–$end');
                  return Text(time.isEmpty ? title : '$time  $title');
                }),
                onTap: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ActivityDetailSheet(docSnapshot: doc),
                  );
                },
              ),
        ],
      ),
    );
  }
}

