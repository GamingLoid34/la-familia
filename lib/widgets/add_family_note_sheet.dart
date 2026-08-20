import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/layout.dart';
import '../app_theme.dart';
import '../models/family_note.dart';
import '../models/user_model.dart';

/// Bottom sheet för att lägga till en kort dagsnotis på familjedagstavlan.
class AddFamilyNoteSheet extends StatefulWidget {
  final String familyId;
  final UserModel user;
  final List<FamilyNote> todayNotes;

  const AddFamilyNoteSheet({
    super.key,
    required this.familyId,
    required this.user,
    required this.todayNotes,
  });

  static Future<void> show(
    BuildContext context, {
    required String familyId,
    required UserModel user,
    required List<FamilyNote> todayNotes,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddFamilyNoteSheet(
        familyId: familyId,
        user: user,
        todayNotes: todayNotes,
      ),
    );
  }

  @override
  State<AddFamilyNoteSheet> createState() => _AddFamilyNoteSheetState();
}

class _AddFamilyNoteSheetState extends State<AddFamilyNoteSheet> {
  static const _maxLen = 140;
  static const _maxNotesPerDay = 3;

  static const _templates = [
    'På väg hem 🚗',
    'Sover middag 😴',
    'Behöver bli hämtad',
    'Lite seg idag',
    'Allt bra! ✨',
    'Lämnar kl ___',
  ];

  final _text = TextEditingController();
  bool _saving = false;

  int get _myNotesToday =>
      widget.todayNotes.where((n) => n.fromUid == widget.user.uid).length;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _todayDateKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > _maxLen) return;
    if (_myNotesToday >= _maxNotesPerDay) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Max 3 notiser per dag — ta bort en först.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    try {
      await FirebaseFirestore.instance.collection('family_notes').add({
        'familyId': widget.familyId,
        'fromUid': widget.user.uid,
        'fromName': widget.user.name,
        'fromColor': widget.user.color,
        'date': _todayDateKey(),
        'createdAt': FieldValue.serverTimestamp(),
        'text': trimmed,
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e, stack) {
      developer.log('AddFamilyNoteSheet save error',
          error: e, stackTrace: stack);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara: $e'),
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
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    return wrapBottomSheet(
      context,
      Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPad),
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
              Text(
                'Lägg till notis',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.getTextColor(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_myNotesToday / $_maxNotesPerDay idag',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                maxLength: _maxLen,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Kort meddelande till familjen…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  counterText: '${_text.text.length}/$_maxLen',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _templates.map((t) {
                  return ActionChip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    onPressed: _saving
                        ? null
                        : () {
                            _text.text = t;
                            setState(() {});
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _saving || _text.text.trim().isEmpty
                      ? null
                      : () => _save(_text.text),
                  style: FilledButton.styleFrom(backgroundColor: dayColor),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Skicka'),
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
