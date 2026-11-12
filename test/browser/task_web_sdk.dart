// Manuell körning: flutter test --platform chrome
// --dart-define=TASK_EMULATOR_TEST=true test/browser/task_web_sdk.dart
// Kräver Firestore-emulator med demo-vardag-task-sdk på 127.0.0.1:8197.
// Isolerad SDK-kontroll med öppna TEST-regler; säkerhetsregler provas separat.
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/planning_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'web SDK completes and reopens a task without losing attribution',
    () async {
      FirebaseCoreWeb.registerWith(Registrar());
      FirebaseFirestoreWeb.registerWith(Registrar());
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:123:web:demo',
          messagingSenderId: '123',
          projectId: 'demo-vardag-task-sdk',
        ),
      );
      final db = FirebaseFirestore.instance;
      db.useFirestoreEmulator('127.0.0.1', 8197);
      final ref = db.collection('tasks').doc('web-roundtrip');
      await ref.set({
        'title': 'Ta med matsäck',
        'status': 'open',
        'doneAt': null,
        'sourceNoteId': 'brev',
        'aboutUids': ['barn'],
      });
      await ref.update(
        PlanningTask.statusPatch(true, FieldValue.serverTimestamp()),
      );
      final done = (await ref.get(
        const GetOptions(source: Source.server),
      )).data()!;
      expect(done['status'], 'done');
      expect(done['doneAt'], isA<Timestamp>());
      expect(done['sourceNoteId'], 'brev');
      expect(done['aboutUids'], ['barn']);
      await ref.update(
        PlanningTask.statusPatch(false, FieldValue.serverTimestamp()),
      );
      expect((await ref.get()).data()!['doneAt'], isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: !const bool.fromEnvironment('TASK_EMULATOR_TEST'),
  );
}
