import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../data/hospital_menu.dart';
import '../utils/layout.dart';

/// Öppnar väljar-sheet för sjukhusmåltid (lunch eller middag).
Future<void> showMealChoiceSheet(
  BuildContext context, {
  required DateTime date,
  required String meal,
  required String familyId,
  required String personUid,
  Map<String, dynamic>? initialChoice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => MealChoiceSheet(
      date: date,
      meal: meal,
      familyId: familyId,
      personUid: personUid,
      initialChoice: initialChoice,
    ),
  );
}

class MealChoiceSheet extends StatefulWidget {
  final DateTime date;
  final String meal; // 'lunch' | 'middag'
  final String familyId;
  final String personUid;
  final Map<String, dynamic>? initialChoice;

  const MealChoiceSheet({
    super.key,
    required this.date,
    required this.meal,
    required this.familyId,
    required this.personUid,
    this.initialChoice,
  });

  @override
  State<MealChoiceSheet> createState() => _MealChoiceSheetState();
}

class _MealChoiceSheetState extends State<MealChoiceSheet> {
  String? _selectedDishId;
  String? _selectedRakostId;
  String? _selectedDessertId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialChoice != null) {
      _selectedDishId = widget.initialChoice!['dishId'] as String?;
      _selectedRakostId = widget.initialChoice!['rakostId'] as String?;
      _selectedDessertId = widget.initialChoice!['dessertId'] as String?;
    }
  }

  Future<void> _saveChoice() async {
    if (_selectedDishId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vänligen välj en rätt.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
    final docId = '${widget.personUid}_$dateStr';

    try {
      final data = <String, dynamic>{
        'familyId': widget.familyId,
        'personUid': widget.personUid,
        'date': dateStr,
        widget.meal: {
          'dishId': _selectedDishId,
          if (_selectedRakostId != null) 'rakostId': _selectedRakostId,
          if (_selectedDessertId != null) 'dessertId': _selectedDessertId,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('meal_choices')
          .doc(docId)
          .set(data, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e, st) {
      developer.log('Fel vid sparande av måltidsval: $e', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunde inte spara måltidsvalet.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekday = widget.date.weekday;
    final dayColor = AppTheme.getDayAccentColor(weekday);
    final dateFmt = DateFormat('EEEE d/M', 'sv').format(widget.date);
    final mealCapitalized = widget.meal == 'lunch' ? 'Lunch' : 'Middag';
    final headerTitle = '$mealCapitalized $dateFmt';

    final varmratter = hospitalMenuItems
        .where((i) => i.kategori == HospitalMenuCategory.varmratt)
        .toList();
    final smaratter = hospitalMenuItems
        .where((i) => i.kategori == HospitalMenuCategory.smaratt)
        .toList();
    final rakoster = hospitalMenuItems
        .where((i) => i.kategori == HospitalMenuCategory.rakost)
        .toList();
    final desserter = hospitalMenuItems
        .where((i) => i.kategori == HospitalMenuCategory.dessert)
        .toList();

    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return wrapBottomSheet(
      context,
      Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: dayColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('🍽️', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Patientmeny VOS Måltid',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollbart innehåll
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  // Sektion 1: Rätt
                  _buildSectionHeader('Rätt (välj en)', Icons.restaurant_menu_rounded, dayColor),
                  const SizedBox(height: 8),

                  for (final item in varmratter)
                    _buildDishTile(item, dayColor),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Smårätter',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),

                  for (final item in smaratter)
                    _buildDishTile(item, dayColor),

                  const SizedBox(height: 20),

                  // Sektion 2: Råkost (valfritt)
                  _buildSectionHeader('Råkost (valfritt)', Icons.eco_rounded, dayColor),
                  const SizedBox(height: 8),
                  for (final item in rakoster)
                    _buildOptionalTile(
                      item: item,
                      isSelected: _selectedRakostId == item.id,
                      dayColor: dayColor,
                      onTap: () {
                        setState(() {
                          _selectedRakostId = _selectedRakostId == item.id ? null : item.id;
                        });
                      },
                    ),

                  const SizedBox(height: 20),

                  // Sektion 3: Dessert (valfritt)
                  _buildSectionHeader('Dessert (valfritt)', Icons.icecream_rounded, dayColor),
                  const SizedBox(height: 8),
                  for (final item in desserter)
                    _buildOptionalTile(
                      item: item,
                      isSelected: _selectedDessertId == item.id,
                      dayColor: dayColor,
                      onTap: () {
                        setState(() {
                          _selectedDessertId = _selectedDessertId == item.id ? null : item.id;
                        });
                      },
                    ),
                ],
              ),
            ),

            // Sticky Save Button
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2F3B45),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('🍽️', style: TextStyle(fontSize: 20)),
                  label: Text(
                    _isSaving ? 'Sparar...' : 'Spara mitt val 🍽️',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveChoice,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color dayColor) {
    return Row(
      children: [
        Icon(icon, size: 18, color: dayColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildDishTile(HospitalMenuItem item, Color dayColor) {
    final isSelected = _selectedDishId == item.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? dayColor.withValues(alpha: 0.15) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              _selectedDishId = item.id;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? dayColor : Colors.grey.shade200,
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Nummer stort till vänster
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? dayColor : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${item.nummer}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.namn,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded, color: dayColor, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionalTile({
    required HospitalMenuItem item,
    required bool isSelected,
    required Color dayColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? dayColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? dayColor : Colors.grey.shade200,
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: isSelected ? dayColor : Colors.grey.shade400,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.namn,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
