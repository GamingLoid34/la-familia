// Local-only cross-account SDK test. Run with:
// flutter test --platform chrome --dart-define=PRIVATE_EVENT_PILOT=true \
//   --dart-define=PRIVATE_BROWSER_TEST=true test/browser/private_activity_web_sdk.dart
// Uses only demo-vardag-privacy at 127.0.0.1:9180 / :8280.
// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/utils/private_activity.dart';

Future<void> waitUntil(bool Function() test) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw StateError('Local emulator result timed out.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'owner overlay, account switch, server protection and shared display',
    () async {
      FirebaseCoreWeb.registerWith(Registrar());
      FirebaseFirestoreWeb.registerWith(Registrar());
      FirebaseAuthWeb.registerWith(Registrar());
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'local-demo-key',
          appId: '1:123:web:privacy',
          messagingSenderId: '123',
          projectId: 'demo-vardag-privacy',
          authDomain: 'demo-vardag-privacy.firebaseapp.com',
        ),
      );
      final auth = FirebaseAuth.instance;
      await auth.useAuthEmulator('127.0.0.1', 9180);
      final db = FirebaseFirestore.instance;
      db.useFirestoreEmulator('127.0.0.1', 8280);
      final random = DateTime.now().microsecondsSinceEpoch;
      final parentEmail = 'parent-$random@example.invalid';
      final otherEmail = 'other-$random@example.invalid';
      const password = 'LocalTestOnly123!';
      final parent = (await auth.createUserWithEmailAndPassword(
        email: parentEmail,
        password: password,
      )).user!;
      final parentUid = parent.uid;
      final family = 'privacy-$random';
      await db.collection('families').doc(family).set({'createdBy': parentUid});
      await db.collection('users').doc(parentUid).set({
        'name': 'Alex',
        'role': 'admin',
        'familyId': family,
      });
      final other = (await auth.createUserWithEmailAndPassword(
        email: otherEmail,
        password: password,
      )).user!;
      final otherUid = other.uid;
      await auth.signInWithEmailAndPassword(
        email: parentEmail,
        password: password,
      );
      await db.collection('users').doc(otherUid).set({
        'name': 'Robin',
        'role': 'parent',
        'familyId': family,
      });

      final markerRef = db.collection('planner_events').doc();
      final detailsRef = db
          .collection('private_activities')
          .doc(parentUid)
          .collection('events')
          .doc(markerRef.id);
      final full = <String, dynamic>{
        'familyId': family,
        'date': '2026-11-09',
        'time': '09:30',
        'title': 'Bara Alex ser detta',
        'piktogram': '🏥',
        'checklist': [
          {'item': 'Privat rad'},
        ],
      };
      await (db.batch()
            ..set(markerRef, privateMarker(full, parentUid, 'Alex'))
            ..set(detailsRef, privateDetail(full, parentUid)))
          .commit();
      final raw = (await markerRef.get(
        const GetOptions(source: Source.server),
      )).data()!;
      expect(raw['title'], 'Privat');
      expect(raw.toString(), isNot(contains('Alex ser detta')));

      final provider = FamilyProvider();
      await waitUntil(() => provider.currentUser?.uid == parentUid);
      final retained =
          (await provider
                  .plannerEvents()
                  .where('familyId', isEqualTo: family)
                  .get(const GetOptions(source: Source.server)))
              .docs
              .single;
      await waitUntil(() => retained.data()['title'] == 'Bara Alex ser detta');
      expect(publicActivityData(retained.data())['title'], 'Privat');
      await auth.signInWithEmailAndPassword(
        email: otherEmail,
        password: password,
      );
      // The same retained document must stop yielding another account's text immediately.
      expect(retained.data()['title'], 'Privat');
      await waitUntil(() => provider.currentUser?.uid == otherUid);
      expect(retained.data()['title'], 'Privat');
      await expectLater(
        detailsRef.get(const GetOptions(source: Source.server)),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      await auth.signInWithEmailAndPassword(
        email: parentEmail,
        password: password,
      );
      await waitUntil(
        () =>
            provider.currentUser?.uid == parentUid &&
            retained.data()['title'] == 'Bara Alex ser detta',
      );
      provider.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: !const bool.fromEnvironment('PRIVATE_BROWSER_TEST'),
  );
}
