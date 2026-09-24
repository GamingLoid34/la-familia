import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/note_model.dart';
import 'notification_service.dart';
import 'task_service.dart';

/// Firestore-åtkomst för Inkorgens anteckningar (`notes`), som Androids
/// `NoteRepositoryImpl`. Bara för förälder/admin.
///
/// Integritet: en fråga på bara `familyId` skulle träffa andras privata
/// anteckningar och nekas i sin helhet. Därför ställs alltid två frågor —
/// familjens gemensamma och mina egna — och resultaten slås ihop.
/// Reglerna släpper aldrig igenom något som inte får läsas, så ingen
/// efterfiltrering av otillåten data behövs (eller görs).
class NoteService {
  NoteService._();

  static const _uuid = Uuid();

  static CollectionReference<Map<String, dynamic>> get _notes =>
      FirebaseFirestore.instance.collection('notes');

  static Query<Map<String, dynamic>> _shared(String familyId) => _notes
      .where('familyId', isEqualTo: familyId)
      .where('visibility', isEqualTo: NoteModel.visibilityFamily);

  static Query<Map<String, dynamic>> _mine(String familyId, String uid) =>
      _notes
          .where('familyId', isEqualTo: familyId)
          .where('ownerUid', isEqualTo: uid);

  /// Alla anteckningar användaren får läsa, nyast först. Mjukraderade tas
  /// med — anroparen filtrerar på [NoteModel.isDeleted]. Publiceras först när
  /// båda frågorna svarat, så att listan inte blinkar till halvfärdig.
  static Stream<List<NoteModel>> observe(String familyId, String uid) {
    if (familyId.isEmpty || uid.isEmpty) return Stream.value(const []);
    late final StreamController<List<NoteModel>> controller;
    StreamSubscription? a;
    StreamSubscription? b;
    List<NoteModel>? shared;
    List<NoteModel>? mine;

    void publish() {
      if (shared == null || mine == null) return;
      controller.add(mergeNotes(shared!, mine!));
    }

    controller = StreamController<List<NoteModel>>(
      onListen: () {
        a = _shared(familyId).snapshots().listen((s) {
          shared = s.docs.map((d) => NoteModel.fromMap(d.id, d.data())).toList();
          publish();
        }, onError: controller.addError);
        b = _mine(familyId, uid).snapshots().listen((s) {
          mine = s.docs.map((d) => NoteModel.fromMap(d.id, d.data())).toList();
          publish();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
      },
    );
    return controller.stream;
  }

  /// Slår ihop de två frågornas svar: unika id, nyast först. En anteckning
  /// vars serverstämpel inte kommit än (`createdAt == null`) ligger överst.
  static List<NoteModel> mergeNotes(List<NoteModel> a, List<NoteModel> b) {
    final byId = <String, NoteModel>{};
    for (final n in [...a, ...b]) {
      byId.putIfAbsent(n.id, () => n);
    }
    final out = byId.values.toList()
      ..sort((x, y) {
        final xs = x.createdAt?.millisecondsSinceEpoch ?? 1 << 62;
        final ys = y.createdAt?.millisecondsSinceEpoch ?? 1 << 62;
        return ys.compareTo(xs);
      });
    return out;
  }

  /// Sparar en ny anteckning. Servern börjar tolka den direkt.
  static Future<String> add({
    required String familyId,
    required String ownerUid,
    required String text,
    required bool isPrivate,
    List<String> aboutUids = const [],
  }) async {
    final trimmed = text.trim();
    final ref = await _notes.add({
      'familyId': familyId,
      'ownerUid': ownerUid,
      'visibility':
          isPrivate ? NoteModel.visibilityPrivate : NoteModel.visibilityFamily,
      'text': trimmed,
      'contentHash': NoteContentHash.of(trimmed),
      'aboutUids': aboutUids,
      'status': NoteModel.statusSaved,
      'requestId': _uuid.v4(),
      'linkedIds': const [],
      'createdByUid': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Samma text bland anteckningar användaren får läsa. En annan förälders
  /// privata anteckning med samma text ger ingen träff.
  static Future<List<NoteModel>> findDuplicates({
    required String familyId,
    required String uid,
    required String text,
  }) async {
    final hash = NoteContentHash.of(text);
    if (hash == null) return const [];
    final results = await Future.wait([
      _shared(familyId).where('contentHash', isEqualTo: hash).limit(5).get(),
      _mine(familyId, uid).where('contentHash', isEqualTo: hash).limit(5).get(),
    ]);
    final merged = mergeNotes(
      results[0].docs.map((d) => NoteModel.fromMap(d.id, d.data())).toList(),
      results[1].docs.map((d) => NoteModel.fromMap(d.id, d.data())).toList(),
    );
    return merged.where((n) => !n.isDeleted).toList();
  }

  /// Be servern tolka om: ny `requestId` med status `saved`.
  static Future<void> requestInterpretation(String noteId) =>
      _notes.doc(noteId).update({
        'status': NoteModel.statusSaved,
        'requestId': _uuid.v4(),
      });

  /// Ingen hård radering finns — `deletedAt` tar anteckningen ur allt aktivt.
  static Future<void> softDelete(String noteId) =>
      _notes.doc(noteId).update({'deletedAt': FieldValue.serverTimestamp()});

  static Future<void> setValidity(
    String noteId, {
    String? validFrom,
    String? validTo,
  }) =>
      _notes.doc(noteId).update({'validFrom': validFrom, 'validTo': validTo});

  /// Bekräftar valda förslag. [revision] måste vara den tolkning användaren
  /// såg; servern avvisar annars med "Förslagen har uppdaterats…".
  static Future<ConfirmResult> confirmActions({
    required String noteId,
    required int revision,
    required List<String> actionIds,
  }) async {
    final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('confirmNoteActions')
        .call<Object?>({
      'noteId': noteId,
      'revision': revision,
      'actionIds': actionIds,
    });
    return ConfirmResult.fromResponse(res.data);
  }

  /// Ändring: en ny anteckning skapas först, sedan mjukraderas den gamla.
  /// Originaltexten skrivs aldrig över. Oförändrat ⇒ ingenting skrivs.
  /// Returnerar [EditOutcome] så att anroparen kan berätta sanningsenligt
  /// om något gick halvvägs.
  static Future<EditOutcome> editNote(
    NoteModel note, {
    required String text,
    required bool isPrivate,
    required List<String> aboutUids,
  }) async {
    if (NoteEdit.isUnchanged(note,
        text: text, isPrivate: isPrivate, aboutUids: aboutUids)) {
      return EditOutcome.unchanged;
    }
    await add(
      familyId: note.familyId,
      ownerUid: note.ownerUid.isNotEmpty ? note.ownerUid : note.createdByUid,
      text: text,
      isPrivate: isPrivate,
      aboutUids: aboutUids,
    );
    try {
      await softDelete(note.id);
    } catch (_) {
      return EditOutcome.oldNotRemoved;
    }
    return EditOutcome.replaced;
  }

  /// Tar bort anteckningen och det som skapats UR den (Androids
  /// `deleteWithCreated`). Bara poster vars `sourceNoteId` är exakt den här
  /// anteckningen tas bort — en aktivitet som anteckningen bara kompletterat
  /// med en packlisterad eller ett undantag rörs inte. Avbryts något steg
  /// mjukraderas inte anteckningen, så ett nytt försök är säkert.
  /// Returnerar antalet borttagna poster.
  static Future<int> deleteWithCreated(NoteModel note) async {
    var removed = 0;
    if (note.familyId.isNotEmpty) {
      for (final t in await TaskService.fromNote(note.familyId, note.id)) {
        await TaskService.delete(t.id);
        removed++;
      }
      final events = await FirebaseFirestore.instance
          .collection('planner_events')
          .where('familyId', isEqualTo: note.familyId)
          .where('sourceNoteId', isEqualTo: note.id)
          .get();
      for (final e in events.docs) {
        await NotificationService.cancelActivityReminders(e.id, e.data());
        await e.reference.delete();
        removed++;
      }
    }
    await softDelete(note.id);
    return removed;
  }
}

enum EditOutcome { unchanged, replaced, oldNotRemoved }
