// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/screens/display/display_chips.dart';
import 'package:la_familia/screens/display/display_module_registry.dart';
import 'package:la_familia/screens/display/modules/persondag_module.dart';
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

  final List<UserModel> testMembers = [
    const UserModel(
      uid: 'u1',
      familyId: 'fam1',
      name: 'Mamma Anna',
      email: 'anna@test.com',
      role: 'parent',
      viewMode: 'parent',
      energy: 3,
      color: '#E91E63',
    ),
    const UserModel(
      uid: 'u2',
      familyId: 'fam1',
      name: 'Pappa Erik',
      email: 'erik@test.com',
      role: 'parent',
      viewMode: 'parent',
      energy: 3,
      color: '#2196F3',
    ),
    const UserModel(
      uid: 'u3',
      familyId: 'fam1',
      name: 'Lisa',
      email: 'lisa@test.com',
      role: 'child',
      viewMode: 'child',
      energy: 3,
      color: '#4CAF50',
    ),
  ];

  final testDate = DateTime(2026, 9, 9, 10, 0); // onsdag

  Widget buildTestWidget({
    required int? spotlightIndex,
    List<QueryDocumentSnapshot> todayEvents = const [],
    List<QueryDocumentSnapshot> tomorrowEvents = const [],
    List<QueryDocumentSnapshot> chores = const [],
    Size size = const Size(1920, 1080),
  }) {
    final fakeProvider = FakeFamilyProvider(
      currentUser: testMembers.first,
      familyMembers: testMembers,
      todayEvents: todayEvents,
      tomorrowEvents: tomorrowEvents,
      chores: chores,
    );

    final moduleContext = DisplayModuleContext(
      now: testDate,
      weekStart: DateTime(2026, 9, 7),
      members: testMembers,
      spotlightIndex: spotlightIndex,
    );

    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<FamilyProvider>.value(
          value: fakeProvider,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: PersondagModule(moduleContext: moduleContext),
          ),
        ),
      ),
    );
  }

  group('FAS 5.2 — PersondagModule', () {
    testWidgets(
      '1. Renderar platshållare vid saknat spotlightIndex utan krasch',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(spotlightIndex: null));
        await tester.pump();

        expect(
          find.textContaining('Välj en person: Shift + 1..N'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Tillgängliga personer: 1: Mamma, 2: Pappa, 3: Lisa',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2. Renderar platshållare vid ogiltigt spotlightIndex (> medlemmar) utan krasch',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(spotlightIndex: 5));
        await tester.pump();

        expect(
          find.textContaining('Välj en person: Shift + 1..N'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '3. Renderar personens dag med avatar, namn, närvaro, aktiviteter och sysslor',
      (tester) async {
        final todayEvents = [
          MockDocSnapshot('evt1', {
            'title': 'Styrelsemöte',
            'date': '2026-09-09',
            'time': '11:00',
            'endTime': '12:00',
            'piktogram': '💼',
            'personUids': ['u1'],
          }),
          MockDocSnapshot('evt2', {
            'title': 'Fredagsmys hela familjen',
            'date': '2026-09-09',
            'time': '18:00',
            'piktogram': '🍿',
            'personUids': ['u1', 'u2', 'u3'],
          }),
        ];

        final chores = [
          MockDocSnapshot('c1', {
            'title': 'Vattna blommor',
            'whoUid': 'u1',
            'isDone': true,
          }),
          MockDocSnapshot('c2', {
            'title': 'Bädda sängen',
            'whoUid': 'u1',
            'isDone': false,
          }),
        ];

        final tomorrowEvents = [
          MockDocSnapshot('tom1', {
            'title': 'Fotbollsträning',
            'date': '2026-09-10',
            'time': '17:30',
            'piktogram': '⚽',
            'personUids': ['u1'],
          }),
        ];

        await tester.pumpWidget(
          buildTestWidget(
            spotlightIndex: 1, // Mamma Anna
            todayEvents: todayEvents,
            tomorrowEvents: tomorrowEvents,
            chores: chores,
          ),
        );
        await tester.pump();

        // Namn och närvaro
        expect(find.text('Mamma Anna'), findsOneWidget);
        expect(find.text('Hemma'), findsOneWidget);

        // Aktiviteter
        expect(find.text('Styrelsemöte'), findsOneWidget);
        expect(find.text('Fredagsmys hela familjen'), findsOneWidget);

        // Sysslor
        expect(find.textContaining('✅ Vattna blommor'), findsOneWidget);
        expect(find.textContaining('⬜ Bädda sängen'), findsOneWidget);

        // Morgondagens rad
        expect(
          find.textContaining('Imorgon: ⚽ Fotbollsträning 17:30'),
          findsOneWidget,
        );
      },
    );

    testWidgets('4. Tom dag visar ledig-text och inga sysslor', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          spotlightIndex: 3, // Lisa
          todayEvents: [],
          tomorrowEvents: [],
          chores: [],
        ),
      );
      await tester.pump();

      expect(find.text('Lisa'), findsOneWidget);
      expect(find.text('Inga planer idag — lediiigt! 🎉'), findsOneWidget);
      expect(find.text('Inga sysslor idag'), findsOneWidget);
      expect(find.text('Imorgon: ledig dag'), findsOneWidget);
    });

    testWidgets('5. DisplayActivityCard och DisplayRamPlate stöder isLarge', (
      tester,
    ) async {
      final card = DisplayActivityCard(
        data: const {
          'title': 'Stor aktivitet',
          'time': '14:00',
          'piktogram': '🎾',
        },
        memberColor: Colors.blue,
        isLarge: true,
      );

      final plate = const DisplayRamPlate(
        piktogram: '🏫',
        label: 'Skola',
        time: '8:15–14:00',
        text: '🏫 · Skola · 8:15–14:00',
        memberColor: Colors.purple,
        isLarge: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Column(children: [card, plate])),
        ),
      );
      await tester.pump();

      expect(find.text('Stor aktivitet'), findsOneWidget);
      expect(find.text('Skola'), findsOneWidget);
      expect(find.text(' · 08:15–14:00'), findsOneWidget);
    });
  });
}
