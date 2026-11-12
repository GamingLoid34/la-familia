import 'package:family_routines/family_routines.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/family_provider.dart';
import '../../models/user_model.dart';
import '../../models/planning_task.dart';
import '../../utils/date_utils.dart';
import '../../utils/recurrence.dart';
import '../../utils/schedule_time_utils.dart';
import '../../utils/person_match.dart';

class WallEntry {
  final String title, detail;
  final Color color;
  const WallEntry(
    this.title,
    this.detail, {
    this.color = const Color(0xFF8BE0C8),
  });
}

List<WallEntry> sortWallRows(List<WallEntry> rows) {
  String time(WallEntry row) =>
      RegExp(r'^\d{2}:\d{2}').stringMatch(row.detail) ?? '';
  return [...rows]..sort((a, b) => time(a).compareTo(time(b)));
}

/// Every row is shown: overflow rotates in readable pages, never scrolls.
List<T> wallPage<T>(List<T> rows, int capacity, int tick) {
  if (rows.isEmpty) return [];
  final pages = (rows.length / capacity).ceil();
  final start = (tick % pages) * capacity;
  return rows.skip(start).take(capacity).toList();
}

class FamilyWall extends StatelessWidget {
  const FamilyWall({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FamilyProvider>();
    final user = p.currentUser;
    if (user == null || user.familyId == null) {
      return const Scaffold(
        body: Center(child: Text('Logga in för att visa familjens kalender.')),
      );
    }
    return _LiveWall(
      key: ValueKey('${user.uid}/${user.familyId}/${user.role}'),
      familyId: user.familyId!,
      parent: user.isParent,
    );
  }
}

class _LiveWall extends StatefulWidget {
  final String familyId;
  final bool parent;
  const _LiveWall({super.key, required this.familyId, required this.parent});
  @override
  State<_LiveWall> createState() => _LiveWallState();
}

class _LiveWallState extends State<_LiveWall> with WidgetsBindingObserver {
  final _subscriptions = <StreamSubscription>[];
  final _rows = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  final _errors = <String>{};
  final _cached = <String>{};
  Timer? _timer;
  DateTime _now = DateTime.now();
  int _tick = 0, _generation = 0;
  DateTime? _confirmed;
  bool get _showTasks =>
      widget.parent && Uri.base.queryParameters['tasks'] == '1';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  void _refresh() {
    final now = DateTime.now();
    if (dateKey(now) != dateKey(_now)) {
      _now = now;
      _subscribe();
    }
    if (mounted) {
      setState(() {
        _now = now;
        _tick++;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _subscribe() {
    final generation = ++_generation;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    _rows.clear();
    _errors.clear();
    _cached.clear();
    _confirmed = null;
    final db = FirebaseFirestore.instance;
    final events = db
        .collection('planner_events')
        .where('familyId', isEqualTo: widget.familyId);
    final queries = <String, Query<Map<String, dynamic>>>{
      'dated': events
          .where('date', isGreaterThanOrEqualTo: dateKey(_now))
          .where(
            'date',
            isLessThanOrEqualTo: dateKey(
              DateTime(_now.year, _now.month, _now.day + 7),
            ),
          ),
      'recurring': events.where('isRecurring', isEqualTo: true),
      'shifts': db
          .collection('work_shifts')
          .where('familyId', isEqualTo: widget.familyId),
      if (_showTasks)
        'tasks': db
            .collection('tasks')
            .where('familyId', isEqualTo: widget.familyId),
    };
    for (final entry in queries.entries) {
      _subscriptions.add(
        entry.value
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snap) {
                if (!mounted || generation != _generation) return;
                setState(() {
                  _rows[entry.key] = snap.docs;
                  _errors.remove(entry.key);
                  if (snap.metadata.isFromCache ||
                      snap.metadata.hasPendingWrites) {
                    _cached.add(entry.key);
                  } else {
                    _cached.remove(entry.key);
                    _confirmed = DateTime.now();
                  }
                });
              },
              onError: (Object error) {
                if (!mounted || generation != _generation) return;
                setState(() {
                  _errors.add(entry.key);
                  _rows.remove(entry.key);
                });
              },
            ),
      );
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  List<WallEntry> _events(DateTime day, List<UserModel> members) {
    final unique = {
      for (final key in ['dated', 'recurring'])
        for (final d
            in _rows[key] ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
          d.id: d.data(),
    };
    final entries =
        unique.values
            .where(
              (d) => d['recurrence'] != null
                  ? recurringOccursOnDay(d, day)
                  : eventOccursOnDay(d, day),
            )
            .toList()
          ..sort(
            (a, b) => (a['time'] as String? ?? '').compareTo(
              b['time'] as String? ?? '',
            ),
          );
    return sortWallRows([
      for (final e in entries)
        WallEntry(
          e['title'] as String? ?? 'Aktivitet',
          [
            (e['time'] as String? ?? '').isEmpty
                ? 'Hela dagen'
                : '${e['time']}${e['endTime'] != null ? '–${e['endTime']}' : ''}',
            eventHasNoPersons(e)
                ? 'Familjen'
                : members
                      .where(
                        (m) => eventIncludesPerson(e, uid: m.uid, name: m.name),
                      )
                      .map((m) => m.name.split(' ').first)
                      .join(', '),
            if ((e['location'] as String? ?? '').isNotEmpty)
              e['location'] as String,
          ].where((v) => v.isNotEmpty).join(' · '),
        ),
      for (final d
          in _rows['shifts'] ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        if (shiftTouchesDay(d.data(), day))
          WallEntry(
            'Arbetspass',
            '${d.data()['startTime'] ?? d.data()['time'] ?? ''}–${d.data()['endTime'] ?? ''} · ${d.data()['person'] ?? d.data()['who'] ?? ''}',
            color: const Color(0xFFFFCE8A),
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final members = context.watch<FamilyProvider>().familyMembers;
    final tomorrow = DateTime(_now.year, _now.month, _now.day + 1);
    final upcoming = <WallEntry>[];
    for (var i = 1; i <= 6; i++) {
      final day = DateTime(_now.year, _now.month, _now.day + i);
      upcoming.addAll(
        _events(day, members).map(
          (e) => WallEntry(
            e.title,
            '${i == 1 ? 'I morgon' : DateFormat('EEE d/M', 'sv_SE').format(day)} · ${e.detail}',
            color: e.color,
          ),
        ),
      );
    }
    final tasks =
        (_rows['tasks'] ?? [])
            .map((d) => PlanningTask(d.id, d.data()))
            .where((t) => t.visibleOn(dateKey(_now), dateKey(tomorrow)))
            .toList()
          ..sort(
            (a, b) => (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999'),
          );
    final status = _errors.isNotEmpty
        ? 'Kunde inte hämta alla data · försök ladda om'
        : _cached.isNotEmpty
        ? 'Offline eller väntar på server · visar sparade data'
        : _rows.length < _subscriptions.length
        ? 'Hämtar familjens kalender…'
        : 'Ansluten · kontrollerad ${_confirmed == null ? '–' : DateFormat('HH:mm').format(_confirmed!)}';
    return FamilyRoutineWall(
      familyId: widget.familyId,
      calendarStatus: _errors.isNotEmpty || _cached.isNotEmpty ? status : '',
      calendarSummary:
          'Idag: ${_events(_now, members).take(4).map((e) => "${e.detail} ${e.title}").join(" · ")}',
      calendar: FamilyWallBoard(
        now: _now,
        members: members.map((m) => m.name.split(' ').first).toList(),
        today: _events(_now, members),
        upcoming: upcoming,
        tasks: [
          for (final t in tasks)
            WallEntry(
              t.title,
              t.dueDate == null ? 'Ingen sista dag' : 'Senast ${t.dueDate}',
              color: const Color(0xFFC5B5FF),
            ),
        ],
        showTasks: _showTasks,
        tick: _tick,
        status: status,
      ),
    );
  }
}

class FamilyWallBoard extends StatelessWidget {
  final DateTime now;
  final List<String> members;
  final List<WallEntry> today, upcoming, tasks;
  final bool showTasks;
  final int tick;
  final String status;
  const FamilyWallBoard({
    super.key,
    required this.now,
    required this.members,
    required this.today,
    required this.upcoming,
    this.tasks = const [],
    this.showTasks = false,
    this.tick = 0,
    this.status = '',
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101D2B),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < 1000;
          final capacity = ((box.maxHeight - 400) / 112).floor().clamp(1, 12);
          return Padding(
            padding: EdgeInsets.all(compact ? 20 : 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'VARDAG / FAMILJEN',
                            style: TextStyle(
                              color: Color(0xFF8BE0C8),
                              fontSize: 18,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('EEEE d MMMM', 'sv_SE').format(now),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 28 : 38,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            members.join('   ·   '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB9C8D7),
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      DateFormat('HH:mm').format(now),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 48 : 72,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _panel(
                          'Idag',
                          today,
                          capacity,
                          const Color(0xFF8BE0C8),
                          'Inget planerat i dag',
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 5,
                        child: _panel(
                          'Kommande dagar',
                          upcoming,
                          capacity,
                          const Color(0xFFFFCE8A),
                          'Inget mer planerat de närmaste dagarna',
                        ),
                      ),
                      if (showTasks) ...[
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 4,
                          child: _panel(
                            'Att komma ihåg',
                            tasks,
                            capacity,
                            const Color(0xFFC5B5FF),
                            'Inga aktuella uppgifter',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$status · Fler rader visas automatiskt var 20:e sekund',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB9C8D7),
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
  Widget _panel(
    String title,
    List<WallEntry> entries,
    int capacity,
    Color accent,
    String empty,
  ) {
    final pages = (entries.length / capacity).ceil();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2B3D),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (pages > 1)
                Text(
                  '${tick % pages + 1}/$pages',
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            Text(
              empty,
              style: const TextStyle(color: Colors.white70, fontSize: 22),
            ),
          for (final entry in wallPage(entries, capacity, tick))
            Container(
              height: 108,
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 72,
                    decoration: BoxDecoration(
                      color: entry.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB9C8D7),
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
