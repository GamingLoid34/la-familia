import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../data/piktogram.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';

/// Föräldravy för morgon-/kvällsrutiner 2.0 (FAS R1 & FAS R2).
/// Rutiner är trygghet, inte uppgifter: ägare, morgon/kväll och en ordnad lista steg
/// med piktogram, valfria klockslag och AI-baklängesplanering.
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
                        child: Icon(Icons.arrow_back_ios_rounded,
                            color: textColor),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Rutiner',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
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

  // AI-rutinbyggare (FAS R2)
  String? _aiMalTid;
  String? _aiMalEtikett;
  List<String> _aiAntaganden = [];
  String _lastAiPrompt = '';

  // Vanliga rutin-piktogram — snabbval
  static const _emojis = [
    '🪥', '🚿', '🧼', '👕', '🎒', '🍞', '🥣', '💊',
    '📚', '🧸', '😴', '🌙', '🧦', '🧴', '🚽', '✅',
    '🍳', '🥪', '🚶', '🚌', '🚗', '🏃', '🐶', '💧',
  ];

  @override
  void initState() {
    super.initState();
    final doc = widget.routineToEdit;
    if (doc != null) {
      final d = doc.data() as Map<String, dynamic>;
      _ownerUid = d['ownerUid'] as String?;
      _type = d['type'] as String? ?? 'morning';
      final rawSteps =
          (d['steps'] as List? ?? []).cast<Map<String, dynamic>>();
      _steps.addAll(rawSteps.map((s) => Map<String, dynamic>.from(s)));
    } else if (widget.familyMembers.isNotEmpty) {
      _ownerUid = widget.familyMembers.first.uid;
    }
  }

  @override
  void dispose() {
    _stepCtrl.dispose();
    super.dispose();
  }

  void _addStep([int? insertAt]) {
    final t = _stepCtrl.text.trim();
    if (t.isEmpty) return;
    final step = <String, dynamic>{
      'title': t,
      'piktogram': _stepEmoji,
    };
    setState(() {
      if (insertAt != null && insertAt >= 0 && insertAt <= _steps.length) {
        _steps.insert(insertAt, step);
      } else {
        _steps.add(step);
      }
      _stepCtrl.clear();
    });
  }

  void _openStepEditSheet(int index) {
    final current = _steps[index];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StepEditSheet(
        initialTitle: current['title'] as String? ?? '',
        initialEmoji: current['piktogram'] as String? ?? '✅',
        initialTid: current['tid'] as String?,
        onSave: (newTitle, newEmoji, newTid) {
          setState(() {
            _steps[index] = {
              'title': newTitle,
              'piktogram': newEmoji,
              if (newTid != null && newTid.isNotEmpty) 'tid': newTid,
            };
          });
        },
        onDelete: () {
          setState(() {
            _steps.removeAt(index);
          });
        },
      ),
    );
  }

  void _insertStepAfter(int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StepEditSheet(
        initialTitle: '',
        initialEmoji: '✅',
        initialTid: null,
        onSave: (newTitle, newEmoji, newTid) {
          if (newTitle.trim().isEmpty) return;
          setState(() {
            _steps.insert(index + 1, {
              'title': newTitle.trim(),
              'piktogram': newEmoji,
              if (newTid != null && newTid.isNotEmpty) 'tid': newTid,
            });
          });
        },
      ),
    );
  }

  Future<bool> _generateRoutineWithAi(String promptText) async {
    final owner = widget.familyMembers
        .where((m) => m.uid == _ownerUid)
        .toList();
    final ownerName = owner.isNotEmpty ? owner.first.name : '';

    final existingSteps = _steps
        .map((s) => {
              'title': s['title'] ?? '',
              if (s['tid'] != null) 'tid': s['tid'],
            })
        .toList();

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateRoutine',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

      final res = await callable.call<dynamic>({
        'type': _type,
        'ownerName': ownerName,
        'beskrivning': promptText,
        if (existingSteps.isNotEmpty) 'befintligaSteg': existingSteps,
      });

      final rawData = res.data;
      if (rawData == null || rawData is! Map) {
        throw Exception('Ogiltigt svar från AI-tjänsten.');
      }
      final data = Map<String, dynamic>.from(rawData);
      final rawSteps = (data['steps'] as List<dynamic>? ?? const []);

      setState(() {
        _lastAiPrompt = promptText;
        _aiMalTid = data['malTid'] as String?;
        _aiMalEtikett = data['malEtikett'] as String?;
        _aiAntaganden = (data['antaganden'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        _steps.clear();
        for (final item in rawSteps) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final title = m['title'] as String? ?? m['titel'] as String? ?? '';
            final piktogram = m['piktogram'] as String? ?? '✅';
            final tid = m['tid'] as String?;
            if (title.isNotEmpty) {
              _steps.add({
                'title': title,
                'piktogram': piktogram,
                if (tid != null && tid.isNotEmpty) 'tid': tid,
              });
            }
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Rutin förslagen! Justera gärna tider eller steg innan du sparar.'),
            backgroundColor: Color(0xFF6BAE75),
          ),
        );
      }
      return true;
    } catch (e, stack) {
      developer.log('generateRoutine misslyckades',
          error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte nå AI-hjälpen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  void _openAiPromptSheet({String? prefilledText}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiPromptSheet(
        initialText: prefilledText ?? _lastAiPrompt,
        onGenerate: (text) => _generateRoutineWithAi(text),
      ),
    );
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
      'doneDate': '',
      'doneSteps': <int>[],
    };
    try {
      if (widget.routineToEdit != null) {
        await widget.routineToEdit!.reference.update(data);
      } else {
        await FirebaseFirestore.instance.collection('routines').add(data);
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.routineToEdit != null
                        ? 'Redigera rutin'
                        : 'Ny rutin',
                    style: AppTheme.sectionTitleStyle,
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openAiPromptSheet(),
                    icon: const Text('✨', style: TextStyle(fontSize: 16)),
                    label: const Text('Bygg med AI',
                        style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),

              // AI-förslag banner
              if (_aiMalTid != null || _aiAntaganden.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🎯', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${_aiMalEtikett != null && _aiMalEtikett!.isNotEmpty ? _aiMalEtikett : "Måltid"}: $_aiMalTid',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openAiPromptSheet(
                                prefilledText: _lastAiPrompt),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('🔁 Nytt förslag',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      if (_aiAntaganden.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Antagit: ${_aiAntaganden.join(' · ')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('STEG (i ordning — dra för att ändra)',
                      style: AppTheme.sectionLabelStyle),
                  Text('${_steps.length} st',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 8),

              // Reorderable list med draghandtag
              if (_steps.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _steps.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        final item = _steps.removeAt(oldIndex);
                        _steps.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final s = _steps[index];
                      final tid = s['tid'] as String?;
                      return Material(
                        key: ValueKey('step_${index}_${s['title']}'),
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openStepEditSheet(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: Colors.grey.shade400,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  s['piktogram'] as String? ?? '✅',
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s['title'] as String? ?? '',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (tid != null && tid.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '⏰ $tid',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 20,
                                  ),
                                  color: Colors.grey.shade400,
                                  tooltip: 'Infoga steg efter',
                                  onPressed: () => _insertStepAfter(index),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 12),
              Text('LÄGG TILL NYTT STEG SIST',
                  style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
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
                  onPressed: () => _addStep(),
                ),
              ]),
              const SizedBox(height: 14),

              // Notis om nollställning vid sparning
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dagens bockar nollställs när du sparar ändringar.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

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

/// Bottom-sheet för AI-promptering ("✨ Bygg med AI").
class _AiPromptSheet extends StatefulWidget {
  final String initialText;
  final Future<bool> Function(String text) onGenerate;

  const _AiPromptSheet({
    required this.initialText,
    required this.onGenerate,
  });

  @override
  State<_AiPromptSheet> createState() => _AiPromptSheetState();
}

class _AiPromptSheetState extends State<_AiPromptSheet> {
  late final TextEditingController _ctrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() => _loading = true);

    final success = await widget.onGenerate(text);

    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        Navigator.pop(context);
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
                const Text('✨', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text('Bygg rutin med AI', style: AppTheme.sectionTitleStyle),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Beskriv morgonen eller kvällen med egna ord så planerar AI:n tiderna baklänges från din deadline.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              minLines: 3,
              maxLines: 6,
              autofocus: true,
              decoration: InputDecoration(
                hintText:
                    'T.ex: Ska med tåget 07:49. Lämnar barnen på vägen, det tar 12 min. 4 min från parkeringen till tåget.',
                hintStyle:
                    TextStyle(fontSize: 13, color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox.shrink()
                    : const Text('✨', style: TextStyle(fontSize: 16)),
                label: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('Föreslå rutin',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: dayColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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

/// Bottom-sheet för att redigera eller ta bort ett enskilt steg.
class _StepEditSheet extends StatefulWidget {
  final String initialTitle;
  final String initialEmoji;
  final String? initialTid;
  final void Function(String title, String emoji, String? tid) onSave;
  final VoidCallback? onDelete;

  const _StepEditSheet({
    required this.initialTitle,
    required this.initialEmoji,
    this.initialTid,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_StepEditSheet> createState() => _StepEditSheetState();
}

class _StepEditSheetState extends State<_StepEditSheet> {
  late final TextEditingController _titleCtrl;
  late String _emoji;
  String? _tid;
  String? _suggestedEmoji;

  static const _commonEmojis = [
    '🪥', '🚿', '🧼', '👕', '🎒', '🍞', '🥣', '💊',
    '📚', '🧸', '😴', '🌙', '🧦', '🧴', '🚽', '✅',
    '🍳', '🥪', '🚶', '🚌', '🚗', '🏃', '🐶', '💧',
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _emoji = widget.initialEmoji;
    _tid = widget.initialTid;
    _checkSuggestion(_titleCtrl.text);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _checkSuggestion(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) {
      setState(() => _suggestedEmoji = null);
      return;
    }
    final sorted = List<PiktogramItem>.from(piktogramLibrary)
      ..sort((a, b) => b.label.length.compareTo(a.label.length));
    for (final item in sorted) {
      final label = item.label.toLowerCase();
      if (t.contains(label) || label.contains(t)) {
        setState(() {
          _suggestedEmoji = item.emoji;
          if (_emoji == '✅' || _emoji == widget.initialEmoji) {
            _emoji = item.emoji;
          }
        });
        return;
      }
    }
    setState(() => _suggestedEmoji = null);
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = const TimeOfDay(hour: 7, minute: 0);
    if (_tid != null && _tid!.contains(':')) {
      final parts = _tid!.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        initial = TimeOfDay(hour: h, minute: m);
      }
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      setState(() {
        _tid = '$hh:$mm';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.initialTitle.isEmpty ? 'Nytt steg' : 'Redigera steg',
                  style: AppTheme.sectionTitleStyle,
                ),
                if (widget.onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red),
                    tooltip: 'Ta bort steget',
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete!();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              autofocus: widget.initialTitle.isEmpty,
              decoration: InputDecoration(
                labelText: 'Stegets namn',
                hintText: 'T.ex. Klä på dig',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: _checkSuggestion,
            ),
            const SizedBox(height: 14),
            Text('VÄLJ PIKTOGRAM / EMOJI', style: AppTheme.sectionLabelStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_suggestedEmoji != null &&
                    !_commonEmojis.contains(_suggestedEmoji))
                  GestureDetector(
                    onTap: () => setState(() => _emoji = _suggestedEmoji!),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _emoji == _suggestedEmoji
                            ? dayColor.withValues(alpha: 0.25)
                            : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _emoji == _suggestedEmoji
                              ? dayColor
                              : Colors.amber.shade400,
                          width: 1.5,
                        ),
                      ),
                      child: Text(_suggestedEmoji!,
                          style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                ..._commonEmojis.map((em) {
                  final isSelected = _emoji == em;
                  final isSuggested = _suggestedEmoji == em;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = em),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? dayColor.withValues(alpha: 0.2)
                            : (isSuggested
                                ? Colors.amber.shade50
                                : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? Border.all(color: dayColor, width: 1.5)
                            : (isSuggested
                                ? Border.all(
                                    color: Colors.amber.shade400, width: 1.5)
                                : null),
                      ),
                      child: Text(em, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            Text('VALFRITT KLOCKSLAG', style: AppTheme.sectionLabelStyle),
            const SizedBox(height: 8),
            if (_tid == null)
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time_rounded, size: 18),
                label: const Text('Sätt tid'),
                onPressed: _pickTime,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _tid!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _tid = null),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _pickTime,
                    child: const Text('Ändra tid'),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.onDelete != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDelete!();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Ta bort'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      final t = _titleCtrl.text.trim();
                      if (t.isEmpty) return;
                      Navigator.pop(context);
                      widget.onSave(t, _emoji, _tid);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: dayColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Spara steg',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
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
