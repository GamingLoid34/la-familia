// Sessionskontrollen som formuläret och uppspelningen delar: Firebase-uid,
// providerns uid och providerns familj.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/utils/checklist_updates.dart';
import 'package:la_familia/utils/pending_checklist_edits.dart';
import 'package:la_familia/utils/session_guard.dart';

class _MemStore implements ChecklistEditStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async => value = v;
  List<PendingChecklistEdit> get entries => PendingChecklistEdit.decodeAll(value);
}

UserModel _user(String uid, String familyId) => UserModel(
      uid: uid, name: uid, email: '$uid@test', color: 'ff2A6F97',
      role: 'parent', viewMode: 'parent', energy: 3, familyId: familyId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FamilyProvider provider;
  var authUid = 'anna';

  setUp(() {
    authUid = 'anna';
    provider = FamilyProvider.fixed(currentUser: _user('anna', 'fam'));
  });
  tearDown(() => provider.dispose());

  bool Function() guard() => sessionGuard(
      uid: 'anna', familyId: 'fam', provider: provider, authUid: () => authUid);

  group('sessionGuard', () {
    test('samma session är aktiv', () => expect(guard()(), isTrue));

    test('annat Firebase-uid är inte aktivt', () {
      final g = guard();
      authUid = 'bo';
      expect(g(), isFalse);
    });

    test('annan användare i providern är inte aktiv', () {
      final g = guard();
      provider.debugSetCurrentUser(_user('bo', 'fam'));
      expect(g(), isFalse);
    });

    test('familjebyte med oförändrat uid är inte aktivt', () {
      final g = guard();
      provider.debugSetCurrentUser(_user('anna', 'ny'));
      expect(g(), isFalse);
    });

    test('utloggad är inte aktiv', () {
      final g = guard();
      provider.debugSetCurrentUser(null);
      expect(g(), isFalse);
    });
  });

  group('Vanlig sparning medan familjen byts (oförändrat uid)', () {
    late _MemStore store;
    late Completer<void> gate;
    late PendingChecklistEdits queue;

    setUp(() {
      store = _MemStore();
      gate = Completer<void>();
      queue = PendingChecklistEdits(
        store: store,
        newId: () => 'op1',
        // Servern väntar och nekar sedan (som reglerna gör för fel familj).
        server: (_, _, _) async {
          await gate.future;
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        },
      );
    });

    Future<ChecklistSaveOutcome> save() => queue.save(
          eventId: 'e1',
          uid: 'anna',
          familyId: 'fam',
          originalRows: const ['Benskydd'],
          editedRows: const [PacklistRad('Benskydd höger', ursprungIndex: 0)],
          stillActive: guard(),
        );

    test('behörighetsfel efter familjebytet behåller köposten', () async {
      final saving = save();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      provider.debugSetCurrentUser(_user('anna', 'ny')); // samma uid, ny familj
      gate.complete();

      expect(await saving, ChecklistSaveOutcome.queued);
      final kvar = store.entries.single;
      expect((kvar.eventId, kvar.uid, kvar.familyId), ('e1', 'anna', 'fam'));
    });

    test('kontroll: utan familjebyte är samma fel permanent och posten tas bort',
        () async {
      final saving = save();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      gate.complete();
      await expectLater(saving, throwsA(isA<FirebaseException>()));
      expect(store.entries, isEmpty);
    });
  });
}
