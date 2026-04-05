import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../widgets/activity_detail_sheet.dart';
import 'chores_page.dart';
import 'planner_page.dart';

enum AgendaTab { all, activities, chores }

DateTime? _parseDate(dynamic v) {
  try {
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final p = v.split('-');
      if (p.length >= 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    }
  } catch (_) {}
  return null;
}

DateTime? _parseDateTime(Map<String, dynamic> d) {
  try {
    final base = _parseDate(d['date']);
    if (base == null) return null;
    final timeStr = d['time'] as String? ?? '';
    if (timeStr.isNotEmpty) {
      final tp = timeStr.split(':');
      if (tp.length >= 2) {
        return DateTime(
          base.year,
          base.month,
          base.day,
          int.parse(tp[0]),
          int.parse(tp[1]),
        );
      }
    }
    return base;
  } catch (_) {}
  return null;
}

class AgendaPage extends StatefulWidget {
  final AgendaTab initialTab;
  /// Filtrera på fullständigt namn (samma som i Firestore `persons` / `who`).
  final String? initialPersonFilter;

  const AgendaPage({
    super.key,
    this.initialTab = AgendaTab.all,
    this.initialPersonFilter,
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

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _filterPerson = widget.initialPersonFilter;
  }

  List<QueryDocumentSnapshot> _eventsForDay(
    List<QueryDocumentSnapshot> all,
    DateTime day,
  ) {
    final filtered = all.where((doc) {
      try {
        final d = doc.data() as Map<String, dynamic>;
        final date = _parseDate(d['date']);
        if (date == null) return false;
        if (!isSameDay(date, day)) return false;
        if (_filterPerson != null) {
          final persons = (d['persons'] as List? ?? []).cast<String>();
          return persons.contains(_filterPerson);
        }
        return true;
      } catch (_) {
        return false;
      }
    }).toList();

    filtered.sort((a, b) {
      final dA = _parseDateTime(a.data() as Map<String, dynamic>);
      final dB = _parseDateTime(b.data() as Map<String, dynamic>);
      if (dA == null && dB == null) return 0;
      if (dA == null) return 1;
      if (dB == null) return -1;
      return dA.compareTo(dB);
    });

    return filtered;
  }

  List<QueryDocumentSnapshot> _filterChores(List<QueryDocumentSnapshot> docs) {
    final list = docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (_filterPerson != null) return d['who'] == _filterPerson;
      return true;
    }).toList();

    list.sort((a, b) {
      final da = (a.data() as Map)['isDone'] == true ? 1 : 0;
      final db = (b.data() as Map)['isDone'] == true ? 1 : 0;
      return da.compareTo(db);
    });

    return list;
  }

  Stream<QuerySnapshot>? _plannerStreamFor(String? familyId) {
    if (familyId == null || familyId.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .snapshots();
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

    final chores = _filterChores(provider.chores);

    return Container(
      decoration: AppTheme.getBackground(),
      child: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _plannerStreamFor(user?.familyId),
            builder: (ctx, snap) {
              final allEvents = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
              final eventsForSelected = _eventsForDay(allEvents, _selectedDay);

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(dayColor)),
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
                  ],
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
                    if (eventsForSelected.isEmpty)
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
                          (_, i) => _ActivityRow(
                            doc: eventsForSelected[i],
                            dayColor: dayColor,
                          ),
                          childCount: eventsForSelected.length,
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
                          ),
                          childCount: chores.length,
                        ),
                      ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 140)),
                ],
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: bottomPad + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'agenda_open_planner',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlannerPage()),
                  ),
                  backgroundColor: dayColor,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: const Text('Ny aktivitet',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'agenda_open_chores',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChoresPage()),
                  ),
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.getTextColor(),
                  icon: const Icon(Icons.cleaning_services_rounded),
                  label: const Text('Ny syssla',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color dayColor) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: BoxDecoration(
        color: dayColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
      child: Text(
        'Agenda',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
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

  Widget _buildCalendar(List<QueryDocumentSnapshot> all, Color dayColor) {
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
        availableGestures: AvailableGestures.horizontalSwipe,
        selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
        calendarFormat: CalendarFormat.month,
        availableCalendarFormats: const {CalendarFormat.month: 'Månad'},
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
        calendarStyle: CalendarStyle(
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
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
            onTap: () => setState(() => _filterPerson = null),
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
              onTap: () => setState(() =>
                  _filterPerson = _filterPerson == m.name ? null : m.name),
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
  const _ActivityRow({required this.doc, required this.dayColor});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final pik = d['piktogram'] as String? ?? '📅';
    final title = d['title'] as String? ?? '';
    final dt = _parseDateTime(d);
    final timeStr = dt != null && (dt.hour != 0 || dt.minute != 0)
        ? DateFormat('HH:mm').format(dt)
        : (d['time'] as String? ?? '');
    final isPending = d['isPending'] == true;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ActivityDetailSheet(docSnapshot: doc),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: AppTheme.cardDecoration().copyWith(
          border: Border(left: BorderSide(color: dayColor, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(pik, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 13,
                          color: dayColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (isPending)
                      const Text(
                        '⏳ Väntar på godkännande',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
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
    );
  }
}

class _ChoreRow extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;
  const _ChoreRow({required this.doc, required this.dayColor});

  @override
  State<_ChoreRow> createState() => _ChoreRowState();
}

class _ChoreRowState extends State<_ChoreRow> {
  bool _saving = false;

  Future<void> _toggleDone(bool current) async {
    setState(() => _saving = true);
    try {
      await widget.doc.reference.update({'isDone': !current});
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

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isDone ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: AppTheme.cardDecoration(radius: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              const SizedBox(width: 6),
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
            ],
          ),
        ),
      ),
    );
  }
}

