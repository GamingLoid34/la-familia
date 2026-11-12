import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/layout.dart';

/// Redigera foodPrefs på familjedokumentet (föräldrar).
Future<void> showFoodPrefsSheet(
  BuildContext context, {
  required String familyId,
  List<String>? allergier,
  List<String>? ogillar,
  List<String>? gillar,
  required VoidCallback onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => wrapBottomSheet(
      ctx,
      _FoodPrefsSheet(
        familyId: familyId,
        allergier: allergier ?? const [],
        ogillar: ogillar ?? const [],
        gillar: gillar ?? const [],
        onSaved: onSaved,
      ),
    ),
  );
}

class _FoodPrefsSheet extends StatefulWidget {
  final String familyId;
  final List<String> allergier;
  final List<String> ogillar;
  final List<String> gillar;
  final VoidCallback onSaved;

  const _FoodPrefsSheet({
    required this.familyId,
    required this.allergier,
    required this.ogillar,
    required this.gillar,
    required this.onSaved,
  });

  @override
  State<_FoodPrefsSheet> createState() => _FoodPrefsSheetState();
}

class _FoodPrefsSheetState extends State<_FoodPrefsSheet> {
  late List<String> _allergier;
  late List<String> _ogillar;
  late List<String> _gillar;
  final _ctrl = TextEditingController();
  String _target = 'allergier';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _allergier = List.of(widget.allergier);
    _ogillar = List.of(widget.ogillar);
    _gillar = List.of(widget.gillar);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<String> get _active {
    switch (_target) {
      case 'ogillar':
        return _ogillar;
      case 'gillar':
        return _gillar;
      default:
        return _allergier;
    }
  }

  void _add() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      if (!_active.contains(t)) _active.add(t);
      _ctrl.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .set({
        'foodPrefs': {
          'allergier': _allergier,
          'ogillar': _ogillar,
          'gillar': _gillar,
        },
      }, SetOptions(merge: true));
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunde inte spara: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _chipSection(String id, String label, List<String> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _target = id),
          child: Row(
            children: [
              Text(label, style: AppTheme.sectionLabelStyle),
              const SizedBox(width: 8),
              if (_target == id)
                Text('(vald)',
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in items)
              InputChip(
                label: Text(item),
                onDeleted: () => setState(() => items.remove(item)),
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            if (items.isEmpty)
              Text('Inga ännu',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Matpreferenser', style: AppTheme.sectionTitleStyle),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  Text(
                    'Används av AI-veckomenyn. Tryck en kategori, skriv och lägg till.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 14),
                  _chipSection('allergier', 'ALLERGIER', _allergier, Colors.red),
                  _chipSection('ogillar', 'OGILLAR', _ogillar, Colors.orange),
                  _chipSection('gillar', 'GILLAR', _gillar, Colors.green),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          decoration: InputDecoration(
                            hintText: 'Lägg till i $_target…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      IconButton(
                        onPressed: _add,
                        icon: Icon(Icons.add_circle_rounded,
                            color: dayColor, size: 32),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 16 + MediaQuery.paddingOf(context).bottom),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dayColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Spara',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
