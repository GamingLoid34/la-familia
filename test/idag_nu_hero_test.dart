// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/screens/display/display_module_registry.dart';
import 'package:la_familia/screens/display/modules/idag_nu_module.dart';
import 'package:provider/provider.dart';

class MockDocSnapshot implements QueryDocumentSnapshot {
  @override
  final String id;
  final Map<String, dynamic> _data;

  MockDocSnapshot(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFamilyProvider extends ChangeNotifier implements FamilyProvider {
  @override
  final UserModel? currentUser;
  @override
  final List<UserModel> familyMembers;
  @override
  final List<QueryDocumentSnapshot> todayEvents;
  @override
  final List<QueryDocumentSnapshot> tomorrowEvents;
  @override
  final List<QueryDocumentSnapshot> chores;

  FakeFamilyProvider({
    this.currentUser,
    this.familyMembers = const [],
    this.todayEvents = const [],
    this.tomorrowEvents = const [],
    this.chores = const [],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('sv_SE', null);
  });

  final emilio = const UserModel(
    uid: 'u_emilio',
    familyId: 'fam1',
    name: 'Emilio Svensson',
    email: 'emilio@test.com',
    role: 'child',
    viewMode: 'child',
    energy: 3,
    color: '#4CAF50',
  );

  final mamma = const UserModel(
    uid: 'u_mamma',
    familyId: 'fam1',
    name: 'Mamma Anna',
    email: 'anna@test.com',
    role: 'parent',
    viewMode: 'parent',
    energy: 3,
    color: '#E91E63',
  );

  final members = [mamma, emilio];

  testWidgets('PIN-TEST: now 11:00, händelser 17:00 (Emilio) och 18:00 -> heron visar 17:00 med "om 6 timmar"', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final now = DateTime(2026, 9, 10, 11, 0);

    final event17 = MockDocSnapshot('ev_17', {
      'title': 'Fotbollsträning',
      'time': '17:00',
      'piktogram': '⚽',
      'date': '2026-08-01', // Återkommande med startdatum i dåtid
      'isRecurring': true,
      'personUid': emilio.uid,
      'personName': emilio.name,
      'persons': ['Emilio Svensson'],
    });

    final event18 = MockDocSnapshot('ev_18', {
      'title': 'Gitarreffekt',
      'time': '18:00',
      'piktogram': '🎸',
      'date': '2026-09-10',
      'isRecurring': false,
    });

    final fakeProvider = FakeFamilyProvider(
      currentUser: mamma,
      familyMembers: members,
      todayEvents: [event17, event18],
    );

    final moduleContext = DisplayModuleContext(
      now: now,
      weekStart: DateTime(2026, 9, 7),
      members: members,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<FamilyProvider>.value(
        value: fakeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1920,
              height: 1080,
              child: IdagNuModule(moduleContext: moduleContext),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Verifiera att heron hittade 17:00-händelsen (Emilio)
    // formatCountdownMinutes(360) -> "om 6 timmar"
    // Title, piktogram och Emilio ska finnas i hjälten
    expect(find.textContaining('Härnäst om 6 timmar'), findsOneWidget);
    expect(find.text('om 6 timmar'), findsOneWidget); // badge på kortet
    expect(find.textContaining('Fotbollsträning'), findsWidgets);
    expect(find.textContaining('(Emilio)'), findsOneWidget);
  });

  testWidgets('Hero fångar upp kommande händelse sent på kvällen fram till midnatt', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final now = DateTime(2026, 9, 10, 11, 0);

    final lateEvent = MockDocSnapshot('ev_late', {
      'title': 'Kvällsmöte',
      'time': '22:30',
      'piktogram': '🌙',
      'date': '2026-09-10',
    });

    final fakeProvider = FakeFamilyProvider(
      currentUser: mamma,
      familyMembers: members,
      todayEvents: [lateEvent],
    );

    final moduleContext = DisplayModuleContext(
      now: now,
      weekStart: DateTime(2026, 9, 7),
      members: members,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<FamilyProvider>.value(
        value: fakeProvider,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1920,
              height: 1080,
              child: IdagNuModule(moduleContext: moduleContext),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // diff = 11 timmar och 30 min (690 min) -> om 12 timmar
    expect(find.textContaining('Härnäst om 12 timmar'), findsOneWidget);
    expect(find.text('om 12 timmar'), findsOneWidget); // badge på kortet
    expect(find.textContaining('Kvällsmöte'), findsWidgets);
  });
}
