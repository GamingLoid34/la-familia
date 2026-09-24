import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import '../utils/recurrence.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/vardag_header.dart';
import 'aterkommande_lista.dart';

/// Delad hantering av menyval ('edit' eller 'delete') för en aktivitet.
///
/// [listDay] är den förekomst användaren tittar på (radens datum), inte
/// seriens startdag eller veckans måndag. "Bara denna gång" lägger just det
/// datumet som undantag. Returnerar true när något togs bort.
Future<bool> handleEventMenuAction(
  BuildContext context, {
  required String action, // 'edit' | 'delete'
  required QueryDocumentSnapshot doc,
  required DateTime listDay,
  required List<UserModel> familyMembers,
  required String familyId,
}) async {
  if (action == 'edit') {
    await openActivityEditor(context,
        doc: doc, familyMembers: familyMembers, familyId: familyId);
    return false;
  }
  if (action != 'delete') return false;
  return deleteActivity(context, doc: doc, occurrenceDay: listDay);
}

/// Öppnar det gemensamma aktivitetsformuläret förifyllt för [doc].
Future<void> openActivityEditor(
  BuildContext context, {
  required QueryDocumentSnapshot doc,
  required List<UserModel> familyMembers,
  required String familyId,
}) async {
  final d = doc.data() as Map<String, dynamic>;
  final day = parseDate(d['date']) ?? DateTime.now();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => AddEventSheet(
      selectedDay: day,
      familyMembers: familyMembers,
      familyId: familyId.isEmpty ? null : familyId,
      eventToEdit: doc,
    ),
  );
}

/// Ta bort en aktivitet. En återkommande aktivitet frågar om rätt enskilt
/// datum ("Bara i morgon", "Bara tisdag 29 sep" …) eller alla gånger.
/// Påminnelser avbokas. Ett misslyckat försök visas för användaren.
Future<bool> deleteActivity(
  BuildContext context, {
  required QueryDocumentSnapshot doc,
  required DateTime occurrenceDay,
}) async {
  final d = doc.data() as Map<String, dynamic>;
  final title = (d['title'] as String? ?? '').trim();
  final isRecurring = d['recurrence'] != null;
  final day = DateTime(occurrenceDay.year, occurrenceDay.month, occurrenceDay.day);

  String? choice;
  if (isRecurring) {
    choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort återkommande aktivitet?'),
        content: Text(
            '"$title" upprepas (${recurrenceLabel(d).toLowerCase()}). Vill du ta bort ett tillfälle eller alla gånger?'),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'single'),
            child: Text(baraDagEtikett(day, DateTime.now())),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            child: const Text('Alla gånger'),
          ),
        ],
      ),
    );
  } else {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort aktivitet?'),
        content: Text(title.isEmpty
            ? 'Det här går inte att ångra.'
            : '"$title" tas bort. Det här går inte att ångra.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (ok == true) choice = 'all';
  }
  if (choice == null) return false;

  try {
    if (choice == 'single') {
      // Bara undantagslistan ändras (arrayUnion) — ingen annan del av serien.
      await doc.reference.update({
        'recurrence.exceptions': FieldValue.arrayUnion([dateKey(day)]),
      });
      await NotificationService.cancelActivityInstance(doc.id, day);
      if (context.mounted) {
        showVardagSnack(context, 'Borttagen ${baraDagEtikett(day, DateTime.now()).replaceFirst('Bara ', '')}.');
      }
    } else {
      await doc.reference.delete();
      await NotificationService.cancelActivityReminders(doc.id, d);
      if (context.mounted) showVardagSnack(context, 'Borttagen.');
    }
    return true;
  } catch (e, stack) {
    developer.log('Kunde inte ta bort aktivitet', error: e, stackTrace: stack);
    if (context.mounted) {
      showVardagSnack(context, 'Kunde inte ta bort: $e', isError: true);
    }
    return false;
  }
}
