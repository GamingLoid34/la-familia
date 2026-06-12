import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Manuell ”incheckning” så familjen ser att du är upptagen utan kalenderimport.
class BusyCheckInSheet extends StatefulWidget {
  final String familyId;
  final String userName;
  final String userUid;

  const BusyCheckInSheet({
    super.key,
    required this.familyId,
    required this.userName,
    this.userUid = '',
  });

  @override
  State<BusyCheckInSheet> createState() => _BusyCheckInSheetState();
}

class _BusyCheckInSheetState extends State<BusyCheckInSheet> {
  final _note = TextEditingController();
  int _minutes = 60;
  bool _saving = false;

  static const _presets = <int>[15, 30, 45, 60, 90, 120];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    final end = now.add(Duration(minutes: _minutes));
    try {
      await FirebaseFirestore.instance.collection('busy_sessions').add({
        'familyId': widget.familyId,
        'userName': widget.userName,
        'userUid': widget.userUid,
        'startAt': Timestamp.fromDate(now),
        'endAt': Timestamp.fromDate(end),
        'note': _note.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Upptagen till ${TimeOfDay.fromDateTime(end).format(context)}',
          ),
          backgroundColor: const Color(0xFF6BAE75),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunde inte spara: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          Text('Jag är upptagen', style: AppTheme.sectionTitleStyle),
          const SizedBox(height: 4),
          Text(
            'Andra i familjen ser dig som upptagen (röd ring) under tiden du väljer — utan kalenderimport.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          Text('Hur länge?', style: AppTheme.sectionLabelStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((m) {
              final sel = _minutes == m;
              return ChoiceChip(
                label: Text('$m min'),
                selected: sel,
                selectedColor: dayColor.withValues(alpha: 0.25),
                onSelected: (_) => setState(() => _minutes = m),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: 'Vad gör du? (valfritt)',
              hintText: 'T.ex. möte, plugga…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _saving ? null : _save,
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
                  : const Text('Starta'),
            ),
          ),
        ],
      ),
    );
  }
}
