import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/permissions.dart';
import '../utils/person_match.dart';
import '../widgets/shimmer_list_placeholder.dart';
import 'agenda_page.dart';
import 'chore_stats_page.dart';
import 'chores_page.dart';

/// Syssla utan `dueDate` visas i dag-sektionen varje dag; med datum bara den dagen.
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

/// Fas 6 Sysslor-flik — dagens + öppna sysslor, mallar, läsningstimer.
class SysslorPage extends StatefulWidget {
  const SysslorPage({super.key});

  @override
  State<SysslorPage> createState() => _SysslorPageState();
}

class _SysslorPageState extends State<SysslorPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _filterPerson;
  String? _filterPersonUid;
  bool _doneExpanded = false;

  bool _readingActive = false;
  int _readingSeconds = 0;
  Timer? _readingTimer;

  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  void _onChoreCompleted() => _confettiController.play();

  void _toggleReading() {
    if (_readingActive) {
      final minutes = _readingSeconds ~/ 60;
      if (minutes > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Du läste $minutes minuter! 📚'),
          backgroundColor: const Color(0xFF6BAE75),
        ));
      }
      setState(() {
        _readingActive = false;
        _readingSeconds = 0;
      });
      _readingTimer?.cancel();
    } else {
      setState(() {
        _readingActive = true;
        _readingSeconds = 0;
      });
      _readingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _readingSeconds++);
      });
    }
  }

  String get _readingTimeStr {
    final m = _readingSeconds ~/ 60;
    final s = _readingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool _matchesPerson(
    Map<String, dynamic> d,
    UserModel? user,
    bool isFocus,
  ) {
    if (_filterPerson != null) {
      return assignedToPerson(
        d,
        uid: _filterPersonUid ?? '',
        name: _filterPerson!,
      );
    }
    if (isFocus && user != null) {
      return assignedToPerson(d, uid: user.uid, name: user.name);
    }
    return true;
  }

  ({List<QueryDocumentSnapshot> today, List<QueryDocumentSnapshot> open,
      List<QueryDocumentSnapshot> done}) _splitChores(
    List<QueryDocumentSnapshot> all,
    UserModel? user,
    bool isFocus,
  ) {
    final today = DateTime.now();
    final todayList = <QueryDocumentSnapshot>[];
    final openList = <QueryDocumentSnapshot>[];
    final doneList = <QueryDocumentSnapshot>[];

    for (final doc in all) {
      final d = doc.data() as Map<String, dynamic>;
      if (!_matchesPerson(d, user, isFocus)) continue;

      if (d['isDone'] == true) {
        doneList.add(doc);
      } else if (_choreVisibleOnDay(d, today)) {
        todayList.add(doc);
      } else {
        openList.add(doc);
      }
    }

    int byTitle(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
      final ta = ((a.data() as Map)['chore'] as String? ??
              (a.data() as Map)['title'] as String? ??
              '')
          .toLowerCase();
      final tb = ((b.data() as Map)['chore'] as String? ??
              (b.data() as Map)['title'] as String? ??
              '')
          .toLowerCase();
      return ta.compareTo(tb);
    }

    todayList.sort(byTitle);
    openList.sort(byTitle);
    doneList.sort(byTitle);
    return (today: todayList, open: openList, done: doneList);
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
    final today = DateTime.now();
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
      'dueDate': dateKey(today),
      'substeps': <Map<String, dynamic>>[],
      if (FirebaseAuth.instance.currentUser != null)
        'createdByUid': FirebaseAuth.instance.currentUser!.uid,
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
            final ta = (a.data() as Map)['title'] as String? ?? '';
            final tb = (b.data() as Map)['title'] as String? ?? '';
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
                                Text(pik,
                                    style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 120),
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

  void _showAddSheet(FamilyProvider provider, Color dayColor) {
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
    final today = DateTime.now();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => wrapBottomSheet(
        ctx,
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Lägg till syssla', style: AppTheme.sectionTitleStyle),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: dayColor.withValues(alpha: 0.15),
                  child: Icon(Icons.flash_on_rounded, color: dayColor),
                ),
                title: const Text('Snabb syssla',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Titel + vem — klar på några sekunder'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => QuickChoreSheet(
                      familyMembers: provider.familyMembers,
                      familyId: provider.currentUser?.familyId,
                      selectedDay: today,
                    ),
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: dayColor.withValues(alpha: 0.15),
                  child: Icon(Icons.checklist_rounded, color: dayColor),
                ),
                title: const Text('Ny syssla',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Piktogram, delsteg, vikt m.m.'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AddChoreSheet(
                      familyMembers: provider.familyMembers,
                      familyId: provider.currentUser?.familyId ?? '',
                      preselectedDay: today,
                      startOnForm: true,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color dayColor) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Sysslor',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Statistik',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChoreStatsPage(),
                ),
              );
            },
            icon: Icon(Icons.bar_chart_rounded, color: textColor),
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

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(title, style: AppTheme.sectionLabelStyle),
    );
  }

  Widget _choreRow(
    QueryDocumentSnapshot doc,
    Color dayColor,
    List<UserModel> members,
    String familyId,
    UserModel? user,
  ) {
    return RepaintBoundary(
      child: AgendaChoreRow(
        doc: doc,
        dayColor: dayColor,
        familyMembers: members,
        familyId: familyId,
        currentUser: user,
        allowDrag: canEditDoc(user, doc.data() as Map<String, dynamic>),
        onComplete: _onChoreCompleted,
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(22),
      decoration: AppTheme.cardDecoration(),
      child: Center(
        child: Text(message, style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }

  List<Widget> _buildFocusSlivers({
    required List<QueryDocumentSnapshot> today,
    required Color dayColor,
    required List<UserModel> members,
    required String familyId,
    required UserModel? user,
  }) {
    final name = user?.name.split(' ').first ?? '';
    final total = today.length;
    final done =
        today.where((d) => (d.data() as Map)['isDone'] == true).length;

    return [
      SliverToBoxAdapter(child: _buildHeader(dayColor)),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mina sysslor', style: AppTheme.sectionTitleStyle),
              Text(
                '$name — $done av $total klara idag',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
      if (today.isEmpty)
        SliverToBoxAdapter(
          child: _buildEmptyCard('Inga sysslor idag — bra jobbat! 🎉'),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _choreRow(today[i], dayColor, members, familyId, user),
            childCount: today.length,
          ),
        ),
      const SliverToBoxAdapter(
        child: SizedBox(height: WindowSize.navScrollPadding),
      ),
    ];
  }

  List<Widget> _buildParentSlivers({
    required List<QueryDocumentSnapshot> today,
    required List<QueryDocumentSnapshot> open,
    required List<QueryDocumentSnapshot> done,
    required Color dayColor,
    required List<UserModel> members,
    required String familyId,
    required UserModel? user,
    required bool isParent,
  }) {
    final slivers = <Widget>[
      SliverToBoxAdapter(child: _buildHeader(dayColor)),
      SliverToBoxAdapter(child: _buildPersonFilter(members, dayColor)),
      SliverToBoxAdapter(
        child: _buildChoreTemplatesStrip(
          familyId.isEmpty ? null : familyId,
          members,
          isParent,
          dayColor,
        ),
      ),
      SliverToBoxAdapter(child: _sectionLabel('IDAG')),
    ];

    if (today.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildEmptyCard('Inga sysslor för idag.'),
        ),
      );
    } else {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _choreRow(today[i], dayColor, members, familyId, user),
            childCount: today.length,
          ),
        ),
      );
    }

    slivers.add(SliverToBoxAdapter(child: _sectionLabel('ÖPPNA')));

    if (open.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildEmptyCard('Inga öppna sysslor med annat datum.'),
        ),
      );
    } else {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _choreRow(open[i], dayColor, members, familyId, user),
            childCount: open.length,
          ),
        ),
      );
    }

    if (done.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _doneExpanded = !_doneExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Row(
                  children: [
                    Text('KLARA', style: AppTheme.sectionLabelStyle),
                    const SizedBox(width: 8),
                    Text(
                      '${done.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _doneExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (_doneExpanded) {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) =>
                  _choreRow(done[i], dayColor, members, familyId, user),
              childCount: done.length,
            ),
          ),
        );
      }
    }

    slivers.add(
      const SliverToBoxAdapter(
        child: SizedBox(height: WindowSize.navScrollPadding),
      ),
    );
    return slivers;
  }

  Widget _buildFabColumn(Color dayColor, FamilyProvider fp, bool isFocus) {
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    return Positioned(
      right: 16,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isFocus) ...[
            if (_readingActive)
              FloatingActionButton.extended(
                heroTag: 'sysslor_reading_stop',
                onPressed: _toggleReading,
                backgroundColor: const Color(0xFF6BAE75),
                foregroundColor: Colors.white,
                icon: const Icon(Icons.stop),
                label: Text('📖 $_readingTimeStr'),
              )
            else
              FloatingActionButton.extended(
                heroTag: 'sysslor_reading_start',
                onPressed: _toggleReading,
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.getTextColor(),
                icon: const Text('📖', style: TextStyle(fontSize: 18)),
                label: const Text(
                  'Jag läser nu',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'sysslor_add',
              onPressed: () => _showAddSheet(fp, dayColor),
              backgroundColor: dayColor,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded),
            ),
          ] else
            FloatingActionButton.extended(
              heroTag: 'sysslor_reading_focus',
              onPressed: _toggleReading,
              backgroundColor: _readingActive
                  ? const Color(0xFF6BAE75)
                  : Colors.white,
              foregroundColor:
                  _readingActive ? Colors.white : AppTheme.getTextColor(),
              icon: Text(
                _readingActive ? '⏱️' : '📖',
                style: const TextStyle(fontSize: 20),
              ),
              label: Text(
                _readingActive ? 'Stop $_readingTimeStr' : 'Jag läser nu',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    context.select((FamilyProvider p) => (
          p.isLoading,
          p.currentUser,
          p.chores,
          p.familyMembers,
        ));
    final fp = context.read<FamilyProvider>();
    final user = fp.currentUser;
    final members = fp.familyMembers;
    final isFocus = user?.isFocusMode ?? false;
    final dayColor = AppTheme.getDayAccentColor();
    final familyId = user?.familyId ?? '';

    final split = _splitChores(fp.chores, user, isFocus);

    return Container(
      decoration: AppTheme.getBackground(),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (fp.isLoading)
            const ShimmerListPlaceholder()
          else
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: isFocus
                  ? _buildFocusSlivers(
                      today: split.today,
                      dayColor: dayColor,
                      members: members,
                      familyId: familyId,
                      user: user,
                    )
                  : _buildParentSlivers(
                      today: split.today,
                      open: split.open,
                      done: split.done,
                      dayColor: dayColor,
                      members: members,
                      familyId: familyId,
                      user: user,
                      isParent: user?.isParent ?? false,
                    ),
            ),
          if (!fp.isLoading) _buildFabColumn(dayColor, fp, isFocus),
          ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.1,
            numberOfParticles: 20,
            colors: [dayColor, Colors.amber, Colors.pink, Colors.purple],
          ),
        ],
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
  Widget build(BuildContext context) {
    return GestureDetector(
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
}
