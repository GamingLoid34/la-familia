import '../services/occurrence_mutations.dart';
import '../services/activity_receipts.dart';
import '../widgets/move_occurrence_dialog.dart';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import '../utils/recurrence.dart';
import '../widgets/add_event_sheet.dart';

/// Delad hantering av menyval ('edit' eller 'delete') för en aktivitet/händelse.
Future<void> handleEventMenuAction(
  BuildContext context, {
  required String action, // 'edit' | 'delete'
  required QueryDocumentSnapshot doc,
  required DateTime listDay,
  required List<UserModel> familyMembers,
  required String familyId,
}) async {
  try {
    if (action == 'edit') {
      final d = doc.data() as Map<String, dynamic>;
      if (d['recurrence'] != null && d['source'] != 'calendar') {
        if (!context.mounted) return;
        final choice = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Ändra återkommande aktivitet'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'move'), child: const Text('Flytta bara detta tillfälle')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'series'), child: const Text('Redigera hela serien')),
          ],
        ));
        if (!context.mounted || choice == null) return;
        if (choice == 'move') { await showMoveOccurrence(context, doc, listDay); return; }
      }
      var day = listDay;
      final pd = parseDate(d['date']);
      if (pd != null) day = pd;
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AddEventSheet(
          selectedDay: day,
          familyMembers: familyMembers,
          familyId: familyId.isEmpty ? null : familyId,
          eventToEdit: doc,
        ),
      );
    } else if (action == 'delete') {
      final d = doc.data() as Map<String, dynamic>;
      final isRecurring = d['recurrence'] != null;

      if (isRecurring) {
        // Återkommande: fråga om bara denna dag eller alla gånger.
        if (!context.mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ta bort återkommande aktivitet?'),
            content: Text(
                '"${d['title'] ?? ''}" upprepas (${recurrenceLabel(d)}). Alla gånger tar även bort flyttade tillfällen. Kräver internet.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Avbryt'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'single'),
                child: const Text('Bara denna dag'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'all'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Alla gånger'),
              ),
            ],
          ),
        );
        if (choice == 'single') {
          await ActivityReceipts.track(family: familyId, title: d['title'] as String? ?? 'Aktivitet', date: dateKey(listDay), ids: [doc.id], operation: (writeId) => doc.reference.update({
            'recurrence.exceptions': FieldValue.arrayUnion([dateKey(listDay)]), 'writeId': writeId,
          }));
          await NotificationService.cancelActivityInstance(doc.id, listDay);
        } else if (choice == 'all') {
          await deleteSeries(doc.reference, d);
          await NotificationService.cancelActivityReminders(doc.id, d);
        }
        return;
      }

      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ta bort aktivitet?'),
          content: const Text('Den tas bort från planeringen. Kräver internet.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Ta bort'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await deleteSeries(doc.reference, d);
        await NotificationService.cancel(doc.id);
      }
    }
  } catch (e, stack) {
    developer.log('Fel vid hantering av aktivitetsmeny ($action)',
        error: e, stackTrace: stack);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ändringen kunde inte sparas. Försök igen.')));
  }
}
