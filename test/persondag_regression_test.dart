// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/screens/display/display_chips.dart';
import 'package:la_familia/screens/display/display_log.dart';
import 'package:la_familia/screens/display/display_module_error_boundary.dart';
import 'package:la_familia/screens/display/display_module_registry.dart';
import 'package:la_familia/screens/display/display_palette.dart';
import 'package:la_familia/screens/display/display_school_menu_data.dart';
import 'package:la_familia/screens/display/modules/persondag_module.dart';
import 'package:la_familia/screens/display/modules/persondag_schema.dart';
import 'package:provider/provider.dart';

class _MockDocSnapshot implements QueryDocumentSnapshot {
  @override
  final String id;
  final Map<String, dynamic> _data;
  _MockDocSnapshot(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProvider extends ChangeNotifier implements FamilyProvider {
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
  @override
  final List<QueryDocumentSnapshot> todayMeals;

  _FakeProvider({
    this.currentUser,
    this.familyMembers = const [],
    this.todayEvents = const [],
    this.todayMeals = const [],
    this.chores = const [],
  }) : tomorrowEvents = const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('sv_SE', null);
    DisplayModuleErrorBoundary.initialize();
  });

  setUp(() {
    DisplayLog.instance.clear();
  });

  // Datum för schemadagen (måndag 2026-09-14)
  final testDay = DateTime(2026, 9, 14, 10, 0);

  // 1. Leandro fixture (Fröafallsskolan, 12 lektioner)
  final leandroMember = const UserModel(
    uid: 'uLeandro',
    familyId: 'fam1',
    name: 'Leandro',
    email: 'leandro@test.com',
    role: 'child',
    viewMode: 'child',
    energy: 3,
    color: '#E91E63',
  );

  final leandroEvents = [
    {"time": "08:25", "endTime": "08:45", "title": "Lektion Ombyte", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "08:45", "endTime": "09:30", "title": "Lektion idh", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "09:30", "endTime": "09:50", "title": "Lektion rast", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "09:50", "endTime": "10:50", "title": "Lektion sv", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "10:50", "endTime": "11:15", "title": "Lektion lunch", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "11:15", "endTime": "11:45", "title": "Lektion rast", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "11:45", "endTime": "12:15", "title": "Lektion sv", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "12:15", "endTime": "12:55", "title": "Lektion ma", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "12:55", "endTime": "13:10", "title": "Lektion rast", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "13:10", "endTime": "13:45", "title": "Lektion ma", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "13:45", "endTime": "14:00", "title": "Lektion rast", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
    {"time": "14:00", "endTime": "14:30", "title": "Lektion so", "planningImportKind": "schedule", "calendarName": "Leandro skolschema", "date": "2026-09-14", "personUids": ["uLeandro"]},
  ].map((m) => _MockDocSnapshot(m['title']! as String, m)).toList();

  // 2. Lionel fixture (Junkaremålsskolan, 9 lektioner)
  final lionelMember = const UserModel(
    uid: 'uLionel',
    familyId: 'fam1',
    name: 'Lionel',
    email: 'lionel@test.com',
    role: 'child',
    viewMode: 'child',
    energy: 3,
    color: '#4CAF50',
  );

  final lionelEvents = [
    {"time": "08:10", "endTime": "08:55", "title": "Lektion Sv/Sva", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "08:55", "endTime": "09:20", "title": "Lektion Rast", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "09:20", "endTime": "10:05", "title": "Lektion Mu", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "10:10", "endTime": "10:45", "title": "Lektion Ma", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "10:50", "endTime": "11:45", "title": "Lektion Lunch", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "11:50", "endTime": "12:35", "title": "Lektion Sl", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "12:35", "endTime": "12:50", "title": "Lektion Rast", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "12:50", "endTime": "13:25", "title": "Lektion Ma", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
    {"time": "13:30", "endTime": "14:15", "title": "Lektion So", "planningImportKind": "schedule", "calendarName": "Lionels schema", "date": "2026-09-14", "personUids": ["uLionel"]},
  ].map((m) => _MockDocSnapshot(m['title']! as String, m)).toList();

  // 3. Emilio fixture (Holavedsgymnasiet, 3 lektioner)
  final emilioMember = const UserModel(
    uid: 'uEmilio',
    familyId: 'fam1',
    name: 'Emilio',
    email: 'emilio@test.com',
    role: 'child',
    viewMode: 'child',
    energy: 3,
    color: '#2196F3',
  );

  final emilioEvents = [
    {"time": "09:20", "endTime": "11:15", "title": "Lektion Fysik", "planningImportKind": "schedule", "calendarName": "Emilios skolschema", "date": "2026-09-14", "personUids": ["uEmilio"]},
    {"time": "12:15", "endTime": "13:35", "title": "Lektion Engelska", "planningImportKind": "schedule", "calendarName": "Emilios skolschema", "date": "2026-09-14", "personUids": ["uEmilio"]},
    {"time": "13:45", "endTime": "15:00", "title": "Lektion Teknik", "planningImportKind": "schedule", "calendarName": "Emilios skolschema", "date": "2026-09-14", "personUids": ["uEmilio"]},
  ].map((m) => _MockDocSnapshot(m['title']! as String, m)).toList();

  // 4. Céline fixture (Universitet, 1 lektion)
  final celineMember = const UserModel(
    uid: 'uCeline',
    familyId: 'fam1',
    name: 'Céline',
    email: 'celine@test.com',
    role: 'child',
    viewMode: 'child',
    energy: 3,
    color: '#9C27B0',
  );

  final celineEvents = [
    {"time": "08:15", "endTime": "11:15", "title": "HARV1000X", "planningImportKind": "schedule", "calendarName": "Celine v38", "date": "2026-09-14", "personUids": ["uCeline"]},
  ].map((m) => _MockDocSnapshot(m['title']! as String, m)).toList();

  // 5. Noomi fixture (Rehab)
  final noomiMember = const UserModel(
    uid: 'uNoomi',
    familyId: 'fam1',
    name: 'Noomi',
    email: 'noomi@test.com',
    role: 'child',
    viewMode: 'child',
    energy: 3,
    color: '#FF9800',
  );

  final noomiEvents = [
    {"time": "09:00", "endTime": "10:00", "title": "Fysioterapi Rehab", "planningImportKind": "schedule", "calendarName": "Rehab", "piktogram": "🏥", "date": "2026-09-14", "personUids": ["uNoomi"]},
    {"time": "11:00", "endTime": "11:45", "title": "Bassängträning", "planningImportKind": "schedule", "calendarName": "Rehab", "piktogram": "🏊", "date": "2026-09-14", "personUids": ["uNoomi"]},
  ].map((m) => _MockDocSnapshot(m['title']! as String, m)).toList();

  // 6. Oscar fixture (Utan schema)
  final oscarMember = const UserModel(
    uid: 'uOscar',
    familyId: 'fam1',
    name: 'Oscar',
    email: 'oscar@test.com',
    role: 'child',
    viewMode: 'child',
    energy: 3,
    color: '#795548',
  );

  final oscarEvents = <QueryDocumentSnapshot>[];

  Future<void> pumpPersondag(
    WidgetTester tester, {
    required UserModel member,
    required List<QueryDocumentSnapshot> events,
    List<QueryDocumentSnapshot> chores = const [],
    List<QueryDocumentSnapshot> meals = const [],
    Size size = const Size(1920, 1080),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final provider = _FakeProvider(
      currentUser: member,
      familyMembers: [member],
      todayEvents: events,
      todayMeals: meals,
      chores: chores,
    );

    final moduleContext = DisplayModuleContext(
      now: testDay,
      weekStart: DateTime(2026, 9, 14),
      members: [member],
      spotlightIndex: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<FamilyProvider>.value(
            value: provider,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: PersondagModule(moduleContext: moduleContext),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('FAS 6d Regression — Anonymiserade fixturer från verklig schemadata', () {
    testWidgets('1. Leandro vid 1280x720 renderar kompakt listfallback (sum(min_i)=562 > H)', (tester) async {
      await pumpPersondag(
        tester,
        member: leandroMember,
        events: leandroEvents,
        size: const Size(1280, 720),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsOneWidget);
      expect(find.textContaining('08:25–14:30'), findsOneWidget);

      // Titeltvätt och expansion (inga "Lektion ", idh -> Idrott och hälsa, etc.)
      expect(find.text('Ombyte'), findsWidgets);
      expect(find.text('Idrott och hälsa'), findsOneWidget);
      expect(find.text('Svenska'), findsWidgets);
      expect(find.text('Matematik'), findsWidgets);

      // Verifiera att kompakt listfallback aktiverades på grund av sum(min_i) > H vid 1280x720
      expect(find.textContaining('till'), findsOneWidget);
    });

    testWidgets('1b. Leandro vid 1920x1080 renderar TIDSLINJE (sum(h_i) <= H, två kolumner, inte lista)', (tester) async {
      await pumpPersondag(
        tester,
        member: leandroMember,
        events: leandroEvents,
        size: const Size(1920, 1080),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsOneWidget);
      expect(find.textContaining('08:25–14:30'), findsOneWidget);

      // Titeltvätt och expansion
      expect(find.text('Idrott och hälsa'), findsOneWidget);
      expect(find.text('Svenska'), findsWidgets);
      expect(find.text('Matematik'), findsWidgets);

      // Verifiera att tidslinje renderas (INGEN kompakt listfallback)
      expect(find.textContaining('till'), findsNothing);
    });

    testWidgets('2. Lionel (Junkaremålsskolan) händelsesemantik ur tabellen (6 lektioner, raster, lunch)', (tester) async {
      await pumpPersondag(
        tester,
        member: lionelMember,
        events: lionelEvents,
        size: const Size(1920, 1080),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsOneWidget);
      expect(find.textContaining('08:10–14:15'), findsOneWidget);

      // Semantik och ämnesexpansion
      expect(find.text('Svenska'), findsOneWidget); // Sv/Sva -> Svenska
      expect(find.text('Musik'), findsOneWidget);   // Mu -> Musik
      expect(find.text('Matematik'), findsNWidgets(2)); // Ma -> Matematik
      expect(find.text('Slöjd'), findsOneWidget);   // Sl -> Slöjd
      expect(find.text('Samhällsorienterande ämnen'), findsOneWidget); // So -> Samhällsorienterande ämnen
      expect(find.text('Rast'), findsWidgets);      // Raster som luft + etikett
    });

    testWidgets('3. Emilio vid 1920x1080 renderar proportionell tidslinje med faktiskt renderad texthöjd', (tester) async {
      await pumpPersondag(
        tester,
        member: emilioMember,
        events: emilioEvents,
        size: const Size(1920, 1080),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsOneWidget);

      // Ämnestext: 24 px w700 enligt FAS 6d.3
      final fysikFinder = find.text('Fysik');
      expect(fysikFinder, findsOneWidget);
      final fysikWidget = tester.widget<Text>(fysikFinder);
      expect(fysikWidget.style?.fontSize, 24);
      expect(fysikWidget.style?.fontWeight, FontWeight.w700);

      // Verifiera FAKTISKT renderad texthöjd via RenderBox (ingen FittedBox/nedskalning)
      final fysikRenderBoxHeight = tester.getSize(fysikFinder).height;
      expect(fysikRenderBoxHeight, greaterThanOrEqualTo(24.0));

      final engelskaFinder = find.text('Engelska');
      expect(engelskaFinder, findsOneWidget);
      final engelskaWidget = tester.widget<Text>(engelskaFinder);
      expect(engelskaWidget.style?.fontSize, 24);

      final teknikFinder = find.text('Teknik');
      expect(teknikFinder, findsOneWidget);
      final teknikWidget = tester.widget<Text>(teknikFinder);
      expect(teknikWidget.style?.fontSize, 24);

      // Tidstext: 20 px w600
      final tidFinder = find.text('09:20–11:15');
      expect(tidFinder, findsOneWidget);
      final tidWidget = tester.widget<Text>(tidFinder);
      expect(tidWidget.style?.fontSize, 20);
      expect(tidWidget.style?.fontWeight, FontWeight.w600);

      // Verifiera FAKTISKT renderad tidstexthöjd via RenderBox
      final tidRenderBoxHeight = tester.getSize(tidFinder).height;
      expect(tidRenderBoxHeight, greaterThanOrEqualTo(20.0));

      // Ingen kompakt fallback vid 1920x1080 för Emilio
      expect(find.textContaining('till'), findsNothing);
    });

    testWidgets('3b. Emilio vid 1280x720 renderar också TIDSLINJE (sum(min_i) <= H)', (tester) async {
      await pumpPersondag(
        tester,
        member: emilioMember,
        events: emilioEvents,
        size: const Size(1280, 720),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsOneWidget);

      // Verifiera tidslinje (INGEN kompakt listfallback)
      expect(find.textContaining('till'), findsNothing);

      // Verifiera FAKTISKT renderad texthöjd även vid 1280x720
      final fysikFinder = find.text('Fysik');
      expect(fysikFinder, findsOneWidget);
      expect(tester.getSize(fysikFinder).height, greaterThanOrEqualTo(24.0));

      final tidFinder = find.text('09:20–11:15');
      expect(tidFinder, findsOneWidget);
      expect(tester.getSize(tidFinder).height, greaterThanOrEqualTo(20.0));
    });

    testWidgets('4. Céline (Universitet, 1 lektion) renderar koden som titel när ingen kursbeskrivning finns', (tester) async {
      await pumpPersondag(
        tester,
        member: celineMember,
        events: celineEvents,
        size: const Size(1920, 1080),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsOneWidget);
      expect(find.text('HARV1000X'), findsOneWidget);
    });

    testWidgets('5. Lunchluckan på vardag med saknad matsedel renderar nudgen i luckan (5.1b)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final lunchInfoNudge = const LunchInfo(
        schoolName: 'Testskolan',
        lunch: 'Matsedel saknas — ladda upp i appen',
        isNudge: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1920,
              height: 1080,
              child: PersondagSchemaView(
                scheduleDocs: emilioEvents,
                memberColor: Colors.blue,
                now: testDay,
                isLowStimuli: false,
                lunchInfo: lunchInfoNudge,
                displayPalette: DisplayPalette.light,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Matsedel saknas — ladda upp i appen'), findsOneWidget);
    });

    testWidgets('6. Noomi (Rehab, icke-skolimport) renderar schemablock utan fel', (tester) async {
      await pumpPersondag(
        tester,
        member: noomiMember,
        events: noomiEvents,
        size: const Size(1920, 1080),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsOneWidget);
      expect(find.text('Fysioterapi Rehab'), findsOneWidget);
      expect(find.text('Bassängträning'), findsOneWidget);
    });

    testWidgets('7. Oscar (Person utan schema) renderar ledig dag / normal vy utan fel', (tester) async {
      await pumpPersondag(
        tester,
        member: oscarMember,
        events: oscarEvents,
        size: const Size(1920, 1080),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(PersondagSchemaView), findsNothing);
      expect(find.textContaining('Inga planer idag'), findsOneWidget);
    });

    testWidgets('8. FAS 6d.3 — Två kolumner vid 1920x1080 (bredd >= 1400): högerkolumn med staplade kort, bottenrader utgår', (tester) async {
      final choreDoc = _MockDocSnapshot('c1', {
        'title': 'Duka bordet',
        'whoUid': 'uLionel',
        'who': 'Lionel',
        'assignedTo': 'uLionel',
        'personUid': 'uLionel',
        'dueDate': '2026-09-14',
      });
      final mealDoc = _MockDocSnapshot('m1', {
        'title': 'Tacos och nachos',
        'emoji': '🌮',
        'date': '2026-09-14',
      });

      await pumpPersondag(
        tester,
        member: lionelMember,
        events: lionelEvents,
        chores: [choreDoc],
        meals: [mealDoc],
        size: const Size(1920, 1080),
      );

      expect(tester.takeException(), isNull);
      // Vänsterkolumn har schemat
      expect(find.byType(PersondagSchemaView), findsOneWidget);

      // Högerkolumn har sektionskort för "Middag ikväll" och "Sysslor idag"
      expect(find.text('Middag ikväll'), findsOneWidget);
      expect(find.textContaining('Tacos och nachos'), findsOneWidget);
      expect(find.text('Sysslor idag'), findsOneWidget);
      expect(find.text('Duka bordet'), findsOneWidget);

      // Bottenraderna utgår i tvåkolumnsläget (ingen "Sysslor: " rubrikrad i botten)
      expect(find.text('Sysslor: '), findsNothing);
    });

    testWidgets('9. FAS 6d.3 — En kolumn vid 1280x720 (bredd < 1400): bottenraderna Sysslor och Imorgon visas', (tester) async {
      final choreDoc = _MockDocSnapshot('c1', {
        'title': 'Plocka ur diskmaskinen',
        'whoUid': 'uEmilio',
        'who': 'Emilio',
        'assignedTo': 'uEmilio',
        'personUid': 'uEmilio',
        'dueDate': '2026-09-14',
      });

      await pumpPersondag(
        tester,
        member: emilioMember,
        events: emilioEvents,
        chores: [choreDoc],
        size: const Size(1280, 720),
      );

      expect(tester.takeException(), isNull);
      // Enkolumnsläget har schemat överst
      expect(find.byType(PersondagSchemaView), findsOneWidget);

      // Bottenraderna finns med i enkolumnsläget
      expect(find.text('Sysslor: '), findsOneWidget);
      expect(find.textContaining('Plocka ur diskmaskinen'), findsOneWidget);
      expect(find.textContaining('Imorgon:'), findsOneWidget);
    });
  });

  group('FAS 6d Robusthet — DisplayModuleErrorBoundary', () {
    testWidgets('7. Modul som kastar renderar dämpad platta och loggar [render] till DisplayLog och lastError', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DisplayModuleErrorBoundary(
              moduleId: 'test_trasig_modul',
              displayPalette: DisplayPalette.light,
              childBuilder: (ctx) => throw Exception('Kritiskt simulerat renderfel!'),
            ),
          ),
        ),
      );

      await tester.pump();

      // 1. Verifiera att fallback-plattan visas
      expect(find.text('Kunde inte visa test_trasig_modul'), findsOneWidget);

      // 2. Verifiera loggpost i DisplayLog med kategori [render]
      final renderLogs = DisplayLog.instance.entries.where((e) => e.category == 'render').toList();
      expect(renderLogs.isNotEmpty, isTrue);
      expect(renderLogs.first.message, contains('test_trasig_modul: Exception: Kritiskt simulerat renderfel!'));

      // 3. Verifiera lastError i DisplayLog (reflekteras i hjärtslaget)
      expect(DisplayLog.instance.lastError, contains('test_trasig_modul: Exception: Kritiskt simulerat renderfel!'));
    });

    testWidgets('8. Persondag som kastar faller tillbaka till klumpade ramen (pre-6d)', (tester) async {
      final moduleContext = DisplayModuleContext(
        now: testDay,
        weekStart: DateTime(2026, 9, 14),
        members: [lionelMember],
        spotlightIndex: 1,
      );

      final provider = _FakeProvider(
        currentUser: lionelMember,
        familyMembers: [lionelMember],
        todayEvents: lionelEvents,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<FamilyProvider>.value(
              value: provider,
              child: SizedBox(
                width: 1920,
                height: 1080,
                child: DisplayModuleErrorBoundary(
                  moduleId: 'persondag',
                  displayPalette: DisplayPalette.light,
                  fallbackBuilder: (ctx, err) => PersondagModule(
                    moduleContext: moduleContext,
                    forceClumped: true,
                  ),
                  childBuilder: (ctx) => throw Exception('Simulerat fel i persondag schema'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verifiera att den klumpade ramplattan renderas som fallback
      expect(find.byType(DisplayRamPlate), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DisplayRamPlate),
          matching: find.textContaining('Skola'),
        ),
        findsOneWidget,
      );

      // Verifiera loggpost
      final renderLogs = DisplayLog.instance.entries.where((e) => e.category == 'render').toList();
      expect(renderLogs.any((e) => e.message.contains('persondag: Exception: Simulerat fel')), isTrue);
    });
  });
}
