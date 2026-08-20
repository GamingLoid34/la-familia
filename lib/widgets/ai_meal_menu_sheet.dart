import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../services/meal_ai_service.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';

/// Periodväljare → AI-meny → förhandsgranska / tillämpa.
Future<void> runAiMealMenuFlow(
  BuildContext context, {
  required String familyId,
  DateTime? weekStartHint,
}) async {
  final range = await showModalBottomSheet<_MealPeriod>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => wrapBottomSheet(
      ctx,
      _MealPeriodPicker(weekStartHint: weekStartHint),
    ),
  );
  if (range == null || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final menu = await MealAiService.askMealPlanner(
      startDate: dateKey(range.start),
      days: range.days,
    );
    if (!context.mounted) return;
    Navigator.pop(context); // loading
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => wrapBottomSheet(
        ctx,
        _AiMealMenuSheet(familyId: familyId, initialMenu: menu),
      ),
    );
  } on FirebaseFunctionsException catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Kunde inte hämta meny.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  } catch (e, stack) {
    developer.log('AI-meny misslyckades', error: e, stackTrace: stack);
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte hämta meny: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }
}

class _MealPeriod {
  final DateTime start;
  final int days;
  const _MealPeriod({required this.start, required this.days});
}

class _MealPeriodPicker extends StatefulWidget {
  final DateTime? weekStartHint;
  const _MealPeriodPicker({this.weekStartHint});

  @override
  State<_MealPeriodPicker> createState() => _MealPeriodPickerState();
}

class _MealPeriodPickerState extends State<_MealPeriodPicker> {
  late DateTime _start;
  int _days = 7;
  String _preset = 'week';

  @override
  void initState() {
    super.initState();
    final hint = widget.weekStartHint;
    if (hint != null) {
      _start = DateTime(hint.year, hint.month, hint.day);
      _preset = 'thisWeek';
    } else {
      final n = DateTime.now();
      _start = DateTime(n.year, n.month, n.day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final end = _start.add(Duration(days: _days - 1));
    String label;
    try {
      label =
          '${DateFormat('d MMM', 'sv').format(_start)} – ${DateFormat('d MMM', 'sv').format(end)}';
    } catch (_) {
      label =
          '${DateFormat('d MMM').format(_start)} – ${DateFormat('d MMM').format(end)}';
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
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
          const SizedBox(height: 14),
          Text('Föreslå veckomeny', style: AppTheme.sectionTitleStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Denna vecka'),
                selected: _preset == 'thisWeek',
                onSelected: (_) {
                  final n = DateTime.now();
                  final t = DateTime(n.year, n.month, n.day);
                  setState(() {
                    _preset = 'thisWeek';
                    _start = t.subtract(Duration(days: t.weekday - 1));
                    _days = 7;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Nästa vecka'),
                selected: _preset == 'nextWeek',
                onSelected: (_) {
                  final n = DateTime.now();
                  final t = DateTime(n.year, n.month, n.day);
                  final mon = t.subtract(Duration(days: t.weekday - 1));
                  setState(() {
                    _preset = 'nextWeek';
                    _start = mon.add(const Duration(days: 7));
                    _days = 7;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('7 dagar från idag'),
                selected: _preset == 'week',
                onSelected: (_) {
                  final n = DateTime.now();
                  setState(() {
                    _preset = 'week';
                    _start = DateTime(n.year, n.month, n.day);
                    _days = 7;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15, color: dayColor)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              _MealPeriod(start: _start, days: _days),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: dayColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Skapa förslag ✨'),
          ),
        ],
      ),
    );
  }
}

class _AiMealMenuSheet extends StatefulWidget {
  final String familyId;
  final List<MealMenuDay> initialMenu;

  const _AiMealMenuSheet({
    required this.familyId,
    required this.initialMenu,
  });

  @override
  State<_AiMealMenuSheet> createState() => _AiMealMenuSheetState();
}

class _AiMealMenuSheetState extends State<_AiMealMenuSheet> {
  late List<MealMenuDay> _menu;
  final Set<int> _busyDays = {};
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _menu = List.of(widget.initialMenu);
  }

  String _weekdayName(String dayKey) {
    final d = parseDate(dayKey);
    if (d == null) return dayKey;
    try {
      return DateFormat('EEEE', 'sv').format(d);
    } catch (_) {
      return DateFormat('EEEE').format(d);
    }
  }

  String? _leftoverLabel(MealMenuDay day) {
    final src = day.leftoverOfDay;
    if (src == null) return null;
    final name = _weekdayName(src);
    final capped =
        name.isEmpty ? src : '${name[0].toUpperCase()}${name.substring(1)}';
    return '♻️ rester från $capped';
  }

  Future<void> _swapDay(int index) async {
    if (_busyDays.contains(index)) return;
    final day = _menu[index];
    setState(() => _busyDays.add(index));
    try {
      final fresh = await MealAiService.askMealPlanner(
        startDate: day.day,
        days: 1,
      );
      if (!mounted) return;
      if (fresh.isNotEmpty) {
        setState(() => _menu[index] = fresh.first.copyWith(day: day.day));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Kunde inte byta rätt.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte byta rätt: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDays.remove(index));
    }
  }

  Future<void> _applyWeek() async {
    if (_applying) return;
    setState(() => _applying = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final db = FirebaseFirestore.instance;

    try {
      for (final day in _menu) {
        String? dishId = day.dishId;

        if (dishId == null && !day.isLeftover) {
          final dishRef = db.collection('dishes').doc();
          await dishRef.set({
            'familyId': widget.familyId,
            'namn': day.title,
            'emoji': day.emoji,
            'kategori': 'ÖVRIGT',
            'ingredienser': day.ingredients.map((i) => i.toMap()).toList(),
            'steg': day.steps,
            'tillagningMin': day.prepMinutes,
            'antalLagningar': 0,
            'senastLagad': null,
            'kalla': 'ai',
            'createdByUid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          dishId = dishRef.id;
        }

        final existing = await db
            .collection('meals')
            .where('familyId', isEqualTo: widget.familyId)
            .where('date', isEqualTo: day.day)
            .limit(1)
            .get();

        final fields = <String, dynamic>{
          'familyId': widget.familyId,
          'date': day.day,
          'title': day.title,
          'emoji': day.emoji,
          'dishId': dishId,
          'leftoverOfDay': day.leftoverOfDay,
          'recipe': day.recipeMap(),
          'cookCounted': false,
        };

        if (existing.docs.isNotEmpty) {
          await existing.docs.first.reference.set(fields, SetOptions(merge: true));
        } else {
          fields['createdAt'] = FieldValue.serverTimestamp();
          await db.collection('meals').add(fields);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veckomenyn sparad!'),
            backgroundColor: Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('Spara AI-meny misslyckades', error: e, stackTrace: stack);
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _addShopping() async {
    final lines = <String>[];
    for (final day in _menu) {
      if (day.isLeftover) continue;
      for (final ing in day.ingredients) {
        final line = ing.shoppingLine;
        if (line.isNotEmpty) lines.add(line);
      }
    }
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inga ingredienser att lägga till.')),
      );
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final line in lines) {
      final ref = FirebaseFirestore.instance.collection('shopping_items').doc();
      batch.set(ref, {
        'title': line,
        'isDone': false,
        'timestamp': FieldValue.serverTimestamp(),
        'familyId': widget.familyId,
      });
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lines.length} varor till inköpslistan 🛒'),
          backgroundColor: const Color(0xFF6BAE75),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('AI-veckomeny', style: AppTheme.sectionTitleStyle),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: _menu.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final day = _menu[i];
                final leftover = _leftoverLabel(day);
                final busy = _busyDays.contains(i);
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppTheme.cardDecoration(radius: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(day.emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _weekdayName(day.day),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: dayColor,
                                  ),
                                ),
                                Text(
                                  day.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  leftover ?? '~${day.prepMinutes} min',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: leftover != null
                                        ? Colors.teal.shade700
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: busy || _applying ? null : () => _swapDay(i),
                            child: busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Byt ut 🔄',
                                    style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottom),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _applying ? null : _addShopping,
                    child: const Text('🛒 Veckans ingredienser till inköpslistan'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _applying ? null : _applyWeek,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: dayColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _applying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Använd hela veckan',
                            style: TextStyle(fontWeight: FontWeight.bold)),
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
