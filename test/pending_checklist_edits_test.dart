// Packlistekön (granskning 2026-09-25, omgång 2 och 3). Kön körs på riktigt
// — save och flush — med ersättningar för lagringen och servern.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/checklist_updates.dart';
import 'package:la_familia/utils/pending_checklist_edits.dart';

/// Lagring i minnet. [failWrites] kastar vid skrivning; [delay] gör varje
/// läsning/skrivning långsam, så att samtidiga operationer kan krocka om
/// kön inte serialiserades.
class MemStore implements ChecklistEditStore {
  String? value;
  bool failWrites = false;
  Duration delay = Duration.zero;

  @override
  Future<String?> read() async {
    final v = value;
    await Future<void>.delayed(delay);
    return v;
  }

  @override
  Future<void> write(String? v) async {
    await Future<void>.delayed(delay);
    if (failWrites) throw StateError('disken är full');
    value = v;
  }

  List<PendingChecklistEdit> get entries => PendingChecklistEdit.decodeAll(value);
}

/// Servern: varje anrop hämtar sitt svar ur [respond] (standard: lyckas).
class FakeServer {
  final calls = <String>[];
  Future<void> Function(String eventId) respond = (_) async {};

  Future<void> call(String eventId, List<dynamic> o, List<PacklistRad> e) {
    calls.add(eventId);
    return respond(eventId);
  }
}

FirebaseException _unavailable() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

final _original = <dynamic>[
  {'item': 'Benskydd', 'isDone': false, 'rowId': 'r1', 'addedAt': Timestamp.fromMillisecondsSinceEpoch(1000)},
  {'item': 'Vattenflaska', 'isDone': false},
  'Handduk',
];
final _edited = [
  const PacklistRad('Benskydd', ursprungIndex: 0),
  const PacklistRad('Vattenflaska 1 l', ursprungIndex: 1),
  const PacklistRad('Handduk', ursprungIndex: 2),
  const PacklistRad('Matsäck'),
];

void main() {
  late MemStore store;
  late FakeServer server;
  late PendingChecklistEdits queue;
  var ids = 0;

  setUp(() {
    store = MemStore();
    server = FakeServer();
    ids = 0;
    queue = PendingChecklistEdits(
      store: store,
      server: server.call,
      newId: () => 'op${++ids}',
      now: () => DateTime.fromMillisecondsSinceEpoch(ids * 1000),
    );
  });

  Future<ChecklistSaveOutcome> save(String eventId,
          {String uid = 'anna', String familyId = 'fam'}) =>
      queue.save(
        eventId: eventId,
        uid: uid,
        familyId: familyId,
        originalRows: _original,
        editedRows: _edited,
      );

  group('Lagringsformat', () {
    test('ägare, ursprung, index och radernas extra fält bevaras', () {
      final e = PendingChecklistEdit(
        opId: 'op1', eventId: 'e1', uid: 'anna', familyId: 'fam',
        createdAtMs: 5, original: _original, edited: _edited,
      );
      final back = PendingChecklistEdit.decodeAll(PendingChecklistEdit.encodeAll([e])).single;
      expect(back.uid, 'anna');
      expect(back.familyId, 'fam');
      expect(back.opId, 'op1');
      expect(back.edited, _edited);
      expect(back.original, _original);
      expect((back.original.first as Map)['addedAt'], isA<Timestamp>());
    });

    test('trasig lagring och poster utan ägare ger tom kö', () {
      expect(PendingChecklistEdit.decodeAll('{inte json'), isEmpty);
      expect(PendingChecklistEdit.decodeAll('[{"eventId":"e1"}]'), isEmpty);
    });

    test('Androids avbockning överlever uppspelning ur kön', () {
      final latest = <dynamic>[
        {'item': 'Benskydd', 'isDone': true, 'rowId': 'r1'},
        {'item': 'Vattenflaska', 'isDone': true},
        'Handduk',
      ];
      final merged = mergeChecklist(
          latestRows: latest, originalRows: _original, editedRows: _edited);
      expect(checklistIsDone(merged[0]), isTrue);
      expect(checklistTextOf(merged[1]), 'Vattenflaska 1 l');
      expect(checklistIsDone(merged[1]), isTrue);
      expect(checklistTextOf(merged.last), 'Matsäck');
    });
  });

  group('save', () {
    test('servern tar emot: bekräftad, kön tom', () async {
      expect(await save('e1'), ChecklistSaveOutcome.confirmed);
      expect(store.entries, isEmpty);
    });

    test('servern nås inte: köad, posten bunden till användare och familj', () async {
      server.respond = (_) async => throw _unavailable();
      expect(await save('e1'), ChecklistSaveOutcome.queued);
      final e = store.entries.single;
      expect((e.eventId, e.uid, e.familyId), ('e1', 'anna', 'fam'));
    });

    test('permanent fel: kastas och posten tas bort', () async {
      server.respond = (_) async => throw _denied();
      await expectLater(save('e1'), throwsA(isA<FirebaseException>()));
      expect(store.entries, isEmpty);
    });

    test('lagringsfel + servern nås inte: kastas, döljs inte', () async {
      store.failWrites = true;
      server.respond = (_) async => throw _unavailable();
      await expectLater(save('e1'), throwsA(isA<PacklistaEjSparad>()));
    });

    test('lagringsfel men servern tar emot: bekräftad', () async {
      store.failWrites = true;
      expect(await save('e1'), ChecklistSaveOutcome.confirmed);
    });
  });

  group('Kontobyte', () {
    test('nästa användare kör inte föregående användares ändringar', () async {
      server.respond = (_) async => throw _unavailable();
      await save('e1', uid: 'anna');
      server.calls.clear();
      // Bo loggar in; servern skulle neka honom (permanent fel).
      server.respond = (_) async => throw _denied();
      await queue.flush(uid: 'bo', familyId: 'fam');
      expect(server.calls, isEmpty, reason: 'Annas post rörs inte av Bo');
      expect(store.entries.single.uid, 'anna', reason: 'Annas ändring finns kvar');

      // Anna loggar in igen med nät: posten körs och tas bort.
      server.respond = (_) async {};
      await queue.flush(uid: 'anna', familyId: 'fam');
      expect(server.calls, ['e1']);
      expect(store.entries, isEmpty);
    });

    test('annan familj för samma användare körs inte', () async {
      server.respond = (_) async => throw _unavailable();
      await save('e1', familyId: 'gammal');
      server.calls.clear();
      server.respond = (_) async {};
      await queue.flush(uid: 'anna', familyId: 'ny');
      expect(server.calls, isEmpty);
      expect(store.entries, hasLength(1));
    });
  });

  group('Samtidighet', () {
    test('samtidiga köläggningar tappar ingen post', () async {
      store.delay = const Duration(milliseconds: 10);
      server.respond = (_) async => throw _unavailable();
      await Future.wait([save('e1'), save('e2'), save('e3')]);
      expect(store.entries.map((e) => e.eventId).toSet(), {'e1', 'e2', 'e3'});
    });

    test('pågående flush tar bara bort sin egen operation', () async {
      server.respond = (_) async => throw _unavailable();
      await save('e1'); // op1 köad
      final gate = Completer<void>();
      server.respond = (_) => gate.future; // op1:s uppspelning hänger
      final flushing = queue.flush(uid: 'anna', familyId: 'fam');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Under tiden: en nyare ändring för samma aktivitet köas (op2).
      server.respond = (_) async => throw _unavailable();
      expect(await save('e1'), ChecklistSaveOutcome.queued);

      gate.complete(); // op1 lyckas
      await flushing;
      final kvar = store.entries;
      expect(kvar.map((e) => e.opId), ['op2'],
          reason: 'den nyare ändringen får inte raderas');
    });

    test('flush körs äldst först och hoppar över operationer som pågår', () async {
      server.respond = (_) async => throw _unavailable();
      await save('e2');
      await save('e1');
      server.calls.clear();
      server.respond = (_) async {};
      await queue.flush(uid: 'anna', familyId: 'fam');
      expect(server.calls, ['e2', 'e1']);
    });

    test('permanent fel vid flush meddelas och tar bara bort den posten', () async {
      server.respond = (_) async => throw _unavailable();
      await save('e1');
      await save('e2');
      server.respond = (id) async {
        if (id == 'e1') throw const ChecklistChangedException('Aktiviteten finns inte längre.');
      };
      final meddelanden = <String>[];
      await queue.flush(uid: 'anna', familyId: 'fam', onFailed: meddelanden.add);
      expect(meddelanden.single, contains('Aktiviteten finns inte längre.'));
      expect(store.entries, isEmpty, reason: 'e2 lyckades, e1 släpptes');
    });
  });
}
