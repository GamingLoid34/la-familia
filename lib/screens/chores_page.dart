import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../app_theme.dart';
import '../data/piktogram.dart';
import '../models/user_model.dart';
import '../services/family_service.dart';
import '../services/user_service.dart';
import '../widgets/shimmer_list_placeholder.dart';

class ChoresPage extends StatefulWidget {
  const ChoresPage({super.key});
  @override
  State<ChoresPage> createState() => _ChoresPageState();
}

class _ChoresPageState extends State<ChoresPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  UserModel? _currentUser;
  List<UserModel> _familyMembers = [];
  String? _filterPerson;
  Stream<QuerySnapshot>? _choresStream;

  // Reading timer
  bool _readingActive = false;
  int _readingSeconds = 0;
  Timer? _readingTimer;

  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _loadUser();
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await FamilyService.getCurrentUserModel();
    final members = <UserModel>[];
    if (user?.familyId != null) {
      final snap = await FirebaseFirestore.instance
          .collection('users').where('familyId', isEqualTo: user!.familyId).get();
      for (final d in snap.docs) members.add(UserModel.fromMap(d.id, d.data()));
    }
    if (mounted) {
      setState(() {
        _currentUser = user;
        _familyMembers = members;
        // Query without familyId filter so existing chores are always visible.
        // familyId is saved on every new chore for future filtering.
        _choresStream =
            FirebaseFirestore.instance.collection('chores').snapshots();
      });
    }
  }

  void _toggleReading() {
    if (_readingActive) {
      // Stop — award points
      final minutes = _readingSeconds ~/ 60;
      final points = (minutes / 5).floor();
      if (points > 0 && _currentUser != null) {
        UserService.addPoints(_currentUser!.uid, points);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Du läste $minutes minuter! +$points poäng! 📚'),
          backgroundColor: const Color(0xFF6BAE75),
        ));
      }
      setState(() { _readingActive = false; _readingSeconds = 0; });
      _readingTimer?.cancel();
    } else {
      setState(() { _readingActive = true; _readingSeconds = 0; });
      _readingTimer = Timer.periodic(const Duration(seconds: 1),
          (_) { if (mounted) setState(() => _readingSeconds++); });
    }
  }

  void _onChoreCompleted() {
    _confettiController.play();
    if (_currentUser != null) UserService.addPoints(_currentUser!.uid, 10);
  }

  String get _readingTimeStr {
    final m = _readingSeconds ~/ 60;
    final s = _readingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isFocus = _currentUser?.isFocusMode ?? false;
    final dayColor = AppTheme.getDayAccentColor();

    return Container(
      decoration: AppTheme.getBackground(),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (_choresStream == null)
            _buildParentView([], [], dayColor)
          else
            StreamBuilder<QuerySnapshot>(
              stream: _choresStream,
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Fel: ${snap.error}',
                          style: const TextStyle(color: Colors.red)),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const ShimmerListPlaceholder();
                }
                final docs = snap.data?.docs ?? [];
                final filtered = _filterChores(docs);
                if (isFocus) return _buildFocusView(filtered, dayColor);
                return _buildParentView(docs, filtered, dayColor);
              },
            ),
          // FABs — placerade ovanför BottomNavigationBar
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isFocus) ...[
                  if (_readingActive)
                    FloatingActionButton.extended(
                      heroTag: 'reading',
                      onPressed: _toggleReading,
                      backgroundColor: const Color(0xFF6BAE75),
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.stop),
                      label: Text('📖 $_readingTimeStr'),
                    )
                  else
                    FloatingActionButton.extended(
                      heroTag: 'reading_start',
                      onPressed: _toggleReading,
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.getTextColor(),
                      icon: const Text('📖', style: TextStyle(fontSize: 18)),
                      label: const Text('Jag läser nu',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 12),
                  FloatingActionButton(
                    heroTag: 'add_chore',
                    onPressed: _showAddChoreSheet,
                    backgroundColor: dayColor,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.add_rounded),
                  ),
                ] else
                  FloatingActionButton.extended(
                    heroTag: 'reading_focus',
                    onPressed: _toggleReading,
                    backgroundColor: _readingActive
                        ? const Color(0xFF6BAE75)
                        : Colors.white,
                    foregroundColor: _readingActive
                        ? Colors.white
                        : AppTheme.getTextColor(),
                    icon: Text(_readingActive ? '⏱️' : '📖',
                        style: const TextStyle(fontSize: 20)),
                    label: Text(
                        _readingActive
                            ? 'Stop $_readingTimeStr'
                            : 'Jag läser nu',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          // Confetti
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

  List<QueryDocumentSnapshot> _filterChores(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (_filterPerson != null) return d['who'] == _filterPerson;
      return true;
    }).toList()
      ..sort((a, b) {
        final da = (a.data() as Map)['isDone'] == true ? 1 : 0;
        final db = (b.data() as Map)['isDone'] == true ? 1 : 0;
        return da.compareTo(db);
      });
  }

  // ─── PARENT VIEW ─────────────────────────────────────────────────────────
  Widget _buildParentView(List<QueryDocumentSnapshot> all,
      List<QueryDocumentSnapshot> filtered, Color dayColor) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
          SliverToBoxAdapter(child: _buildHeader(dayColor)),
          SliverToBoxAdapter(child: _buildLeaderboard(all, dayColor)),
          SliverToBoxAdapter(child: _buildPersonFilter(dayColor)),
          if (filtered.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(dayColor))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _ChoreCard(
                  doc: filtered[i], 
                  dayColor: dayColor,
                  currentUser: _currentUser,
                  familyMembers: _familyMembers,
                  onComplete: _onChoreCompleted,
                ),
                childCount: filtered.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      );
  }

  // ─── FOCUS VIEW ──────────────────────────────────────────────────────────
  Widget _buildFocusView(List<QueryDocumentSnapshot> filtered, Color dayColor) {
    final name = _currentUser?.name.split(' ').first ?? '';
    final total = filtered.length;
    final done = filtered.where((d) => (d.data() as Map)['isDone'] == true).length;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
          SliverToBoxAdapter(child: _buildHeader(dayColor)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mina sysslor', style: AppTheme.sectionTitleStyle),
                Text('$name — $done av $total klara idag',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              ]),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _FocusChoreCard(doc: filtered[i], dayColor: dayColor, onComplete: _onChoreCompleted),
              childCount: filtered.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      );
  }

  Widget _buildHeader(Color dayColor) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: BoxDecoration(
        color: dayColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
      child: Text('Sysslor', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
    );
  }

  Widget _buildLeaderboard(List<QueryDocumentSnapshot> all, Color dayColor) {
    if (_familyMembers.isEmpty) return const SizedBox.shrink();
    final weekStr = 'Vecka ${_weekNumber()}';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Poängliga', style: AppTheme.cardTitleStyle),
          Text(weekStr, style: AppTheme.captionStyle),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _familyMembers.length,
            itemBuilder: (_, i) {
              final m = _familyMembers[i];
              Color mc; try { mc = Color(m.colorValue as int); } catch (_) { mc = dayColor; }
              return Container(
                width: 72, margin: const EdgeInsets.only(right: 12),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircleAvatar(radius: 22, backgroundColor: mc,
                    child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 4),
                  Text(m.name.split(' ').first, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text('${m.weeklyPoints} ⭐', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildPersonFilter(Color dayColor) {
    if (_familyMembers.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _PlannerPill(label: 'Alla', selected: _filterPerson == null, color: dayColor,
              onTap: () => setState(() => _filterPerson = null)),
          ..._familyMembers.map((m) {
            Color mc; try { mc = Color(m.colorValue as int); } catch (_) { mc = dayColor; }
            return _PlannerPill(label: m.name.split(' ').first, selected: _filterPerson == m.name,
                color: mc, onTap: () => setState(() => _filterPerson = _filterPerson == m.name ? null : m.name));
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color dayColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          const Text('🧹', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text('Inga sysslor ännu', style: AppTheme.sectionTitleStyle, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Lägg till din första syssla! 🧹',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _showAddChoreSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: dayColor, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Lägg till syssla', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddChoreSheet() {
    if (_currentUser == null) {
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
      backgroundColor: Colors.transparent,
      builder: (_) => _AddChoreSheet(
        familyMembers: _familyMembers,
        familyId: _currentUser?.familyId ?? '',
      ),
    );
  }

  int _weekNumber() {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, 1, 1);
    return ((now.difference(firstDay).inDays + firstDay.weekday - 1) / 7).ceil();
  }
}

// ─── PILL ────────────────────────────────────────────────────────────────────
class _PlannerPill extends StatelessWidget {
  final String label; final bool selected; final Color color; final VoidCallback onTap;
  const _PlannerPill({required this.label, required this.selected, required this.color, required this.onTap});
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
        border: Border.all(color: selected ? color : Colors.grey.shade300)),
      child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppTheme.getTextColor(),
          fontWeight: FontWeight.w600, fontSize: 13)),
    ),
  );
}

// ─── CHORE CARD ──────────────────────────────────────────────────────────────
class _ChoreCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;
  final UserModel? currentUser;
  final List<UserModel> familyMembers;
  final VoidCallback onComplete;
  const _ChoreCard({
    required this.doc, 
    required this.dayColor, 
    this.currentUser, 
    required this.familyMembers,
    required this.onComplete
  });
  @override
  State<_ChoreCard> createState() => _ChoreCardState();
}

class _ChoreCardState extends State<_ChoreCard> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.elasticOut)).animate(_anim);
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  Future<void> _toggle(bool current) async {
    _anim.forward().then((_) => _anim.reverse());
    await widget.doc.reference.update({'isDone': !current});
    if (!current) widget.onComplete();
  }

  void _confirmDelete(BuildContext context, QueryDocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort syssla?'),
        content: const Text('Är du säker på att du vill ta bort denna syssla? Den försvinner för alla i familjen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Avbryt')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, 
              foregroundColor: Colors.white
            ),
            onPressed: () {
              doc.reference.delete();
              Navigator.pop(ctx);
            },
            child: const Text('Ta bort'),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';
    final who = d['who'] as String? ?? '';
    final isDone = d['isDone'] == true;
    final points = (d['points'] as int?) ?? 10;
    final substeps = (d['substeps'] as List? ?? []).cast<Map<String, dynamic>>();

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isDone ? 0.5 : 1.0,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          decoration: AppTheme.cardDecoration(radius: 16),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Text(pik, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                      decoration: isDone ? TextDecoration.lineThrough : null)),
                  if (who.isNotEmpty) Text(who, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Text('+$points ⭐', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
                ),
                // Tre prickar för att Redigera eller Ta bort
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
                  padding: EdgeInsets.zero,
                  onSelected: (val) {
                    if (val == 'edit') {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _AddChoreSheet(
                          familyMembers: widget.familyMembers,
                          familyId: widget.currentUser?.familyId,
                          choreToEdit: widget.doc,
                        ),
                      );
                    } else if (val == 'delete') {
                      _confirmDelete(context, widget.doc);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('Redigera')),
                    const PopupMenuItem(value: 'delete', child: Text('Ta bort', style: TextStyle(color: Colors.red))),
                  ],
                ),
                ScaleTransition(
                  scale: _scale,
                  child: GestureDetector(
                    onTap: () => _toggle(isDone),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: isDone ? widget.dayColor : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDone ? widget.dayColor : Colors.grey.shade400, width: 2)),
                      child: isDone ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
                ),
              ]),
            ),
            if (_expanded && substeps.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))),
                child: Column(children: substeps.map((sub) {
                  final subDone = sub['isDone'] == true;
                  return ListTile(
                    dense: true,
                    leading: Icon(subDone ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: subDone ? widget.dayColor : Colors.grey.shade400, size: 20),
                    title: Text(sub['title'] as String? ?? '',
                        style: TextStyle(decoration: subDone ? TextDecoration.lineThrough : null)),
                  );
                }).toList()),
              ),
          ]),
        ),
      ),
    );
  }
}

// ─── FOCUS CHORE CARD ────────────────────────────────────────────────────────
class _FocusChoreCard extends StatelessWidget {
  final QueryDocumentSnapshot doc; final Color dayColor; final VoidCallback onComplete;
  const _FocusChoreCard({required this.doc, required this.dayColor, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';
    final isDone = d['isDone'] == true;
    final points = (d['points'] as int?) ?? 10;

    return GestureDetector(
      onTap: () async {
        await doc.reference.update({'isDone': !isDone});
        if (!isDone) onComplete();
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isDone ? 0.5 : 1.0,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.cardDecoration(),
          child: Row(children: [
            Text(pik, style: const TextStyle(fontSize: 52)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  decoration: isDone ? TextDecoration.lineThrough : null)),
              Text('+$points ⭐', style: const TextStyle(fontSize: 14, color: Colors.amber, fontWeight: FontWeight.bold)),
            ])),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: isDone ? dayColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: isDone ? dayColor : Colors.grey.shade400, width: 2.5)),
              child: isDone ? const Icon(Icons.check, color: Colors.white, size: 22) : null,
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── ADD CHORE SHEET ─────────────────────────────────────────────────────────
class _AddChoreSheet extends StatefulWidget {
  final List<UserModel> familyMembers;
  final String? familyId;
  final QueryDocumentSnapshot? choreToEdit;
  const _AddChoreSheet({required this.familyMembers, this.familyId, this.choreToEdit});
  @override
  State<_AddChoreSheet> createState() => _AddChoreSheetState();
}

class _AddChoreSheetState extends State<_AddChoreSheet> {
  String _pik = '✅'; String _cat = 'Alla'; String _q = '';
  int _step = 0;
  final _title = TextEditingController();
  String? _assignTo;
  int _points = 10;
  final List<String> _substeps = [];
  final _subCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Fyll i formuläret automatiskt om vi redigerar en existerande syssla
    if (widget.choreToEdit != null) {
      final d = widget.choreToEdit!.data() as Map<String, dynamic>;
      _title.text = d['chore'] as String? ?? d['title'] as String? ?? '';
      _pik = d['piktogram'] as String? ?? '✅';
      _assignTo = d['who'] as String?;
      if (_assignTo != null && _assignTo!.isEmpty) _assignTo = null;
      _points = (d['points'] as int?) ?? 10;
      final subs = (d['substeps'] as List? ?? []).cast<Map<String, dynamic>>();
      _substeps.addAll(subs.map((s) => s['title'] as String? ?? ''));
      _step = 1; // Hoppa direkt till det sista formuläret när man redigerar
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final firstDay = DateTime(now.year, 1, 1);
      final weekNum = ((now.difference(firstDay).inDays + firstDay.weekday - 1) / 7).ceil();
      final weekOf = '${now.year}-W$weekNum';
      
      String whoColor = '';
      if (_assignTo != null) {
        final member = widget.familyMembers.where((m) => m.name == _assignTo).isNotEmpty
            ? widget.familyMembers.firstWhere((m) => m.name == _assignTo)
            : null;
        if (member != null) whoColor = member.color;
      }

      if (widget.choreToEdit != null) {
        // Uppdatera existerande syssla
        await widget.choreToEdit!.reference.update({
          'chore': _title.text.trim(),
          'piktogram': _pik,
          'who': _assignTo ?? '',
          'whoColor': whoColor,
          'points': _points,
          'substeps': _substeps.map((s) => {'title': s, 'isDone': false}).toList(),
        });
      } else {
        // Skapa ny syssla
        await FirebaseFirestore.instance.collection('chores').add({
          'chore': _title.text.trim(),
          'piktogram': _pik,
          'who': _assignTo ?? '',
          'whoColor': whoColor,
          'isDone': false,
          'points': _points,
          'isRecurring': false,
          'familyId': widget.familyId ?? '',
          'weekOf': weekOf,
          'substeps': _substeps.map((s) => {'title': s, 'isDone': false}).toList(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.choreToEdit != null ? 'Syssla uppdaterad! ✅' : 'Syssla sparad! ✅'),
            backgroundColor: const Color(0xFF6BAE75),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fel vid sparande: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.only(top: 12),
          child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(
              _step == 0 ? 'Välj piktogram' : (widget.choreToEdit != null ? 'Redigera syssla' : 'Ny syssla'), 
              style: AppTheme.sectionTitleStyle
            )),
            if (_step == 1) TextButton(onPressed: () => setState(() => _step = 0), child: const Text('← Byt')),
          ])),
        Expanded(child: _step == 0 ? _buildPicker(dayColor) : _buildForm(dayColor)),
      ]),
    );
  }

  Widget _buildPicker(Color dayColor) {
    final items = piktogramLibrary.where((p) =>
      (_cat == 'Alla' || p.category == _cat) &&
      (_q.isEmpty || p.label.toLowerCase().contains(_q.toLowerCase()))).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(hintText: 'Sök...', prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true, fillColor: Colors.grey.shade100, contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: piktogramCategories.map((c) => GestureDetector(
          onTap: () => setState(() => _cat = c),
          child: Container(margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _cat == c ? dayColor : Colors.white, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cat == c ? dayColor : Colors.grey.shade300)),
            child: Text(c, style: TextStyle(color: _cat == c ? Colors.white : AppTheme.getTextColor(), fontSize: 13)))
        )).toList())),
      const SizedBox(height: 8),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.9),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final p = items[i]; final sel = p.emoji == _pik;
          return GestureDetector(
            onTap: () { setState(() { _pik = p.emoji; if (_title.text.isEmpty) _title.text = p.label; _step = 1; }); },
            child: AnimatedContainer(duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(color: sel ? dayColor.withValues(alpha: 0.15) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12), border: sel ? Border.all(color: dayColor, width: 2) : null),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.emoji, style: const TextStyle(fontSize: 24)),
                Text(p.label, style: const TextStyle(fontSize: 9), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ])));
        })),
    ]);
  }

  Widget _buildForm(Color dayColor) {
    return SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: GestureDetector(onTap: () => setState(() => _step = 0),
        child: Column(children: [Text(_pik, style: const TextStyle(fontSize: 56)), Text('Byt piktogram', style: TextStyle(fontSize: 12, color: dayColor))]))),
      const SizedBox(height: 16),
      TextField(controller: _title, decoration: InputDecoration(labelText: 'Syssla', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 12),
      Text('Tilldela', style: AppTheme.sectionLabelStyle),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: widget.familyMembers.map((m) {
        Color mc; try { mc = Color(m.colorValue as int); } catch (_) { mc = dayColor; }
        return ChoiceChip(label: Text(m.name.split(' ').first), selected: _assignTo == m.name,
            selectedColor: mc.withValues(alpha: 0.2),
            onSelected: (v) => setState(() => _assignTo = v ? m.name : null));
      }).toList()),
      const SizedBox(height: 16),
      Text('Poäng: $_points ⭐', style: AppTheme.sectionLabelStyle),
      Slider(value: _points.toDouble(), min: 5, max: 50, divisions: 9, activeColor: dayColor,
          onChanged: (v) => setState(() => _points = v.round())),
      const SizedBox(height: 12),
      Text('Delsteg', style: AppTheme.sectionLabelStyle),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _subCtrl,
          decoration: InputDecoration(hintText: 'Lägg till delsteg...', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          onSubmitted: (v) { if (v.trim().isNotEmpty) setState(() { _substeps.add(v.trim()); _subCtrl.clear(); }); })),
        const SizedBox(width: 8),
        IconButton(icon: Icon(Icons.add_circle_rounded, color: dayColor, size: 32),
          onPressed: () { if (_subCtrl.text.trim().isNotEmpty) setState(() { _substeps.add(_subCtrl.text.trim()); _subCtrl.clear(); }); }),
      ]),
      ..._substeps.map((s) => ListTile(dense: true, contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.drag_handle), title: Text(s),
        trailing: IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.red),
          onPressed: () => setState(() => _substeps.remove(s))))),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(backgroundColor: dayColor, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _saving ? const CircularProgressIndicator(color: Colors.white) :
            Text(widget.choreToEdit != null ? 'Uppdatera syssla' : 'Spara syssla', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
      const SizedBox(height: 40),
    ]));
  }
}