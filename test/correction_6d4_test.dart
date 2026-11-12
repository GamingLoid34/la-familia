import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/screens/display/display_clock.dart';
import 'package:la_familia/screens/display/display_chips.dart';
import 'package:la_familia/screens/display/display_module_registry.dart';
import 'package:la_familia/screens/display/display_palette.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';
import 'package:la_familia/screens/display/display_school_menu_data.dart';
import 'package:la_familia/screens/display/modules/idag_nu_module.dart';
import 'package:la_familia/screens/display/modules/skolmat_module.dart';
import 'package:la_familia/screens/display/modules/persondag_schema.dart';
import 'package:provider/provider.dart';
import 'idag_nu_hero_test.dart' show FakeFamilyProvider, MockDocSnapshot;

void main() {
  setUpAll(() => initializeDateFormatting('sv_SE', null));
  tearDown(() {
    DisplayClock.reset();
    DisplayClock.setRealNowProvider(DateTime.now);
    DisplaySchoolMenuData.instance.reset();
  });

  test('6d.4 punkt 1: kontrasttabell alla sju dagar', () {
    for (var day = 1; day <= 7; day++) {
      final stop = DisplayPalette.lightestGradientStop(day);
      final alpha = DisplayPalette.idagScrimAlphaFor(day);
      final ratio = DisplayPalette.contrastRatio(
        Colors.white,
        Color.alphaBlend(Colors.black.withValues(alpha: alpha), stop),
      );
      expect(DisplayPalette.idagTextColorFor(day), Colors.white);
      expect(alpha, greaterThan(0));
      expect(ratio, greaterThanOrEqualTo(4.5));
      // Rapportvärden från samma Flutter-färgberäkning som renderingen.
      // ignore: avoid_print
      print(
        'KONTRAST $day #${stop.toARGB32().toRadixString(16).substring(2).toUpperCase()} $alpha ${ratio.toStringAsFixed(3)}:1',
      );
    }
  });

  testWidgets(
    '6d.4 punkt 2: Kebabpytt utan veg renderas exakt en gång utan grodd',
    (tester) async {
      DisplaySchoolMenuData.instance.setMockMenus({
        'fixture': const SchoolMenu(
          schoolId: 'fixture',
          schoolName: 'SkolFood',
          days: [
            DayMenu(date: '2026-09-14', lunch: 'Kebabpytt', vegetarian: null),
          ],
        ),
      });
      final ctx = DisplayModuleContext(
        now: DateTime(2026, 9, 14, 11),
        weekStart: DateTime(2026, 9, 14),
        members: const [],
        skolmatConfig: const DisplaySkolmatConfig(
          schools: [
            DisplaySkolmatSchoolConfig(
              id: 'fixture',
              name: 'SkolFood',
              memberUids: [],
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 130,
              width: 600,
              child: SkolmatModule(moduleContext: ctx),
            ),
          ),
        ),
      );
      expect(find.text('Kebabpytt'), findsOneWidget);
      expect(find.textContaining('🌱'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '6d.4 punkt 3: Mentorstitel och klasskod renderas separat och dämpat',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersondagSchemaView(
              scheduleDocs: [
                MockDocSnapshot('lesson', {
                  'title': 'mentorstid_tek2',
                  'date': '2026-09-14',
                  'time': '09:00',
                  'endTime': '10:00',
                }),
              ],
              memberColor: Colors.blue,
              now: DateTime(2026, 9, 14, 8),
              isLowStimuli: false,
              displayPalette: DisplayPalette.light,
            ),
          ),
        ),
      );
      expect(find.text('Mentorstid'), findsOneWidget);
      expect(find.text('tek2'), findsOneWidget);
      final code = tester.widget<Text>(find.text('tek2'));
      expect(code.style!.fontSize, greaterThanOrEqualTo(18));
      expect(code.style!.color, DisplayPalette.light.textMuted);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '6d.4 punkt 4: testTime söndag visar inga skolramar eller måndagshändelser',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DisplayClock.init(
        uri: Uri.parse(
          'https://example.test/?display=1&testTime=2026-09-13T11:00',
        ),
        realNowProvider: () => DateTime(2026, 9, 14, 11),
      );
      const member = UserModel(
        uid: 'child',
        familyId: 'family',
        name: 'Testbarn',
        email: 'child@example.test',
        role: 'child',
        viewMode: 'child',
        energy: 3,
        color: '#2196F3',
      );
      final provider = FakeFamilyProvider(
        currentUser: member,
        familyMembers: [member],
        todayEvents: [
          MockDocSnapshot('school', {
            'title': 'Måndagsskola',
            'date': '2026-09-14',
            'time': '12:00',
            'endTime': '15:00',
            'planningImportKind': 'schedule',
            'personUids': ['child'],
          }),
          MockDocSnapshot('activity', {
            'title': 'Måndagsfotboll',
            'date': '2026-09-14',
            'time': '17:00',
            'personUids': ['child'],
          }),
          MockDocSnapshot('weekly', {
            'title': 'Veckovis måndagsmöte',
            'date': '2026-09-07',
            'time': '18:00',
            'isRecurring': true,
            'recurrence': {'type': 'weekly', 'startDate': '2026-09-07'},
            'personUids': ['child'],
          }),
          MockDocSnapshot('sunday', {
            'title': 'Söndagspromenad',
            'date': '2026-09-13',
            'time': '16:00',
            'personUids': ['child'],
          }),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<FamilyProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: IdagNuModule(
                moduleContext: DisplayModuleContext(
                  now: DisplayClock.now(),
                  weekStart: DateTime(2026, 9, 7),
                  members: [member],
                ),
              ),
            ),
          ),
        ),
      );
      expect(DisplayClock.now().weekday, DateTime.sunday);
      expect(find.byType(DisplayRamPlate), findsNothing);
      expect(find.textContaining('Måndagsskola'), findsNothing);
      expect(find.textContaining('Måndagsfotboll'), findsNothing);
      expect(find.textContaining('Veckovis måndagsmöte'), findsNothing);
      expect(find.textContaining('Söndagspromenad'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
