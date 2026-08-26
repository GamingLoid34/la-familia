import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';

/// Föräldravy för morgon-/kvällsrutiner (ROADMAP Etapp 7.3).
/// Rutiner är medvetet enkla: ägare, morgon/kväll och en lista steg
/// med piktogram. Inga poäng — rutiner är trygghet, inte uppgifter.
class ManageRoutinesPage extends StatelessWidget {
  const ManageRoutinesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    final routines = provider.routines.toList()
      ..sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;
        final byOwner = (da['ownerName'] as String? ?? '')
            .compareTo(db['ownerName'] as String? ?? '');
        if (byOwner != 0) return byOwner;
        return (da['type'] as String? ?? '')
            .compareTo(db['type'] as String? ?? '');
      });

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: AppTheme.getBackground(),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    decoration: AppTheme.headerDecoration(),
                    padding: AppTheme.paddingBelowStatusBar(context),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child:
                            Icon(Icons.arrow_back_ios_rounded, color: textColor),
                      ),
                      const SizedBox(width: 12),
                      Text('Rutiner',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: textColor)),
                    ]),
                  ),
                ),
                if (routines.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(children: [
                        const Text('🌅', style: TextStyle(fontSize: 52)),
                        const SizedBox(height: 16),
                        Text('Inga rutiner ännu',
                            style: AppTheme.sectionTitleStyle),
                        const SizedBox(height: 8),
                        Text(
                          'Tryck + för att skapa en morgon- eller '
                          'kvällsrutin för en familjemedlem.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 13),
                        ),
                      ]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _RoutineListTile(doc: routines[i]),
                        childCount: routines.length,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.getDayAccentColor(),
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(context, provider, null),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

void _openEditor(
  BuildContext context,
  FamilyProvider provider,
  QueryDocumentSnapshot? doc,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoutineEditorSheet(
      familyMembers: provider.familyMembers,
      familyId: provider.currentUser?.familyId ?? '',
      routineToEdit: doc,
    ),
  );
}

class _RoutineListTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _RoutineListTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final isMorning = (d['type'] as String? ?? 'morning') == 'morning';
    final steps = (d['steps'] as List? ?? []);
    final provider = context.read<FamilyProvider>();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Text(isMorning ? '🌅' : '🌙',
            style: const TextStyle(fontSize: 26)),
        title: Text(
          '${d['ownerName'] ?? ''} — ${isMorning ? 'morgon' : 'kväll'}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text('${steps.length} steg',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              color: Colors.grey.shade400, size: 20),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Ta bort rutin?'),
                content: Text(
                    'Rutinen för ${d['ownerName'] ?? ''} tas bort.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Avbryt')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Ta bort')),
                ],
              ),
            );
            if (ok == true) await doc.reference.delete();
          },
        ),
        onTap: () => _openEditor(context, provider, doc),
      ),
    );
  }
}

class _RoutineEditorSheet extends StatefulWidget {
  final List<UserModel> familyMembers;
  final String familyId;
  final QueryDocumentSnapshot? routineToEdit;

  const _RoutineEditorSheet({
    required this.familyMembers,
    required this.familyId,
    this.routineToEdit,
  });

  @override
  State<_RoutineEditorSheet> createState() => _RoutineEditorSheetState();
}

class _RoutineEditorSheetState extends State<_RoutineEditorSheet> {
  String? _ownerUid;
  String _type = 'morning';
  final List<Map<String, dynamic>> _steps = [];
  final _stepCtrl = TextEditingController();
  String _stepEmoji = '✅';
  bool _saving = false;

  // Vanliga rutin-piktogram — snabbval istället för fritextletande.
  static const _emojis = [
    '🪥', '🚿', '🧼', '👕', '🎒', '🍞', '🥣', '💊',
    '📚', '🧸', '😴', '🌙', '🧦', '🧴', '🚽', '✅',
  ];

  @override
  void initState() {
    super.initState();
    final doc = widget.routineToEdit;
    if (doc != null) {
      final d = doc.data() as Map<String, dynamic>;
      _ownerUid = d['ownerUid'] as String?;
      _type = d['type'] as String? ?? 'morning';
      _steps.addAll(
          (d['steps'] as List? ?? []).cast<Map<String, dynamic>>());
    } else if (widget.familyMembers.isNotEmpty) {
      _ownerUid = widget.familyMembers.first.uid;
    }
  }

  @override
  void dispose() {
    _stepCtrl.dispose();
    super.dispose();
  }

  void _addStep() {
    final t = _stepCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _steps.add({'title': t, 'piktogram': _stepEmoji});
      _stepCtrl.clear();
    });
  }

  Future<void> _save() async {
    if (_ownerUid == null || _steps.isEmpty) return;
    setState(() => _saving = true);
    final owner = widget.familyMembers
        .where((m) => m.uid == _ownerUid)
        .toList();
    final data = {
      'familyId': widget.familyId,
      'ownerUid': _ownerUid,
      'ownerName': owner.isNotEmpty ? owner.first.name : '',
      'type': _type,
      'steps': _steps,
    };
    try {
      if (widget.routineToEdit != null) {
        await widget.routineToEdit!.reference.update(data);
      } else {
        await FirebaseFirestore.instance.collection('routines').add({
          ...data,
          'doneDate': '',
          'doneSteps': <int>[],
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e, stack) {
      developer.log('Rutin: spara misslyckades', error: e, stackTrace: stack);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Kunde inte spara: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                  widget.routineToEdit != null
                      ? 'Redigera rutin'
                      : 'Ny rutin',
                  style: AppTheme.sectionTitleStyle),
              const SizedBox(height: 16),
              Text('VEM?', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _ownerUid,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                items: widget.familyMembers
                    .map((m) => DropdownMenuItem(
                        value: m.uid, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setState(() => _ownerUid = v),
              ),
              const SizedBox(height: 16),
              Text('NÄR?', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'morning', label: Text('🌅 Morgon')),
                  ButtonSegment(value: 'evening', label: Text('🌙 Kväll')),
                ],
                selected: {_type},
                onSelectionChanged: (s) =>
                    setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              Text('STEG (i ordning)', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              ..._steps.asMap().entries.map((e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(e.value['piktogram'] as String? ?? '✅',
                        style: const TextStyle(fontSize: 22)),
                    title: Text(e.value['title'] as String? ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Colors.red),
                      onPressed: () =>
                          setState(() => _steps.removeAt(e.key)),
                    ),
                  )),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _emojis
                    .map((em) => GestureDetector(
                          onTap: () => setState(() => _stepEmoji = em),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _stepEmoji == em
                                  ? dayColor.withValues(alpha: 0.2)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: _stepEmoji == em
                                  ? Border.all(color: dayColor)
                                  : null,
                            ),
                            child: Text(em,
                                style: const TextStyle(fontSize: 20)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _stepCtrl,
                    decoration: InputDecoration(
                      hintText: 'T.ex. Borsta tänderna',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _addStep(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle_rounded,
                      color: dayColor, size: 32),
                  onPressed: _addStep,
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed:
                      _saving || _steps.isEmpty || _ownerUid == null
                          ? null
                          : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dayColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Spara rutin',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
