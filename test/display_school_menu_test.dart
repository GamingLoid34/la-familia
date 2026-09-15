import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/screens/display/display_module_error_boundary.dart';
import 'package:la_familia/screens/display/display_module_registry.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';
import 'package:la_familia/screens/display/display_school_menu_data.dart';
import 'package:la_familia/screens/display/modules/skolmat_module.dart';
import 'package:la_familia/screens/settings/storskarm_settings_page.dart';

void main() {
  group('FAS 5.1 — Skolmatsedel: Modeller och Data', () {
    test('1. DayMenu och SchoolMenu parsning och dayFor', () {
      final menuMap = {
        'schoolId': '318',
        'schoolName': 'Junkaremålsskolan',
        'days': [
          {
            'date': '2026-09-09',
            'lunch': 'Köttbullar med potatismos',
            'vegetarian': 'Vegobullar med potatismos',
          },
          {
            'date': '2026-09-10',
            'lunch': 'Pannkakor med sylt',
            'vegetarian': null,
          },
        ],
      };

      final schoolMenu = SchoolMenu.fromMap(menuMap);
      expect(schoolMenu.schoolId, '318');
      expect(schoolMenu.schoolName, 'Junkaremålsskolan');
      expect(schoolMenu.days.length, 2);

      final sep9 = DateTime(2026, 9, 9, 10, 30);
      final day9 = schoolMenu.dayFor(sep9);
      expect(day9, isNotNull);
      expect(day9!.lunch, 'Köttbullar med potatismos');
      expect(day9.vegetarian, 'Vegobullar med potatismos');

      final sep10 = DateTime(2026, 9, 10, 12, 0);
      final day10 = schoolMenu.dayFor(sep10);
      expect(day10, isNotNull);
      expect(day10!.lunch, 'Pannkakor med sylt');
      expect(day10.vegetarian, isNull);

      final sep11 = DateTime(2026, 9, 11, 8, 0);
      expect(schoolMenu.dayFor(sep11), isNull);
    });

    test('2. computeSchoolMenuBackoffMinutes', () {
      expect(computeSchoolMenuBackoffMinutes(0), 5);
      expect(computeSchoolMenuBackoffMinutes(1), 5);
      expect(computeSchoolMenuBackoffMinutes(2), 15);
      expect(computeSchoolMenuBackoffMinutes(3), 60);
      expect(computeSchoolMenuBackoffMinutes(5), 60);
    });

    test('3. DisplaySchoolMenuData.lunchFor matchar medlems-uid och skola', () {
      final data = DisplaySchoolMenuData.instance;
      data.reset();

      final schoolMenu = SchoolMenu(
        schoolId: '318',
        schoolName: 'Junkaremålsskolan',
        days: const [
          DayMenu(
            date: '2026-09-09',
            lunch: 'Fiskbjörk med dillsås',
            vegetarian: 'Sojabiffar',
          ),
        ],
      );
      data.setMockMenus({'318': schoolMenu});

      const config = DisplaySkolmatConfig(
        schools: [
          DisplaySkolmatSchoolConfig(
            id: '318',
            name: 'Junkaremålsskolan',
            memberUids: ['lionel-uid'],
          ),
          DisplaySkolmatSchoolConfig(
            id: '323',
            name: 'Fröafallsskolan',
            memberUids: ['leandro-uid'],
          ),
        ],
      );

      final testDate = DateTime(2026, 9, 9, 11, 0);

      // Lionel -> Skola 318 -> har meny
      final lionelLunch = data.lunchFor('lionel-uid', testDate, config);
      expect(lionelLunch, isNotNull);
      expect(lionelLunch!.schoolName, 'Junkaremålsskolan');
      expect(lionelLunch.lunch, 'Fiskbjörk med dillsås');
      expect(lionelLunch.vegetarian, 'Sojabiffar');

      // Leandro -> Skola 323 -> saknar meny i mock
      final leandroLunch = data.lunchFor('leandro-uid', testDate, config);
      expect(leandroLunch, isNull);

      // Celine -> saknar skola
      final celineLunch = data.lunchFor('celine-uid', testDate, config);
      expect(celineLunch, isNull);

      // Lionel en annan dag -> saknas
      final otherDayLunch =
          data.lunchFor('lionel-uid', DateTime(2026, 9, 12), config);
      expect(otherDayLunch, isNull);
    });

    testWidgets('4. DisplayModuleRegistry har skolmat registrerad', (tester) async {
      final registry = DisplayModuleRegistry.instance;
      expect(registry, isNotNull);

      final modCtx = DisplayModuleContext(
        now: DateTime(2026, 9, 9, 10, 0),
        weekStart: DateTime(2026, 9, 7),
        members: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = registry.buildModule('skolmat', context, modCtx);
              expect(widget, isA<DisplayModuleErrorBoundary>());
              return widget;
            },
          ),
        ),
      );
      expect(find.byType(SkolmatModule), findsOneWidget);
    });
  });

  group('FAS 5.1 — SkolmatModule widget rendering', () {
    testWidgets('5. Renderar footerkort (höjd <= 130)', (tester) async {
      final data = DisplaySchoolMenuData.instance;
      data.reset();
      data.setMockMenus({
        '318': const SchoolMenu(
          schoolId: '318',
          schoolName: 'Junkaremålsskolan',
          days: [
            DayMenu(
              date: '2026-09-09',
              lunch: 'Köttbullar med mos',
            ),
          ],
        ),
      });

      const config = DisplaySkolmatConfig(
        schools: [
          DisplaySkolmatSchoolConfig(
            id: '318',
            name: 'Junkaremålsskolan',
            memberUids: ['lionel'],
          ),
        ],
      );

      final modCtx = DisplayModuleContext(
        now: DateTime(2026, 9, 9, 10, 0),
        weekStart: DateTime(2026, 9, 7),
        members: const [],
        skolmatConfig: config,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 110,
              width: 400,
              child: SkolmatModule(moduleContext: modCtx),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Skolmat'), findsOneWidget);
      expect(find.text('Köttbullar med mos'), findsOneWidget);
    });

    testWidgets('6. Renderar stor zon med veckomatsedel', (tester) async {
      final data = DisplaySchoolMenuData.instance;
      data.reset();
      data.setMockMenus({
        '318': const SchoolMenu(
          schoolId: '318',
          schoolName: 'Junkaremålsskolan',
          days: [
            DayMenu(
              date: '2026-09-07',
              lunch: 'Pasta bolognese',
              vegetarian: 'Vegfärssås',
            ),
            DayMenu(
              date: '2026-09-08',
              lunch: 'Fiskgratäng',
            ),
          ],
        ),
      });

      const config = DisplaySkolmatConfig(
        schools: [
          DisplaySkolmatSchoolConfig(
            id: '318',
            name: 'Junkaremålsskolan',
            memberUids: ['lionel'],
          ),
        ],
      );

      final modCtx = DisplayModuleContext(
        now: DateTime(2026, 9, 7, 10, 0),
        weekStart: DateTime(2026, 9, 7),
        members: const [],
        skolmatConfig: config,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              width: 800,
              child: SkolmatModule(moduleContext: modCtx),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Skolmatsedel'), findsOneWidget);
      expect(find.text('Junkaremålsskolan'), findsOneWidget);
      expect(find.text('Pasta bolognese'), findsOneWidget);
      expect(find.text('🌱 Vegfärssås'), findsOneWidget);
      expect(find.text('Fiskgratäng'), findsOneWidget);
    });

    test('7. DisplaySkolmatSchoolConfig hanterar municipality', () {
      const config = DisplaySkolmatSchoolConfig(
        id: '50',
        name: 'Anders Ljungstedts Gymnasium',
        municipality: 'linkoping',
        memberUids: ['uid-1', 'uid-2'],
      );

      final map = config.toMap();
      expect(map['id'], '50');
      expect(map['name'], 'Anders Ljungstedts Gymnasium');
      expect(map['municipality'], 'linkoping');
      expect(map['memberUids'], ['uid-1', 'uid-2']);

      final parsed = DisplaySkolmatSchoolConfig.fromMap(map);
      expect(parsed.id, '50');
      expect(parsed.name, 'Anders Ljungstedts Gymnasium');
      expect(parsed.municipality, 'linkoping');
      expect(parsed.memberUids, ['uid-1', 'uid-2']);

      // Fallback till tranas om municipality saknas i map
      final parsedFallback = DisplaySkolmatSchoolConfig.fromMap({
        'id': '318',
        'name': 'Junkaremålsskolan',
        'memberUids': ['uid-3'],
      });
      expect(parsedFallback.municipality, 'tranas');
    });

    testWidgets('8. StorskarmSettingsPage renderar Foton och Skolmat för föräldrar',
        (tester) async {
      const parentUser = UserModel(
        uid: 'p-1',
        name: 'Mamma',
        email: 'mamma@test.se',
        color: 'ff2196f3',
        role: 'parent',
        viewMode: 'parent',
        energy: 3,
        familyId: 'fam-1',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: StorskarmSettingsPage(
            familyId: 'fam-1',
            dayColor: Colors.blue,
            familyMembers: [parentUser],
            currentUser: parentUser,
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Storskärm'), findsWidgets);
      expect(find.text('Foton'), findsOneWidget);
      expect(find.text('Skolmat'), findsOneWidget);
      expect(find.text('Koppla barnen till skola och kommun för skolmatsedel'),
          findsOneWidget);
    });

    testWidgets('9. StorskarmSettingsPage blockerar barnkonton',
        (tester) async {
      const childUser = UserModel(
        uid: 'c-1',
        name: 'Barn',
        email: 'barn@test.se',
        color: 'ff4caf50',
        role: 'child',
        viewMode: 'child',
        energy: 4,
        familyId: 'fam-1',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: StorskarmSettingsPage(
            familyId: 'fam-1',
            dayColor: Colors.green,
            familyMembers: [childUser],
            currentUser: childUser,
          ),
        ),
      );

      await tester.pump();
      expect(
        find.text('Endast föräldrar har behörighet till storskärmsinställningar.'),
        findsOneWidget,
      );
      expect(find.text('Skolmat'), findsNothing);
    });
  });

  group('FAS 5.1b — Egen matsedel: Modeller, ISO-vecka och Väggnudge', () {
    test('10. formatIsoWeek härleder korrekt ISO-8601 veckonyckel ur datum', () {
      // 2026-09-10 är en torsdag i vecka 37
      expect(formatIsoWeek(DateTime(2026, 9, 10)), '2026-W37');
      // 2026-09-14 är en måndag i vecka 38
      expect(formatIsoWeek(DateTime(2026, 9, 14)), '2026-W38');
      // 2026-01-01 (torsdag) tillhör vecka 1 år 2026
      expect(formatIsoWeek(DateTime(2026, 1, 1)), '2026-W01');
      // 2027-01-01 (fredag) tillhör vecka 53 år 2026
      expect(formatIsoWeek(DateTime(2027, 1, 1)), '2026-W53');
      // 2027-01-04 (måndag) tillhör vecka 1 år 2027
      expect(formatIsoWeek(DateTime(2027, 1, 4)), '2027-W01');
    });

    test('11. DisplaySkolmatSchoolConfig har default source == "mateo"', () {
      const defaultSchool = DisplaySkolmatSchoolConfig(
        id: '318',
        name: 'Junkaremålsskolan',
      );
      expect(defaultSchool.source, 'mateo');
      expect(defaultSchool.isManual, isFalse);

      final fromMapDefault = DisplaySkolmatSchoolConfig.fromMap({
        'id': '318',
        'name': 'Junkaremålsskolan',
      });
      expect(fromMapDefault.source, 'mateo');
      expect(fromMapDefault.isManual, isFalse);

      final manualSchool = DisplaySkolmatSchoolConfig.fromMap({
        'id': 'manual_123',
        'name': 'Emilios skola (SkolFood)',
        'source': 'manual',
      });
      expect(manualSchool.source, 'manual');
      expect(manualSchool.isManual, isTrue);
      expect(manualSchool.municipality, '');
    });

    test('12. Väggnudge söndag kl 17:00 vid saknad matsedel för nästa vecka', () {
      final data = DisplaySchoolMenuData.instance;
      data.reset();

      const config = DisplaySkolmatConfig(
        schools: [
          DisplaySkolmatSchoolConfig(
            id: 'manual_emilio',
            name: 'Emilios skola',
            source: 'manual',
            memberUids: ['emilio-uid'],
          ),
          DisplaySkolmatSchoolConfig(
            id: 'mateo_318',
            name: 'Junkaremålsskolan',
            source: 'mateo',
            memberUids: ['lionel-uid'],
          ),
        ],
      );

      // Söndag 2026-09-13 kl 17:00
      final sunday17 = DateTime(2026, 9, 13, 17, 0);

      // A. Emilio (manuell skola) utan uppladdad nästa vecka -> NUDGE!
      final emilioLunch = data.lunchFor('emilio-uid', sunday17, config);
      expect(emilioLunch, isNotNull);
      expect(emilioLunch!.isNudge, isTrue);
      expect(emilioLunch.lunch, 'Matsedel saknas — ladda upp i appen');

      // B. Lionel (Mateo-skola) utan meny -> ALDRIG nudge för Mateo!
      final lionelLunch = data.lunchFor('lionel-uid', sunday17, config);
      expect(lionelLunch, isNull);

      // C. Ladda upp nästa vecka för Emilio -> Nudge försvinner!
      data.setMockNextWeekMenus({
        'manual_emilio': const SchoolMenu(
          schoolId: 'manual_emilio',
          schoolName: 'Emilios skola',
          days: [
            DayMenu(date: '2026-09-14', lunch: 'Spaghetti och köttfärssås'),
          ],
        ),
      });

      final emilioLunchAfterUpload =
          data.lunchFor('emilio-uid', sunday17, config);
      expect(emilioLunchAfterUpload, isNull);
    });

    test('13. Väggnudge vardag vid saknad matsedel vs uppladdad matsedel', () {
      final data = DisplaySchoolMenuData.instance;
      data.reset();

      const config = DisplaySkolmatConfig(
        schools: [
          DisplaySkolmatSchoolConfig(
            id: 'manual_emilio',
            name: 'Emilios skola',
            source: 'manual',
            memberUids: ['emilio-uid'],
          ),
        ],
      );

      // Torsdag 2026-09-10 kl 08:30
      final thursdayMorning = DateTime(2026, 9, 10, 8, 30);

      // Saknar matsedel på torsdag -> NUDGE!
      final emilioMissing =
          data.lunchFor('emilio-uid', thursdayMorning, config);
      expect(emilioMissing, isNotNull);
      expect(emilioMissing!.isNudge, isTrue);
      expect(emilioMissing.lunch, 'Matsedel saknas — ladda upp i appen');

      // Med uppladdad matsedel -> Visar dagens rätt, isNudge == false
      data.setMockMenus({
        'manual_emilio': const SchoolMenu(
          schoolId: 'manual_emilio',
          schoolName: 'Emilios skola',
          days: [
            DayMenu(
              date: '2026-09-10',
              lunch: 'Korv stroganoff med ris',
              vegetarian: 'Vegokorv stroganoff',
            ),
          ],
        ),
      });

      final emilioUploaded =
          data.lunchFor('emilio-uid', thursdayMorning, config);
      expect(emilioUploaded, isNotNull);
      expect(emilioUploaded!.isNudge, isFalse);
      expect(emilioUploaded.lunch, 'Korv stroganoff med ris');
      expect(emilioUploaded.vegetarian, 'Vegokorv stroganoff');
    });

    test('14. Helg före söndag kl 16:00 visar ingen nudge för manuella skolor', () {
      final data = DisplaySchoolMenuData.instance;
      data.reset();

      const config = DisplaySkolmatConfig(
        schools: [
          DisplaySkolmatSchoolConfig(
            id: 'manual_emilio',
            name: 'Emilios skola',
            source: 'manual',
            memberUids: ['emilio-uid'],
          ),
        ],
      );

      // Lördag 2026-09-12 kl 12:00
      final saturdayNoon = DateTime(2026, 9, 12, 12, 0);
      expect(data.lunchFor('emilio-uid', saturdayNoon, config), isNull);

      // Söndag 2026-09-13 kl 15:59 (före 16:00)
      final sundayBefore16 = DateTime(2026, 9, 13, 15, 59);
      expect(data.lunchFor('emilio-uid', sundayBefore16, config), isNull);
    });
  });

  group('FAS 5.7 — Rening av skolmatstitlar och kompakt visning', () {
    test('15. cleanDishTitle rensar prefix', () {
      expect(cleanDishTitle('Lunch 1: Pannkakor med sylt'), 'Pannkakor med sylt');
      expect(cleanDishTitle('Lunch 2 - Köttbullar'), 'Köttbullar');
      expect(cleanDishTitle('Dagens 1: Fiskgratäng'), 'Fiskgratäng');
      expect(cleanDishTitle('Dagens rätt 1: Kycklinggryta'), 'Kycklinggryta');
      expect(cleanDishTitle('Lunch: Ostgratinerad falukorv'), 'Ostgratinerad falukorv');
      expect(cleanDishTitle('Falukorv med stuvade makaroner'), 'Falukorv med stuvade makaroner');
    });

    test('16. formatCompactLunch visar alltid exakt en rätt utan prefix', () {
      expect(formatCompactLunch('Lunch 1: Ugnsbakad falukorv · Lunch 2: Sojakorv'), 'Ugnsbakad falukorv');
      expect(formatCompactLunch('Lunch 1: Quornfilé'), 'Quornfilé');
      expect(formatCompactLunch('Matsedel saknas — ladda upp i appen'), 'Matsedel saknas — ladda upp i appen');
      expect(formatCompactLunch(null), '');
      expect(formatCompactLunch(''), '');
    });
  });

  group('Korrigering 6d.4 — Lunchrad och distinkt vegetariskt alternativ', () {
    test('hasDistinctVegetarian returnerar false om veg är tomt, null eller identiskt med lunch', () {
      // SkolFood måndag v.38: Kebabpytt utan veg
      expect(hasDistinctVegetarian('Kebabpytt', null), isFalse);
      expect(hasDistinctVegetarian('Kebabpytt', ''), isFalse);
      expect(hasDistinctVegetarian('Kebabpytt', '   '), isFalse);
      expect(hasDistinctVegetarian('Kebabpytt', 'Kebabpytt'), isFalse);
      expect(hasDistinctVegetarian('Kebabpytt', 'kebabpytt'), isFalse);
      expect(hasDistinctVegetarian('Kebabpytt', '  kebabpytt  '), isFalse);
      expect(hasDistinctVegetarian('Lunch 1: Kebabpytt', 'Kebabpytt'), isFalse);

      // Distinkt veg
      expect(hasDistinctVegetarian('Laxpudding med skirat smör', 'Vegetarisk paj med spenat'), isTrue);
      expect(hasDistinctVegetarian('Kebabpytt', 'Falafel'), isTrue);
      expect(hasDistinctVegetarian(null, 'Falafel'), isTrue);
    });

    test('Fixtur SkolFood måndag v.38 (Kebabpytt utan veg) -> en rätt, ingen 🌱', () {
      const lunch = 'Kebabpytt';
      const String? veg = null;

      final hasVeg = hasDistinctVegetarian(lunch, veg);
      final cleanVeg = hasVeg ? cleanDishTitle(veg!) : null;
      final dishStr = (cleanVeg != null && cleanVeg.isNotEmpty)
          ? '$lunch · 🌱 $cleanVeg'
          : lunch;

      expect(hasVeg, isFalse);
      expect(cleanVeg, isNull);
      expect(dishStr, 'Kebabpytt');
      expect(dishStr.contains('🌱'), isFalse);
    });
  });
}
