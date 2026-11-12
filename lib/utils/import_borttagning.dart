import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/notification_service.dart';
import 'ics_summary.dart';

/// Tar bort en kalenderimport och exakt de händelser den skapade, och avbokar
/// deras lokala påminnelser. Används av borttagningen i importlistan och av
/// "Ångra" direkt efter en skannad import.
///
/// Manuella händelser påverkas inte: bara poster med `source: "calendar"` som
/// pekar på importen (eller, för äldre poster utan `calendarImportId`, har
/// samma `calendarName`) tas bort. Returnerar antalet borttagna händelser,
/// eller null när importen redan var borta.
Future<int?> taBortKalenderimport(String importId) async {
  final db = FirebaseFirestore.instance;
  final impRef = db.collection('calendar_imports').doc(importId);
  final impDoc = await impRef.get();
  if (!impDoc.exists) return null;
  final data = impDoc.data()!;
  final familyId = data['familyId'] as String? ?? '';
  final namn = data['name'] as String? ?? '';

  final eventsSnap = await db
      .collection('planner_events')
      .where('familyId', isEqualTo: familyId)
      .get();

  final borttagna = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  var batch = db.batch();
  var ops = 0;
  for (final d in eventsSnap.docs) {
    if (!hortTillImport(d.data(), importId: importId, importNamn: namn)) {
      continue;
    }
    batch.delete(d.reference);
    borttagna.add(d);
    ops++;
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
  await impRef.delete();

  await avbokaPaminnelser(borttagna);
  return borttagna.length;
}

/// Avbokar lokala påminnelser för borttagna händelser. Ett misslyckande här
/// ska inte få borttagningen att se misslyckad ut — posterna är redan borta.
Future<void> avbokaPaminnelser(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) async {
  for (final d in docs) {
    try {
      await NotificationService.cancelActivityReminders(d.id, d.data());
    } catch (e, stack) {
      developer.log(
        'Kunde inte avboka påminnelse för ${d.id}',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
