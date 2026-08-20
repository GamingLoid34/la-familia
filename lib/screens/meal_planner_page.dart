import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/family_provider.dart';
import '../services/meal_ai_service.dart';
import '../utils/date_utils.dart';
import '../widgets/ai_meal_menu_sheet.dart';

/// Matplanering: veckans middagar, recept, AI-veckomeny.
class MealPlannerPage extends StatefulWidget {
  const MealPlannerPage({super.key});

  @override
  State<MealPlannerPage> createState() => _MealPlannerPageState();
}

class _MealPlannerPageState extends State<MealPlannerPage> {
  late DateTime _weekStart;
  bool _counting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  List<DateTime> get _days => List.generate(
      7,
      (i) =>
          DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i));

  void _shiftWeek(int weeks) => setState(() => _weekStart = DateTime(
      _weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks));

  /// Öka antalLagningar när en middag med dishId passerat sitt datum.
  Future<void> _bumpCookCounts(
    String familyId,
    Iterable<QueryDocumentSnapshot> docs,
  ) async {
    if (_counting) return;
    final today = dateKey(DateTime.now());
    final pending = <QueryDocumentSnapshot>[];
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final dishId = d['dishId'] as String?;
      final date = d['date'] as String? ?? '';
      final counted = d['cookCounted'] == true;
      if (dishId == null || dishId.isEmpty || date.isEmpty || counted) continue;
      if (date.compareTo(today) >= 0) continue;
      pending.add(doc);
    }
    if (pending.isEmpty) return;

    _counting = true;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in pending) {
        final d = doc.data() as Map<String, dynamic>;
        final dishId = d['dishId'] as String;
        final date = d['date'] as String;
        batch.update(doc.reference, {'cookCounted': true});
        batch.update(
          FirebaseFirestore.instance.collection('dishes').doc(dishId),
          {
            'antalLagningar': FieldValue.increment(1),
            'senastLagad': date,
          },
        );
      }
      await batch.commit();
    } catch (e, stack) {
      developer.log('cookCount bump misslyckades', error: e, stackTrace: stack);
    } finally {
      _counting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final fid = provider.currentUser?.familyId ?? '';
    final isParent = provider.currentUser?.isParent == true;
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    final palette = AppTheme.dayPalette();
    final weekKeys = _days.map(dateKey).toList();

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: AppTheme.getBackground(),
            child: Column(
              children: [
                Container(
                  decoration: AppTheme.headerDecoration(),
                  padding: AppTheme.paddingBelowStatusBar(context),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back_ios_rounded,
                          color: textColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Veckans mat 🍽️',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: textColor)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: () => _shiftWeek(-1),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${DateFormat('d MMM', 'sv').format(_days.first)} – ${DateFormat('d MMM', 'sv').format(_days.last)}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: () => _shiftWeek(1),
                      ),
                    ],
                  ),
                ),
                if (isParent && fid.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => runAiMealMenuFlow(
                          context,
                          familyId: fid,
                          weekStartHint: _weekStart,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.deep,
                          side: BorderSide(
                              color: palette.base.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Föreslå veckomeny ✨'),
                      ),
                    ),
                  ),
                Expanded(
                  child: fid.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('meals')
                              .where('familyId', isEqualTo: fid)
                              .where('date', whereIn: weekKeys)
                              .snapshots(),
                          builder: (ctx, snap) {
                            final docs = snap.data?.docs ?? const [];
                            final byDate = <String, QueryDocumentSnapshot>{};
                            for (final doc in docs) {
                              final d = doc.data() as Map<String, dynamic>;
                              byDate[d['date'] as String? ?? ''] = doc;
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _bumpCookCounts(fid, docs);
                            });

                            final today = dateKey(DateTime.now());

                            return ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: 7,
                              itemBuilder: (_, i) {
                                final day = _days[i];
                                final key = dateKey(day);
                                final doc = byDate[key];
                                final d =
                                    doc?.data() as Map<String, dynamic>?;
                                final isToday = key == today;
                                final leftover =
                                    d?['leftoverOfDay'] as String?;
                                String? leftoverLabel;
                                if (leftover != null && leftover.isNotEmpty) {
                                  final src = parseDate(leftover);
                                  if (src != null) {
                                    try {
                                      final n =
                                          DateFormat('EEEE', 'sv').format(src);
                                      leftoverLabel =
                                          '♻️ rester från ${n[0].toUpperCase()}${n.substring(1)}';
                                    } catch (_) {
                                      leftoverLabel = '♻️ rester';
                                    }
                                  }
                                }
                                final prep = (d?['recipe']
                                        as Map?)?['prepMinutes'] as num?;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration:
                                      AppTheme.cardDecoration(radius: 16)
                                          .copyWith(
                                    border: isToday
                                        ? Border.all(
                                            color: palette.base
                                                .withValues(alpha: 0.5),
                                            width: 1.5)
                                        : null,
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 2),
                                    leading: Text(
                                        d?['emoji'] as String? ?? '🍽️',
                                        style:
                                            const TextStyle(fontSize: 26)),
                                    title: Text(
                                      DateFormat('EEEE', 'sv').format(day),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: isToday
                                            ? palette.deep
                                            : Colors.grey.shade500,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (d?['title'] as String?)
                                                      ?.isNotEmpty ==
                                                  true
                                              ? d!['title'] as String
                                              : 'Lägg till middag…',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: d?['title'] != null
                                                ? AppTheme.getTextColor()
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                        if (leftoverLabel != null)
                                          Text(leftoverLabel,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      Colors.teal.shade700))
                                        else if (prep != null)
                                          Text('~${prep.round()} min',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      Colors.grey.shade600)),
                                      ],
                                    ),
                                    isThreeLine: leftoverLabel != null ||
                                        prep != null,
                                    trailing: Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.grey.shade400),
                                    onTap: () =>
                                        _openMealSheet(fid, day, doc),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMealSheet(
      String familyId, DateTime day, QueryDocumentSnapshot? existing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MealSheet(
        familyId: familyId,
        day: day,
        existing: existing,
      ),
    );
  }
}

class _MealSheet extends StatefulWidget {
  final String familyId;
  final DateTime day;
  final QueryDocumentSnapshot? existing;

  const _MealSheet({
    required this.familyId,
    required this.day,
    this.existing,
  });

  @override
  State<_MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends State<_MealSheet> {
  final _title = TextEditingController();
  final _ingredientCtrl = TextEditingController();
  final List<String> _ingredients = [];
  String _emoji = '🍽️';
  bool _saving = false;
  bool _recipeOpen = false;
  List<MealIngredient> _recipeIngs = [];
  List<String> _recipeSteps = [];
  int? _prepMinutes;
  String? _dishId;
  String? _leftoverOfDay;

  static const _emojis = [
    '🌮', '🍝', '🍕', '🐟', '🍲', '🥘', '🍗', '🍔',
    '🥗', '🥞', '🍜', '🥦', '🌯', '🍳', '🥩', '🍽️',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.existing?.data() as Map<String, dynamic>?;
    if (d != null) {
      _title.text = d['title'] as String? ?? '';
      _emoji = d['emoji'] as String? ?? '🍽️';
      _dishId = d['dishId'] as String?;
      _leftoverOfDay = d['leftoverOfDay'] as String?;
      final recipe = d['recipe'];
      if (recipe is Map) {
        _recipeIngs = (recipe['ingredients'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    MealIngredient.fromMap(Map<String, dynamic>.from(e)))
                .where((i) => i.namn.isNotEmpty)
                .toList() ??
            [];
        _recipeSteps = (recipe['steps'] as List?)
                ?.whereType<String>()
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            [];
        _prepMinutes = (recipe['prepMinutes'] as num?)?.round();
        if (_recipeIngs.isNotEmpty || _recipeSteps.isNotEmpty) {
          _recipeOpen = true;
        }
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _ingredientCtrl.dispose();
    super.dispose();
  }

  void _addIngredient() {
    final t = _ingredientCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _ingredients.add(t);
      _ingredientCtrl.clear();
    });
  }

  Future<void> _saveAsFamilyDish() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ings = _recipeIngs.isNotEmpty
        ? _recipeIngs
        : _ingredients
            .map((s) => MealIngredient(namn: s))
            .toList();
    try {
      final ref = await FirebaseFirestore.instance.collection('dishes').add({
        'familyId': widget.familyId,
        'namn': title,
        'emoji': _emoji,
        'kategori': 'ÖVRIGT',
        'ingredienser': ings.map((i) => i.toMap()).toList(),
        'steg': _recipeSteps,
        'tillagningMin': _prepMinutes ?? 30,
        'antalLagningar': 0,
        'senastLagad': null,
        'kalla': 'manuell',
        'createdByUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (widget.existing != null) {
        await widget.existing!.reference.update({'dishId': ref.id});
      }
      if (mounted) {
        setState(() => _dishId = ref.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sparad som familjerätt'),
            backgroundColor: Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Kunde inte spara rätt: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    setState(() => _saving = true);
    try {
      final recipe = <String, dynamic>{
        'ingredients': _recipeIngs.map((i) => i.toMap()).toList(),
        'steps': _recipeSteps,
        'prepMinutes': _prepMinutes ?? 30,
      };

      if (widget.existing != null) {
        if (title.isEmpty) {
          await widget.existing!.reference.delete();
        } else {
          await widget.existing!.reference.update({
            'title': title,
            'emoji': _emoji,
            if (_dishId != null) 'dishId': _dishId,
            if (_leftoverOfDay != null) 'leftoverOfDay': _leftoverOfDay,
            'recipe': recipe,
          });
        }
      } else if (title.isNotEmpty) {
        await FirebaseFirestore.instance.collection('meals').add({
          'familyId': widget.familyId,
          'date': dateKey(widget.day),
          'title': title,
          'emoji': _emoji,
          'dishId': _dishId,
          'leftoverOfDay': _leftoverOfDay,
          'recipe': recipe,
          'cookCounted': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (_ingredients.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final ing in _ingredients) {
          final ref =
              FirebaseFirestore.instance.collection('shopping_items').doc();
          batch.set(ref, {
            'title': ing,
            'isDone': false,
            'timestamp': FieldValue.serverTimestamp(),
            'familyId': widget.familyId,
          });
        }
        await batch.commit();
      }

      if (mounted) {
        Navigator.pop(context);
        if (_ingredients.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${_ingredients.length} varor lagda i inköpslistan 🛒'),
              backgroundColor: const Color(0xFF6BAE75),
            ),
          );
        }
      }
    } catch (e, stack) {
      developer.log('Meal save misslyckades', error: e, stackTrace: stack);
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
    final palette = AppTheme.dayPalette();
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final dayLabel = DateFormat('EEEE d MMM', 'sv').format(widget.day);
    final hasRecipe =
        _recipeIngs.isNotEmpty || _recipeSteps.isNotEmpty || _prepMinutes != null;
    final canSaveDish = _title.text.trim().isNotEmpty &&
        (_dishId == null || _dishId!.isEmpty);

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
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
              Text('Middag $dayLabel', style: AppTheme.sectionTitleStyle),
              if (_leftoverOfDay != null) ...[
                const SizedBox(height: 6),
                Text('♻️ Matlåda / rester',
                    style: TextStyle(
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                autofocus: _title.text.isEmpty,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Vad äter vi?',
                  hintText: 'T.ex. Tacos',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _emojis
                    .map((em) => GestureDetector(
                          onTap: () => setState(() => _emoji = em),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _emoji == em
                                  ? palette.base.withValues(alpha: 0.2)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: _emoji == em
                                  ? Border.all(color: palette.base)
                                  : null,
                            ),
                            child: Text(em,
                                style: const TextStyle(fontSize: 20)),
                          ),
                        ))
                    .toList(),
              ),
              if (hasRecipe) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => setState(() => _recipeOpen = !_recipeOpen),
                  child: Row(
                    children: [
                      Text('RECEPT', style: AppTheme.sectionLabelStyle),
                      const Spacer(),
                      if (_prepMinutes != null)
                        Text('~$_prepMinutes min',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      Icon(_recipeOpen
                          ? Icons.expand_less
                          : Icons.expand_more),
                    ],
                  ),
                ),
                if (_recipeOpen) ...[
                  const SizedBox(height: 8),
                  for (final ing in _recipeIngs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${ing.shoppingLine}',
                          style: const TextStyle(fontSize: 14)),
                    ),
                  if (_recipeSteps.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (var i = 0; i < _recipeSteps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${i + 1}. ${_recipeSteps[i]}',
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                ],
              ],
              if (canSaveDish) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _saveAsFamilyDish,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Spara som familjerätt'),
                ),
              ],
              const SizedBox(height: 16),
              Text('INGREDIENSER → INKÖPSLISTAN',
                  style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              ..._ingredients.map((ing) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Text('🛒', style: TextStyle(fontSize: 16)),
                    title: Text(ing),
                    trailing: IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Colors.red),
                      onPressed: () =>
                          setState(() => _ingredients.remove(ing)),
                    ),
                  )),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ingredientCtrl,
                    decoration: InputDecoration(
                      hintText: 'T.ex. tortillabröd',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _addIngredient(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle_rounded,
                      color: palette.base, size: 32),
                  onPressed: _addIngredient,
                ),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                if (widget.existing != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red),
                    onPressed: _saving
                        ? null
                        : () async {
                            await widget.existing!.reference.delete();
                            if (context.mounted) Navigator.pop(context);
                          },
                  ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.base,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Spara',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
