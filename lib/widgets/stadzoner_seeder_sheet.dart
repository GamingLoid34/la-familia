import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/stadzoner.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import 'trasa_chip.dart';

/// Modal bottom sheet för att skapa städzoner idempotent.
class StadzonerSeederSheet extends StatefulWidget {
  final String familyId;

  const StadzonerSeederSheet({
    super.key,
    required this.familyId,
  });

  @override
  State<StadzonerSeederSheet> createState() => _StadzonerSeederSheetState();
}

class _StadzonerSeederSheetState extends State<StadzonerSeederSheet> {
  final Set<String> _selectedKeys = stadZoner.map((z) => z.key).toSet();
  bool _isSaving = false;

  Future<void> _seedZones() async {
    if (_selectedKeys.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('chores')
          .where('familyId', isEqualTo: widget.familyId)
          .get();

      final existingKeys = <String>{};
      for (final doc in snap.docs) {
        final k = doc.data()['stadKey'] as String?;
        if (k != null && k.isNotEmpty) {
          existingKeys.add(k);
        }
      }

      int created = 0;
      int alreadyExists = 0;
      final startDay = getNextSaturday();
      final startDayKey = dateKey(startDay);
      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      for (final key in _selectedKeys) {
        final zon = stadZonByKey(key);
        if (zon == null) continue;

        if (existingKeys.contains(key)) {
          alreadyExists++;
          continue;
        }

        await FirebaseFirestore.instance.collection('chores').add({
          'chore': zon.titel,
          'piktogram': zon.piktogram,
          'who': '',
          'whoUid': '',
          'whoColor': '',
          'isDone': false,
          'points': zon.points,
          'familyId': widget.familyId,
          'substeps': zon.steg.map((s) => {'title': s, 'isDone': false}).toList(),
          'isRecurring': true,
          'doneDates': <String>[],
          'dueDate': startDayKey,
          'rotationUids': <String>[],
          'recurrence': {
            'type': 'weekly',
            'startDate': startDayKey,
            'endDate': null,
            'exceptions': <String>[],
          },
          'stadKey': zon.key,
          'stadFarg': zon.farg,
          'verktyg': zon.verktyg,
          'createdByUid': ?currentUid,
        });
        created++;
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$created zoner skapade · $alreadyExists fanns redan'),
            backgroundColor: const Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte skapa zoner: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return wrapBottomSheet(
      context,
      Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  const Text('🧹', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Skapa städzoner',
                            style: AppTheme.sectionTitleStyle),
                        Text(
                          'Återkommande varje lördag med delsteg och färgkodade trasor.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Flexible(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shrinkWrap: true,
                children: stadZoner.map((zon) {
                  final isSelected = _selectedKeys.contains(zon.key);
                  return CheckboxListTile(
                    value: isSelected,
                    activeColor: dayColor,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedKeys.add(zon.key);
                        } else {
                          _selectedKeys.remove(zon.key);
                        }
                      });
                    },
                    secondary: Text(
                      zon.piktogram,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Row(
                      children: [
                        Text(
                          zon.titel,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (zon.farg != null)
                          TrasaChip.fromZon(zon, circleSize: 14),
                      ],
                    ),
                    subtitle: Text(
                      '${zon.steg.length} delsteg · ${zon.verktyg.join(', ')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPad),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving || _selectedKeys.isEmpty ? null : _seedZones,
                  style: FilledButton.styleFrom(
                    backgroundColor: dayColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Skapa ${_selectedKeys.length} zoner',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
