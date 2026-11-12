import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'activity_receipts.dart';

Future<void> deleteSeries(
  DocumentReference ref,
  Map<String, dynamic> data,
) async {
  final linked =
      (data['detachedOccurrences'] as Map?)?.values.cast<String>().toList() ??
      <String>[];
  await ActivityReceipts.track(
    family: data['familyId'] as String,
    title: data['title'] as String? ?? 'Aktivitet',
    ids: [ref.id, ...linked],
    kind: 'delete',
    operation: (_) async {
      final initial =
          (await ref.get(const GetOptions(source: Source.server))).data()
              as Map?;
      if (initial == null) throw StateError('Aktiviteten finns inte längre.');
      if (initial['visibility'] == 'private') {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || initial['privateOwnerUid'] != uid) {
          throw StateError('Bara ägaren kan ta bort aktiviteten.');
        }
        await _deletePrivate(ref.id, uid, initial);
        return;
      }
      final linkedDocs = initial['recurrence'] == null
          ? <QueryDocumentSnapshot>[]
          : (await ref.parent
                    .where('familyId', isEqualTo: initial['familyId'])
                    .where('originalSeriesId', isEqualTo: ref.id)
                    .get(const GetOptions(source: Source.server)))
                .docs;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final current = await tx.get(ref);
        final raw = current.data() as Map?;
        if (raw == null) throw StateError('Aktiviteten finns inte längre.');
        if (!mapEquals(
          raw['detachedOccurrences'] as Map?,
          initial['detachedOccurrences'] as Map?,
        )) {
          throw StateError('Serien ändrades. Öppna kalendern igen.');
        }
        if (linkedDocs.length >= 400) {
          throw StateError(
            'För många flyttade tillfällen för en atomisk radering.',
          );
        }
        for (final linked in linkedDocs) {
          tx.delete(linked.reference);
        }
        tx.delete(ref);
      });
    },
  );
}

Future<void> _deletePrivate(String id, String uid, Map initial) async {
  final db = FirebaseFirestore.instance;
  final events = db.collection('planner_events');
  final ref = events.doc(id);
  final details = db
      .collection('private_activities')
      .doc(uid)
      .collection('events');
  final sourceId = initial['originalSeriesId'];
  if (sourceId is String) {
    await db.runTransaction((tx) async {
      final target = (await tx.get(ref)).data();
      if (target == null) throw StateError('Tillfället finns inte längre.');
      final day = target['originalOccurrenceDate'] as String;
      final seriesRef = events.doc(sourceId);
      final series = (await tx.get(seriesRef)).data();
      if (target['privateOwnerUid'] != uid ||
          series?['privateOwnerUid'] != uid ||
          (series?['detachedOccurrences'] as Map?)?[day] != id) {
        throw StateError('Serien har ändrats eller tagits bort.');
      }
      tx.update(seriesRef, {'detachedOccurrences.$day': FieldValue.delete()});
      tx.delete(ref);
      tx.delete(details.doc(id));
    });
    return;
  }
  // Preserve atomic deletion for up to eight moved occurrences. Larger sets
  // are unlinked in bounded transactions before the final atomic deletion.
  while (true) {
    final finished = await db.runTransaction((tx) async {
      final current = (await tx.get(ref)).data();
      if (current == null) throw StateError('Aktiviteten finns inte längre.');
      if (current['privateOwnerUid'] != uid ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('Bara ägaren kan ta bort aktiviteten.');
      }
      final links = Map<String, dynamic>.from(
        current['detachedOccurrences'] as Map? ?? {},
      );
      if (links.values.any((value) => value is! String)) {
        throw StateError('Ogiltig länk till tillfälle.');
      }
      final finishing = links.length <= 8;
      final remove = finishing
          ? links.entries.toList()
          : links.entries.take(7).toList();
      if (finishing) {
        tx.delete(ref);
        tx.delete(details.doc(id));
      } else {
        tx.update(ref, {
          for (final entry in remove)
            'detachedOccurrences.${entry.key}': FieldValue.delete(),
        });
      }
      for (final entry in remove) {
        tx.delete(events.doc(entry.value as String));
        tx.delete(details.doc(entry.value as String));
      }
      return finishing;
    });
    if (finished) return;
  }
}

Future<void> undoOccurrence(
  DocumentReference ref,
  Map<String, dynamic> data,
) async {
  await ActivityReceipts.track(
    family: data['familyId'] as String,
    title: data['title'] as String? ?? 'Aktivitet',
    ids: [ref.id],
    kind: 'delete',
    operation: (_) async {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final current = (await tx.get(ref)).data() as Map?;
        if (current == null) throw StateError('Tillfället finns inte längre.');
        final day = current['originalOccurrenceDate'] as String;
        final source = ref.parent.doc(current['originalSeriesId'] as String);
        final series = (await tx.get(source)).data() as Map?;
        if ((series?['detachedOccurrences'] as Map?)?[day] != ref.id) {
          throw StateError('Serien har ändrats eller tagits bort.');
        }
        if (current['visibility'] == 'private') {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null ||
              current['privateOwnerUid'] != uid ||
              series?['privateOwnerUid'] != uid) {
            throw StateError('Bara ägaren kan ångra flytten.');
          }
          tx.delete(
            FirebaseFirestore.instance
                .collection('private_activities')
                .doc(uid)
                .collection('events')
                .doc(ref.id),
          );
        }
        tx.update(source, {
          'recurrence.exceptions': FieldValue.arrayRemove([day]),
          'detachedOccurrences.$day': FieldValue.delete(),
        });
        tx.delete(ref);
      });
    },
  );
}
