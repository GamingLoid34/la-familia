import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../widgets/vardag_header.dart';
import 'aterkommande_lista.dart';
import 'chore_utils.dart';
import 'date_utils.dart';
import 'recurrence.dart';

/// Ta bort en syssla (Androids "Ta bort syssla"). En återkommande syssla
/// frågar om bara [occurrenceDay] ("Bara i morgon", "Bara tisdag 29 sep" …)
/// eller alla gånger; ett enskilt tillfälle hoppas över via
/// `recurrence.exceptions`. Påminnelser avbokas och fel visas.
/// [occurrenceDay] null ⇒ bara "Alla gånger" erbjuds (t.ex. från listan
/// Återkommande). Returnerar true när något togs bort.
Future<bool> deleteChore(
  BuildContext context, {
  required DocumentReference ref,
  required Map<String, dynamic> data,
  DateTime? occurrenceDay,
}) async {
  final title = ((data['chore'] ?? data['title']) as String? ?? '').trim();
  final recurring = choreIsRecurring(data);
  final day = occurrenceDay == null
      ? null
      : DateTime(occurrenceDay.year, occurrenceDay.month, occurrenceDay.day);

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(recurring ? 'Ta bort återkommande syssla?' : 'Ta bort syssla?'),
      content: Text(recurring
          ? '"$title" upprepas (${recurrenceLabel(data).toLowerCase()}).'
          : '"$title" tas bort. Det här går inte att ångra.'),
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
        if (recurring && day != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'single'),
            child: Text(baraDagEtikett(day, DateTime.now())),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'all'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
          child: Text(recurring ? 'Alla gånger' : 'Ta bort'),
        ),
      ],
    ),
  );
  if (choice == null) return false;

  try {
    if (choice == 'single' && day != null) {
      await ref.update({
        'recurrence.exceptions': FieldValue.arrayUnion([dateKey(day)]),
      });
      await NotificationService.cancelChoreInstance(ref.id, day);
    } else {
      await ref.delete();
      await NotificationService.cancelChoreReminders(ref.id, data);
    }
    if (context.mounted) showVardagSnack(context, 'Borttagen.');
    return true;
  } catch (e, stack) {
    developer.log('Kunde inte ta bort syssla', error: e, stackTrace: stack);
    if (context.mounted) {
      showVardagSnack(context, 'Kunde inte ta bort: $e', isError: true);
    }
    return false;
  }
}
