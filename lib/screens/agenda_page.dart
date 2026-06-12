import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../providers/family_provider.dart';
import '../widgets/activity_detail_sheet.dart';
import '../services/notification_service.dart';
import '../widgets/planner_event_leading.dart';
import '../widgets/quick_add_bar.dart';
import 'calendar_import_page.dart';
import 'chores_page.dart';
import 'planner_page.dart';
import 'work_schedule_page.dart';

enum AgendaTab { all, activities, chores }

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

int? _hhmmToMinutesAgenda(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  final p = t.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m.clamp(0, 59);
}

String? _latestHhmmAgenda(Iterable<String?> candidates) {
  String? best;
  var bestM = -1;
  for (final c in candidates) {
    final mm = _hhmmToMinutesAgenda(c);
    if (mm != null && mm > bestM) {
      bestM = mm;
      best = c!.trim();
    }
  }
  return best;
}

String? _earliestHhmmAgenda(Iterable<String?> candidates) {
  String? best;
  var bestM = 24 * 60 + 999;
  for (final c in candidates) {
    final mm = _hhmmToMinutesAgenda(c);
    if (mm != null && mm < bestM) {
      bestM = mm;
      best = c!.trim();
    }
  }
  return best;
}

bool _agendaEventSameDay(Map<String, dynamic> d, DateTime day) =>
    eventOccursOnDay(d, day);

bool _agendaIsScheduleCalendarImport(Map<String, dynamic> d) {
  if (d['source'] != 'calendar') return false;
  final kind = d['planningImportKind'] as String? ?? 'schedule';
  return kind == 'schedule';
}

/// En rad: `schema 08:15 - 15:20` (tidigaste start bland passen – senaste slut).
String _schemaSpanFromDocs(List<QueryDocumentSnapshot> docs) {
  if (docs.isEmpty) return 'schema';
  final startCandidates = <String?>[];
  final endCandidates = <String?>[];
  for (final doc in docs) {
    final d = doc.data() as Map<String, dynamic>;
    final st = (d['time'] as String? ?? '').trim();
    if (st.isNotEmpty) startCandidates.add(st);
    final et = (d['endTime'] as String? ?? '').trim();
    if (et.isNotEmpty) {
      endCandidates.add(et);
    } else if (st.isNotEmpty) {
      endCandidates.add(st);
    }
  }
  final earliest = _earliestHhmmAgenda(startCandidates);
  final latest = _latestHhmmAgenda(endCandidates);
  if (earliest != null && latest != null) {
    if (earliest == latest) return 'schema $earliest';
    return 'schema $earliest - $latest';
  }
  if (earliest != null) return 'schema från $earliest';
  if (latest != null) return 'schema till $latest';
  return 'schema';
}

class AgendaPage extends StatefulWidget {
  final AgendaTab initialTab;
  /// Filtrera på fullständigt namn (samma som i Firestore `persons` / `who`).
  final String? initialPersonFilter;
  /// Uid för samma person — används för rename-säker matchning (Etapp 3).
  final String? initialPersonFilterUid;

  const AgendaPage({
    super.key,
    this.initialTab = AgendaTab.all,
    this.initialPersonFilter,
    this.initialPersonFilterUid,
  });

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late AgendaTab _tab;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  String? _filterPerson;
  String? _filterPersonUid;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _filterPerson = widget.initialPersonFilter;
    _filterPersonUid = widget.initialPersonFilterUid;
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
    final list = docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!_choreVisibleOnDay(d, day)) return false;
      if (_filterPerson != null) {
        return assignedToPerson(d,
            uid: _filterPersonUid ?? '', name: _filterPerson!);
      }
      return true;
    }).toList();

    list.sort((a, b) {
      final da = (a.data() as Map)['isDone'] == true ? 1 : 0;
      final db = (b.data() as Map)['isDone'] == true ? 1 : 0;
      return da.compareTo(db);
    });

    return list;
  }

  Stream<QuerySnapshot>? _templatesStream(String? familyId) {
    if (familyId == null || familyId.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('chore_templates')
        .where('familyId', isEqualTo: familyId)
        .snapshots();
  }

  Future<void> _addChoreFromTemplate(
    Map<String, dynamic> template,
    String familyId,
    List<UserModel> members,
  ) async {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, 1, 1);
    final weekNum =
        ((now.difference(firstDay).inDays + firstDay.weekday - 1) / 7).ceil();
    final weekOf = '${now.year}-W$weekNum';
    final title = template['title'] as String? ?? '';
    if (title.isEmpty) return;
    final who = template['defaultWho'] as String? ?? '';
    String whoColor = '';
    if (who.isNotEmpty) {
      for (final m in members) {
        if (m.name == who) {
          whoColor = m.color;
          break;
        }
      }
    }
    final d = _selectedDay;
    final points = (template['points'] as int?) ?? 10;
    final pik = template['piktogram'] as String? ?? '✅';
    await FirebaseFirestore.instance.collection('chores').add({
      'chore': title,
      'piktogram': pik,
      'who': who,
      'whoUid': uidForName(members, who),
      'whoColor': whoColor,
      'isDone': false,
      'points': points,
      'isRecurring': false,
      'familyId': familyId,
      'weekOf': weekOf,
      'dueDate': dateKey(d),
      'substeps': <Map<String, dynamic>>[],
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Syssla från mall tillagd'),
        backgroundColor: Color(0xFF6BAE75),
      ),
    );
  }

  Widget _buildChoreTemplatesStrip(
    BuildContext context,
    String? familyId,
    List<UserModel> members,
    bool isParent,
    Color dayColor,
  ) {
    final stream = _templatesStream(familyId);
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        final raw = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
        final docs = List<QueryDocumentSnapshot>.from(raw)
          ..sort((a, b) {
            final ta =
                (a.data() as Map)['title'] as String? ?? '';
            final tb =
                (b.data() as Map)['title'] as String? ?? '';
            return ta.toLowerCase().compareTo(tb.toLowerCase());
          });
        if (docs.isEmpty && !isParent) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MALLAR', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Inga mallar ännu — de skapas när du lägger till en syssla.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final doc = docs[i];
                      final d = doc.data() as Map<String, dynamic>;
                      final title = d['title'] as String? ?? '';
                      final pik = d['piktogram'] as String? ?? '✅';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: familyId == null || familyId.isEmpty
                              ? null
                              : () => _addChoreFromTemplate(
                                    d,
                                    familyId,
                                    members,
                                  ),
                          onLongPress: isParent
                              ? () async {
                                  final del = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Ta bort mall?'),
                                      content: Text('"$title" tas bort.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('Avbryt'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red),
                                          child: const Text('Ta bort'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (del == true) {
                                    await NotificationService.cancel(doc.id);
                                    await doc.reference.delete();
                                  }
                                }
                              : null,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: dayColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: dayColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(pik, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Stream<QuerySnapshot>? _plannerStreamFor(String? familyId) {
    if (familyId == null || familyId.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .snapshots();
  }

  Stream<QuerySnapshot>? _workShiftsStreamFor(String? familyId) {
    if (familyId == null || familyId.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('work_shifts')
        .where('familyId', isEqualTo: familyId)
        .snapshots();
  }

  List<UserModel> _membersForGlance(List<UserModel> all) {
    if (_filterPerson == null) return all;
    return all.where((m) => m.name == _filterPerson).toList();
  }

  String? _glanceLineForPerson(
    UserModel member,
    List<QueryDocumentSnapshot> shiftDocs,
    List<QueryDocumentSnapshot> allPlanner,
    DateTime day,
  ) {
    final parts = <String>[];

    final dayShifts = shiftDocs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final date = parseDate(d['date']);
      if (date == null || !isSameDay(date, day)) return false;
      return assignedToPerson(d, uid: member.uid, name: member.name);
    }).toList();

    if (dayShifts.length == 1) {
      final d = dayShifts.first.data() as Map<String, dynamic>;
      final a = (d['startTime'] as String? ?? '').trim();
      final b = (d['endTime'] as String? ?? '').trim();
      if (a.isNotEmpty && b.isNotEmpty) {
        parts.add('Jobb $a–$b');
      } else if (a.isNotEmpty) {
        parts.add('Jobb från $a');
      }
    } else if (dayShifts.length > 1) {
      parts.add('${dayShifts.length} arbetspass');
    }

    final calForPerson = allPlanner.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!_agendaEventSameDay(d, day)) return false;
      if (!_agendaIsScheduleCalendarImport(d)) return false;
      if (eventHasNoPersons(d)) return false;
      return eventIncludesPerson(d, uid: member.uid, name: member.name);
    }).toList();

    if (calForPerson.isNotEmpty) {
      parts.add(_schemaSpanFromDocs(calForPerson));
    }

    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String? _glanceSharedCalendar(
    List<QueryDocumentSnapshot> allPlanner,
    DateTime day,
  ) {
    final shared = allPlanner.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!_agendaEventSameDay(d, day)) return false;
      if (!_agendaIsScheduleCalendarImport(d)) return false;
      return eventHasNoPersons(d);
    }).toList();

    if (shared.isEmpty) return null;
    final span = _schemaSpanFromDocs(shared);
    if (span == 'schema') return 'Gemensamt schema';
    return 'Gemensamt $span';
  }

  Widget _buildScheduleGlanceStrip(
    BuildContext context,
    List<UserModel> members,
    Color dayColor,
    List<QueryDocumentSnapshot> shiftDocs,
    List<QueryDocumentSnapshot> allPlanner,
    DateTime day,
  ) {
    if (members.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (final m in _membersForGlance(members)) {
      final line =
          _glanceLineForPerson(m, shiftDocs, allPlanner, day);
      if (line == null) continue;
      Color mc;
      try {
        mc = Color(m.colorValue as int);
      } catch (_) {
        mc = dayColor;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration:
                    BoxDecoration(color: mc, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: Colors.grey.shade800,
                    ),
                    children: [
                      TextSpan(
                        text: '${m.name.split(' ').first}: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: line),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final shared = _glanceSharedCalendar(allPlanner, day);
    if (shared != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.groups_outlined,
                  size: 18, color: dayColor.withValues(alpha: 0.85)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shared,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => WorkSchedulePage(
                  openWithAllMembers: _filterPerson == null,
                  initialPersonName: _filterPerson,
                  initialDay: day,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: dayColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: dayColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 20, color: dayColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SCHEMA & ARBETE (vald dag)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: dayColor,
                        ),
                      ),
                    ),
                    Text(
                      'Scheman',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: dayColor,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: dayColor),
                  ],
                ),
                const SizedBox(height: 10),
                ...rows,
                const SizedBox(height: 4),
                Text(
                  'Tryck för hela dagen i Scheman',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    final members = provider.familyMembers;
    final isFocus = user?.isFocusMode ?? false;
    final dayColor = AppTheme.getDayAccentColor();
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final chores = _filterChoresForDay(provider.chores, _selectedDay);

    return Container(
      decoration: AppTheme.getBackground(),
      child: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _plannerStreamFor(user?.familyId),
            builder: (ctx, snap) {
              final allEvents = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
              final eventsForSelected = _eventsForDay(allEvents, _selectedDay);
              final shiftStream = _workShiftsStreamFor(user?.familyId);

              Widget buildScroll(List<QueryDocumentSnapshot> shiftDocs) {
                final activitiesOnly = eventsForSelected;

                return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                      child: _buildHeader(context, dayColor)),
                  // Snabbinmatning (Etapp 10): en rad → tolkad aktivitet.
                  SliverToBoxAdapter(
                    child: QuickAddBar(
                      familyMembers: provider.familyMembers,
                      familyId: user?.familyId ?? '',
                      onFallbackToForm: (raw) {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => AddEventSheet(
                            selectedDay: _selectedDay,
                            familyMembers: provider.familyMembers,
                            familyId: user?.familyId ?? '',
                            initialTitle: raw,
                          ),
                        );
                      },
                    ),
                  ),
                  if (!isFocus) ...[
                    SliverToBoxAdapter(
                      child: _buildTabs(dayColor),
                    ),
                    SliverToBoxAdapter(
                      child: _buildCalendar(allEvents, dayColor),
                    ),
                    SliverToBoxAdapter(
                      child: _buildPersonFilter(members, dayColor),
                    ),
                    if (_tab != AgendaTab.activities)
                      SliverToBoxAdapter(
                        child: _buildChoreTemplatesStrip(
                          context,
                          user?.familyId,
                          members,
                          user?.isParent ?? false,
                          dayColor,
                        ),
                      ),
                  ],
                  SliverToBoxAdapter(
                    child: _buildScheduleGlanceStrip(
                      context,
                      members,
                      dayColor,
                      shiftDocs,
                      allEvents,
                      _selectedDay,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                      child: Text(
                        () {
                          try {
                            return DateFormat('EEEE d MMMM', 'sv')
                                .format(_selectedDay);
                          } catch (_) {
                            return DateFormat('d MMMM').format(_selectedDay);
                          }
                        }(),
                        style: AppTheme.sectionTitleStyle,
                      ),
                    ),
                  ),
                  if (_tab != AgendaTab.chores) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Text(
                          'AKTIVITETER',
                          style: AppTheme.sectionLabelStyle,
                        ),
                      ),
                    ),
                    if (activitiesOnly.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          padding: const EdgeInsets.all(22),
                          decoration: AppTheme.cardDecoration(),
                          child: const Center(
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
                          (_, i) {
                            return _ActivityRow(
                              doc: activitiesOnly[i],
                              dayColor: dayColor,
                              listDay: _selectedDay,
                              familyMembers: members,
                              familyId: user?.familyId ?? '',
                            );
                          },
                          childCount: activitiesOnly.length,
                        ),
                      ),
                  ],
                  if (_tab != AgendaTab.activities) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 18, 16, 6),
                        child: Text(
                          'SYSSLOR',
                          style: AppTheme.sectionLabelStyle,
                        ),
                      ),
                    ),
                    if (chores.isEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          padding: const EdgeInsets.all(22),
                          decoration: AppTheme.cardDecoration(),
                          child: const Center(
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
                          (_, i) => _ChoreRow(
                            doc: chores[i],
                            dayColor: dayColor,
                            familyMembers: members,
                            familyId: user?.familyId ?? '',
                            allowDrag: _tab != AgendaTab.activities,
                          ),
                          childCount: chores.length,
                        ),
                      ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 140)),
                ],
              );
              }

              if (shiftStream == null) {
                return buildScroll(const <QueryDocumentSnapshot>[]);
              }
              return StreamBuilder<QuerySnapshot>(
                stream: shiftStream,
                builder: (ctx2, snap2) {
                  final shiftDocs =
                      snap2.data?.docs ?? const <QueryDocumentSnapshot>[];
                  return buildScroll(shiftDocs);
                },
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: bottomPad + 16,
            child: FloatingActionButton(
              heroTag: 'agenda_add',
              onPressed: () => _showAddSheet(context, provider, dayColor),
              backgroundColor: dayColor,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, FamilyProvider provider, Color dayColor) {
    if (provider.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Laddar familjedata... försök igen'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTypeSheet(
        dayColor: dayColor,
        showPlanningExtras: provider.currentUser?.isParent ?? false,
        onCalendarImportTap: () {
          Navigator.pop(context);
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const CalendarImportPage(),
            ),
          );
        },
        onActivityTap: () {
          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => AddEventSheet(
              selectedDay: _selectedDay,
              familyMembers: provider.familyMembers,
              familyId: provider.currentUser?.familyId ?? '',
            ),
          );
        },
        onChoreTap: () {
          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => AddChoreSheet(
              familyMembers: provider.familyMembers,
              familyId: provider.currentUser?.familyId ?? '',
              preselectedDay: _selectedDay,
              startOnForm: true,
            ),
          );
        },
        onQuickChoreTap: () {
          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => QuickChoreSheet(
              familyMembers: provider.familyMembers,
              familyId: provider.currentUser?.familyId,
              selectedDay: _selectedDay,
            ),
          );
        },
        onWorkShiftTap: () {
          Navigator.pop(context);
          final fid = provider.currentUser?.familyId ?? '';
          if (fid.isEmpty) return;
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => AddWorkShiftSheet(
              familyId: fid,
              familyMembers: provider.familyMembers,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color dayColor) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context, bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Planering',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(Color dayColor) {
    final narrow = MediaQuery.sizeOf(context).width < 380;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: SegmentedButton<AgendaTab>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: AgendaTab.all,
            label: Text(
              'Alla',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: narrow ? 11 : 13),
            ),
          ),
          ButtonSegment(
            value: AgendaTab.activities,
            label: Text(
              narrow ? 'Aktivitet' : 'Aktiviteter',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: narrow ? 11 : 13),
            ),
          ),
          ButtonSegment(
            value: AgendaTab.chores,
            label: Text(
              'Sysslor',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: narrow ? 11 : 13),
            ),
          ),
        ],
        selected: {_tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
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

  Widget _agendaDayCellWithChoreDrop(
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

    if (_tab == AgendaTab.activities) {
      return cell(const Duration(milliseconds: 250));
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
            SnackBar(
              content: Text('Kunde inte flytta: $e'),
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

  Widget _buildCalendar(List<QueryDocumentSnapshot> all, Color dayColor) {
    final calStyle = CalendarStyle(
      cellMargin: EdgeInsets.zero,
      selectedDecoration:
          BoxDecoration(color: dayColor, shape: BoxShape.circle),
      todayDecoration: BoxDecoration(
          color: dayColor.withValues(alpha: 0.3),
          shape: BoxShape.circle),
      markerDecoration:
          BoxDecoration(color: dayColor, shape: BoxShape.circle),
      markersMaxCount: 1,
      markerSize: 5,
      markerMargin: const EdgeInsets.only(top: 2),
      outsideDaysVisible: false,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: AppTheme.cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: TableCalendar(
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableGestures: AvailableGestures.horizontalSwipe,
            selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
            calendarFormat: _calendarFormat,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Månad',
              CalendarFormat.week: 'Vecka',
            },
            onFormatChanged: (f) => setState(() => _calendarFormat = f),
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
                  _agendaDayCellWithChoreDrop(
                context,
                day,
                dayColor,
                calStyle,
                decoration: calStyle.selectedDecoration,
                textStyle: calStyle.selectedTextStyle,
              ),
              todayBuilder: (context, day, focusedDay) =>
                  _agendaDayCellWithChoreDrop(
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
                return _agendaDayCellWithChoreDrop(
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
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              formatButtonShowsNext: false,
              titleCentered: true,
              titleTextStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
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
          _Pill(
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
              mc = Color(m.colorValue as int);
            } catch (_) {
              mc = dayColor;
            }
            return _Pill(
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
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _Pill({
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

class _ActivityRow extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;
  final DateTime listDay;
  final List<UserModel> familyMembers;
  final String familyId;

  const _ActivityRow({
    required this.doc,
    required this.dayColor,
    required this.listDay,
    required this.familyMembers,
    required this.familyId,
  });

  Future<void> _handleMenu(BuildContext context, String value) async {
    if (value == 'edit') {
      final d = doc.data() as Map<String, dynamic>;
      var day = listDay;
      final pd = parseDate(d['date']);
      if (pd != null) day = pd;
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AddEventSheet(
          selectedDay: day,
          familyMembers: familyMembers,
          familyId: familyId.isEmpty ? null : familyId,
          eventToEdit: doc,
        ),
      );
    } else if (value == 'delete') {
      final d = doc.data() as Map<String, dynamic>;
      final isRecurring = d['recurrence'] != null;

      if (isRecurring) {
        // Återkommande: fråga om bara denna dag eller alla gånger.
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ta bort återkommande aktivitet?'),
            content: Text(
                '"${d['title'] ?? ''}" upprepas (${recurrenceLabel(d)}).'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Avbryt'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'single'),
                child: const Text('Bara denna dag'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'all'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Alla gånger'),
              ),
            ],
          ),
        );
        if (choice == 'single') {
          await NotificationService.cancelActivityInstance(doc.id, listDay);
          await doc.reference.update({
            'recurrence.exceptions':
                FieldValue.arrayUnion([dateKey(listDay)]),
          });
        } else if (choice == 'all') {
          await NotificationService.cancelActivityReminders(doc.id, d);
          await doc.reference.delete();
        }
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ta bort aktivitet?'),
          content: const Text('Den tas bort från planeringen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Ta bort'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await NotificationService.cancel(doc.id);
        await doc.reference.delete();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? '';
    final dt = parseDateTime(d);
    final startClock = (d['time'] as String? ?? '').trim();
    final endClock = (d['endTime'] as String? ?? '').trim();
    String timeStr;
    if (startClock.isNotEmpty && endClock.isNotEmpty) {
      timeStr = '$startClock – $endClock';
    } else if (dt != null && (dt.hour != 0 || dt.minute != 0)) {
      final startFmt = DateFormat('HH:mm').format(dt);
      timeStr =
          endClock.isNotEmpty ? '$startFmt – $endClock' : startFmt;
    } else if (startClock.isNotEmpty) {
      timeStr =
          endClock.isNotEmpty ? '$startClock – $endClock' : startClock;
    } else {
      timeStr = '';
    }
    final isPending = d['isPending'] == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: AppTheme.cardDecoration().copyWith(
        border: Border(left: BorderSide(color: dayColor, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ActivityDetailSheet(docSnapshot: doc),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      PlannerEventLeading(
                        data: d,
                        accentColor: dayColor,
                        emojiSize: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                            if (timeStr.isNotEmpty)
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: dayColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (d['recurrence'] != null)
                              Text(
                                '🔁 ${recurrenceLabel(d)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600),
                              ),
                            if (isPending)
                              const Text(
                                '⏳ Väntar på godkännande',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.orange),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            padding: const EdgeInsets.only(right: 4),
            icon: Icon(Icons.more_vert_rounded,
                color: Colors.grey.shade500, size: 22),
            onSelected: (v) => _handleMenu(context, v),
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'edit', child: Text('Redigera')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Ta bort',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoreRow extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;
  final List<UserModel> familyMembers;
  final String familyId;
  final bool allowDrag;

  const _ChoreRow({
    required this.doc,
    required this.dayColor,
    required this.familyMembers,
    required this.familyId,
    this.allowDrag = true,
  });

  @override
  State<_ChoreRow> createState() => _ChoreRowState();
}

class _ChoreRowState extends State<_ChoreRow> {
  bool _saving = false;

  Future<void> _handleMenu(String value) async {
    if (value == 'edit') {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AddChoreSheet(
          familyMembers: widget.familyMembers,
          familyId: widget.familyId.isEmpty ? null : widget.familyId,
          choreToEdit: widget.doc,
        ),
      );
    } else if (value == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ta bort syssla?'),
          content: const Text('Sysslan tas bort för hela familjen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Ta bort'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await NotificationService.cancel(widget.doc.id);
        await widget.doc.reference.delete();
      }
    }
  }

  Future<void> _toggleDone(bool current) async {
    setState(() => _saving = true);
    try {
      await widget.doc.reference.update({'isDone': !current});
      if (!current) await NotificationService.cancel(widget.doc.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';
    final who = d['who'] as String? ?? '';
    final isDone = d['isDone'] == true;
    final points = (d['points'] as int?) ?? 10;

    final card = AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isDone ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: AppTheme.cardDecoration(radius: 16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(pik, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (who.isNotEmpty)
                      Text(
                        who,
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
              const SizedBox(width: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+$points ⭐',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _saving ? null : () => _toggleDone(isDone),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDone ? widget.dayColor : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isDone ? widget.dayColor : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (isDone
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null),
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert_rounded,
                    color: Colors.grey.shade500, size: 22),
                onSelected: _handleMenu,
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'edit', child: Text('Redigera')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Ta bort',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.allowDrag) return card;

    final maxW = MediaQuery.sizeOf(context).width * 0.82;
    return LongPressDraggable<DocumentReference>(
      data: widget.doc.reference,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: AppTheme.cardDecoration(radius: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pik, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _AddTypeSheet extends StatelessWidget {
  final Color dayColor;
  final bool showPlanningExtras;
  final VoidCallback? onCalendarImportTap;
  final VoidCallback onActivityTap;
  final VoidCallback onChoreTap;
  final VoidCallback onQuickChoreTap;
  final VoidCallback onWorkShiftTap;

  const _AddTypeSheet({
    required this.dayColor,
    this.showPlanningExtras = false,
    this.onCalendarImportTap,
    required this.onActivityTap,
    required this.onChoreTap,
    required this.onQuickChoreTap,
    required this.onWorkShiftTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Vad vill du lägga till?',
                  style: AppTheme.sectionTitleStyle),
              const SizedBox(height: 16),
              _TypeOption(
                emoji: '📅',
                title: 'Aktivitet',
                subtitle: 'Planera något på ett specifikt datum',
                color: dayColor,
                onTap: onActivityTap,
              ),
              const SizedBox(height: 10),
              _TypeOption(
                emoji: '🧹',
                title: 'Syssla',
                subtitle: 'Piktogram, delsteg och poäng',
                color: Colors.grey.shade700,
                onTap: onChoreTap,
              ),
              const SizedBox(height: 10),
              _TypeOption(
                emoji: '⚡',
                title: 'Snabb syssla',
                subtitle: 'Titel och ev. ansvarig — för vald dag',
                color: dayColor,
                onTap: onQuickChoreTap,
              ),
              const SizedBox(height: 10),
              _TypeOption(
                emoji: '💼',
                title: 'Arbetspass',
                subtitle: 'Vem, tid och datum — syns i planeringen',
                color: const Color(0xFF2196F3),
                onTap: onWorkShiftTap,
              ),
              if (showPlanningExtras) ...[
                const SizedBox(height: 10),
                _TypeOption(
                  emoji: '📆',
                  title: 'Kalenderimport',
                  subtitle: 'Importera ICS till familjen',
                  color: dayColor,
                  onTap: onCalendarImportTap ?? () {},
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TypeOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
