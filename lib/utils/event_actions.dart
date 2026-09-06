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
                '"${d['title'] ?? ''}" upprepas (${recurrenceLabel(d)}).'),
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
          await NotificationService.cancelActivityInstance(doc.id, listDay);
          await doc.reference.update({
            'recurrence.exceptions':
                FieldValue.arrayUnion([dateKey(listDay)]),
          });
        } else if (choice == 'all') {
          await NotificationService.cancelActivityReminders(doc.id, d);
          await doc.reference.delete();
        }
        return;
      }

      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ta bort aktivitet?'),
          content: const Text('Den tas bort från planeringen.'),
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
        await NotificationService.cancel(doc.id);
        await doc.reference.delete();
      }
    }
  } catch (e, stack) {
    developer.log('Fel vid hantering av aktivitetsmeny ($action)',
        error: e, stackTrace: stack);
  }
}
