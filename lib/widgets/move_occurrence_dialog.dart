import '../services/activity_receipts.dart';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/date_utils.dart';
import '../utils/move_occurrence.dart';
import '../services/notification_service.dart';

Future<void> showMoveOccurrence(BuildContext context, QueryDocumentSnapshot doc, DateTime original) =>
    showDialog<void>(context: context, barrierDismissible: false,
      builder: (_) => _MoveDialog(doc: doc, original: original));

class _MoveDialog extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final DateTime original;
  const _MoveDialog({required this.doc, required this.original});
  @override State<_MoveDialog> createState() => _MoveDialogState();
}
class _MoveDialogState extends State<_MoveDialog> {
  late final day = TextEditingController(text: dateKey(widget.original));
  late final time = TextEditingController(text: (widget.doc.data() as Map)['time'] as String? ?? '');
  late final end = TextEditingController(text: (widget.doc.data() as Map)['endTime'] as String? ?? '');
  bool saving = false;
  String? error;
  @override void dispose() { day.dispose(); time.dispose(); end.dispose(); super.dispose(); }
  Future<void> save() async {
    final targetDay = day.text.trim(), targetTime = time.text.trim(), targetEnd = end.text.trim();
    final validation = validateMove(targetDay, targetTime, targetEnd);
    if (validation != null) { setState(() => error = validation); return; }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() { saving = true; error = null; });
    try {
      final db = FirebaseFirestore.instance;
      final target = db.collection('planner_events').doc(movedOccurrenceId(widget.doc.id, widget.original));
      final moved = await ActivityReceipts.track(family: (widget.doc.data() as Map)['familyId'] as String,
        title: (widget.doc.data() as Map)['title'] as String? ?? 'Aktivitet', date: targetDay, ids: [target.id],
        operation: (writeId) => db.runTransaction<Map<String, dynamic>>((tx) async {
        final source = await tx.get(widget.doc.reference);
        if (!source.exists) throw StateError('Serien finns inte längre.');
        final sourceData = Map<String, dynamic>.from(source.data() as Map);
        final alreadyMoved = (sourceData['detachedOccurrences'] as Map?)?[dateKey(widget.original)];
        if (alreadyMoved != null) {
          if (alreadyMoved != target.id) throw StateError('Tillfället har redan ändrats.');
          final data = (await tx.get(target)).data();
          if (data == null) throw StateError('Det flyttade tillfället har tagits bort.');
          if (data['date'] != targetDay || data['time'] != targetTime || (data['endTime'] ?? '') != targetEnd) {
            throw StateError('Tillfället har redan flyttats. Öppna kalendern igen.');
          }
          return data;
        }
        final data = detachedOccurrence(Map<String, dynamic>.from(source.data() as Map),
          widget.doc.id, widget.original, targetDay, targetTime, targetEnd, uid);
        tx.update(widget.doc.reference, {'recurrence.exceptions': FieldValue.arrayUnion([dateKey(widget.original)]), 'detachedOccurrences.${dateKey(widget.original)}': target.id});
        data['writeId'] = writeId;
        tx.set(target, data);
        return data;
      }));
      await NotificationService.cancelActivityInstance(widget.doc.id, widget.original);
      await NotificationService.scheduleActivityReminders(docId: target.id, data: moved);
      if (mounted) Navigator.pop(context);
    } catch (e, stack) {
      developer.log('Flytt av tillfälle misslyckades', error: e, stackTrace: stack);
      if (mounted) setState(() { saving = false; error = 'Kunde inte flytta. Kontrollera anslutningen och öppna kalendern igen. $e'; });
    }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !saving, child: AlertDialog(
    title: Text('Flytta tillfället ${dateKey(widget.original)}'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Bara detta tillfälle flyttas och blir en fristående aktivitet. Kräver internet.'),
      TextField(controller: day, enabled: !saving, decoration: const InputDecoration(labelText: 'Datum ÅÅÅÅ-MM-DD')),
      TextField(controller: time, enabled: !saving, decoration: const InputDecoration(labelText: 'Start HH:mm, tomt för utan tid')),
      TextField(controller: end, enabled: !saving, decoration: const InputDecoration(labelText: 'Slut HH:mm, valfri')),
      if (error != null) Text(error!),
    ])),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Avbryt')),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Flyttar…' : 'Flytta'))],
  ));
}
