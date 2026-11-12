import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'activity_receipts.dart';

Future<void> deleteSeries(DocumentReference ref, Map<String, dynamic> data) async {
  final linked = (data['detachedOccurrences'] as Map?)?.values.cast<String>().toList() ?? <String>[];
  await ActivityReceipts.track(family: data['familyId'] as String, title: data['title'] as String? ?? 'Aktivitet',
    ids: [ref.id, ...linked], kind: 'delete', operation: (_) async {
      final initial = (await ref.get(const GetOptions(source: Source.server))).data() as Map?;
      if (initial == null) throw StateError('Aktiviteten finns inte längre.');
      final linkedDocs = initial['recurrence'] == null ? <QueryDocumentSnapshot>[] :
        (await ref.parent.where('familyId', isEqualTo: initial['familyId']).where('originalSeriesId', isEqualTo: ref.id)
          .get(const GetOptions(source: Source.server))).docs;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final current = await tx.get(ref);
        final raw = current.data() as Map?;
        if (raw == null) throw StateError('Aktiviteten finns inte längre.');
        if (!mapEquals(raw['detachedOccurrences'] as Map?, initial['detachedOccurrences'] as Map?)) throw StateError('Serien ändrades. Öppna kalendern igen.');
        if (linkedDocs.length >= 400) throw StateError('För många flyttade tillfällen för en atomisk radering.');
        for (final linked in linkedDocs) { tx.delete(linked.reference); }
        tx.delete(ref);
      });
    });
}
Future<void> undoOccurrence(DocumentReference ref, Map<String, dynamic> data) async {
  await ActivityReceipts.track(family: data['familyId'] as String, title: data['title'] as String? ?? 'Aktivitet',
    ids: [ref.id], kind: 'delete', operation: (_) async {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final current = (await tx.get(ref)).data() as Map?;
        if (current == null) throw StateError('Tillfället finns inte längre.');
        final day = current['originalOccurrenceDate'] as String;
        final source = ref.parent.doc(current['originalSeriesId'] as String);
        final series = (await tx.get(source)).data() as Map?;
        if ((series?['detachedOccurrences'] as Map?)?[day] != ref.id) throw StateError('Serien har ändrats eller tagits bort.');
        tx.update(source, {'recurrence.exceptions': FieldValue.arrayRemove([day]), 'detachedOccurrences.$day': FieldValue.delete()});
        tx.delete(ref);
      });
    });
}
