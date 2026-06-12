import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import '../utils/quick_add_parser.dart';

/// Snabbinmatning (ROADMAP Etapp 10.2): en rad text → tolkat utkast →
/// bekräfta → sparad aktivitet. "Fotboll tis 17:00 Liam" räcker.
class QuickAddBar extends StatefulWidget {
  final List<UserModel> familyMembers;
  final String familyId;
  /// Anropas om tolkningen misslyckas — öppna vanliga formuläret med texten.
  final void Function(String rawText)? onFallbackToForm;

  const QuickAddBar({
    super.key,
    required this.familyMembers,
    required this.familyId,
    this.onFallbackToForm,
  });

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final draft = parseQuickAdd(text, members: widget.familyMembers);
    if (draft == null) {
      widget.onFallbackToForm?.call(text);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickAddConfirmSheet(
        draft: draft,
        familyId: widget.familyId,
        onSaved: () {
          _ctrl.clear();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: TextField(
        controller: _ctrl,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: '⚡ Snabbt: "Fotboll tis 17:00 Liam"',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: palette.base.withValues(alpha: 0.25)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: palette.base.withValues(alpha: 0.25)),
          ),
          suffixIcon: IconButton(
            icon: Icon(Icons.arrow_circle_up_rounded,
                color: palette.deep, size: 26),
            onPressed: _submit,
          ),
        ),
      ),
    );
  }
}

class _QuickAddConfirmSheet extends StatefulWidget {
  final QuickAddDraft draft;
  final String familyId;
  final VoidCallback onSaved;

  const _QuickAddConfirmSheet({
    required this.draft,
    required this.familyId,
    required this.onSaved,
  });

  @override
  State<_QuickAddConfirmSheet> createState() => _QuickAddConfirmSheetState();
}

class _QuickAddConfirmSheetState extends State<_QuickAddConfirmSheet> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final d = widget.draft;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final names = d.persons.map((m) => m.name).toList();
    try {
      final data = <String, dynamic>{
        'title': d.title,
        'piktogram': d.piktogram,
        'type': 'activity',
        'date': dateKey(d.date),
        'time': d.time,
        'persons': names,
        'personUids': d.persons.map((m) => m.uid).toList(),
        'checklist': <dynamic>[],
        'source': 'manual',
        'createdBy': uid,
        'isPending': false,
        'familyId': widget.familyId,
      };
      if (d.recurrenceType.isNotEmpty) {
        data['isRecurring'] = true;
        data['recurrence'] = {
          'type': d.recurrenceType,
          'startDate': dateKey(d.date),
          'endDate': null,
          'exceptions': <String>[],
        };
      }
      final ref = await FirebaseFirestore.instance
          .collection('planner_events')
          .add(data);

      if (d.time.isNotEmpty) {
        await NotificationService.scheduleActivityReminders(
          docId: ref.id,
          data: {
            'title': d.title,
            'date': dateKey(d.date),
            'time': d.time,
            if (d.recurrenceType.isNotEmpty)
              'recurrence': data['recurrence'],
          },
        );
      }

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${d.piktogram} ${d.title} sparad! ✅'),
            backgroundColor: const Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('QuickAdd save misslyckades', error: e, stackTrace: stack);
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

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final palette = AppTheme.dayPalette();
    final dateLabel = DateFormat('EEEE d MMM', 'sv').format(d.date);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.paddingOf(context).bottom),
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
          Text('Stämmer det här?', style: AppTheme.sectionTitleStyle),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(d.piktogram, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(d.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.event_rounded, dateLabel, palette.deep),
              if (d.time.isNotEmpty)
                _chip(Icons.access_time_rounded, d.time, palette.deep),
              if (d.recurrenceType.isNotEmpty)
                _chip(
                    Icons.repeat_rounded,
                    d.recurrenceType == 'weekly'
                        ? 'Varje vecka'
                        : 'Varannan vecka',
                    palette.deep),
              for (final p in d.persons)
                _chip(Icons.person_rounded, p.name.split(' ').first,
                    AppTheme.colorFromHex(p.color)),
              if (d.persons.isEmpty)
                _chip(Icons.groups_rounded, 'Hela familjen',
                    Colors.grey.shade600),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Avbryt'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
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
                      : const Text('Spara ✓',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
