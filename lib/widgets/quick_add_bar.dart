import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/quick_add_parser.dart';

/// Snabbinmatning (ROADMAP Etapp 10 + röst): skriv ELLER tala in en rad →
/// tolkat utkast → bekräfta → sparad. Förstår aktiviteter, sysslor
/// ("syssla dammsuga Liam"), middagar ("middag tacos fredag") och inköp
/// ("handla mjölk och bröd").
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
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;

  @override
  void dispose() {
    _speech.stop();
    _ctrl.dispose();
    super.dispose();
  }

  /// Tryck på mikrofonen → börja lyssna direkt (svenska). Live-texten
  /// skrivs i fältet; när taget är klart tolkas och bekräftas det.
  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (e) {
          developer.log('Taligenkänning: $e');
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Taligenkänning är inte tillgänglig på den här enheten.'),
            ),
          );
        }
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          localeId: 'sv_SE',
        ),
        onResult: (result) {
          if (!mounted) return;
          setState(() => _ctrl.text = result.recognizedWords);
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            setState(() => _listening = false);
            _submit();
          }
        },
      );
    } catch (e, stack) {
      developer.log('Röstinmatning misslyckades', error: e, stackTrace: stack);
      if (mounted) setState(() => _listening = false);
    }
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
          hintText: _listening
              ? '🎙️ Lyssnar… tala nu'
              : '⚡ Skriv eller tryck 🎤 — "Fotboll tis 17:00 Liam"',
          hintStyle: TextStyle(
            fontSize: 13,
            color: _listening ? palette.deep : Colors.grey.shade500,
            fontWeight: _listening ? FontWeight.w700 : FontWeight.normal,
          ),
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
            borderSide: BorderSide(
              color: _listening
                  ? palette.base
                  : palette.base.withValues(alpha: 0.25),
              width: _listening ? 2 : 1,
            ),
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _listening ? Colors.red.shade400 : palette.deep,
                  size: 24,
                ),
                tooltip: _listening ? 'Sluta lyssna' : 'Tala in',
                onPressed: _toggleListen,
              ),
              IconButton(
                icon: Icon(Icons.arrow_circle_up_rounded,
                    color: palette.deep, size: 26),
                onPressed: _submit,
              ),
            ],
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

  String get _intentLabel => switch (widget.draft.intent) {
        QuickAddIntent.activity => 'Aktivitet',
        QuickAddIntent.chore => 'Syssla',
        QuickAddIntent.meal => 'Middag',
        QuickAddIntent.shopping => 'Inköpslistan',
      };

  Future<void> _save() async {
    setState(() => _saving = true);
    final d = widget.draft;
    try {
      String snackText;
      switch (d.intent) {
        case QuickAddIntent.activity:
          await _saveActivity(d);
          snackText = '${d.piktogram} ${d.title} sparad! ✅';
        case QuickAddIntent.chore:
          await _saveChore(d);
          snackText = '✅ Syssla "${d.title}" sparad!';
        case QuickAddIntent.meal:
          await _saveMeal(d);
          snackText =
              '🍽️ ${DateFormat('EEEE', 'sv').format(d.date)}: ${d.title}';
        case QuickAddIntent.shopping:
          await _saveShopping(d);
          snackText = '🛒 ${d.items.length} varor lagda i inköpslistan!';
      }

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackText),
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

  Future<void> _saveActivity(QuickAddDraft d) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final names = d.persons.map((m) => m.name).toList();
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
      'createdByUid': uid,
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
          if (d.recurrenceType.isNotEmpty) 'recurrence': data['recurrence'],
        },
      );
    }
  }

  Future<void> _saveChore(QuickAddDraft d) async {
    final assignee = d.persons.isNotEmpty ? d.persons.first : null;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    await FirebaseFirestore.instance.collection('chores').add({
      'chore': d.title,
      'piktogram': d.piktogram,
      'who': assignee?.name ?? '',
      'whoUid': assignee?.uid ?? '',
      'whoColor': assignee?.color ?? '',
      'isDone': false,
      'points': 3,
      'isRecurring': false,
      'familyId': widget.familyId,
      if (d.hasExplicitDate) 'dueDate': dateKey(d.date),
      'substeps': <Map<String, dynamic>>[],
      'createdByUid': ?uid,
    });
  }

  Future<void> _saveMeal(QuickAddDraft d) async {
    final db = FirebaseFirestore.instance;
    // En middag per dag: uppdatera om den redan finns.
    final existing = await db
        .collection('meals')
        .where('familyId', isEqualTo: widget.familyId)
        .where('date', isEqualTo: dateKey(d.date))
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference
          .update({'title': d.title, 'emoji': d.piktogram});
    } else {
      await db.collection('meals').add({
        'familyId': widget.familyId,
        'date': dateKey(d.date),
        'title': d.title,
        'emoji': d.piktogram,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _saveShopping(QuickAddDraft d) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final item in d.items) {
      batch.set(db.collection('shopping_items').doc(), {
        'title': item,
        'isDone': false,
        'timestamp': FieldValue.serverTimestamp(),
        'familyId': widget.familyId,
      });
    }
    await batch.commit();
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
    final isShopping = d.intent == QuickAddIntent.shopping;

    return wrapBottomSheet(
      context,
      Container(
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
              _chip(Icons.category_rounded, _intentLabel, palette.deep),
              if (!isShopping && (d.hasExplicitDate || d.time.isNotEmpty))
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
              if (d.intent == QuickAddIntent.activity && d.persons.isEmpty)
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
    ),
    );
  }
}
