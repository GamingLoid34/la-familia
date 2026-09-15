import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/screens/display/display_controller.dart';
import 'package:la_familia/screens/display/display_module_registry.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';
import 'package:la_familia/screens/settings/display_keymap_page.dart';
import 'package:la_familia/screens/settings/display_scenes_page.dart';
import 'package:la_familia/screens/settings/display_schedule_page.dart';

void main() {
  group('FAS 6a — Storskärmsstudion: Schemavalidering och 24h-tidslinje', () {
    test('1. Validering blockerar dubblett-starttider med överlappande dagar', () {
      final entriesWithOverlap = [
        DisplayScheduleEntry(start: '08:00', scene: 'standard', days: [1, 2, 3]),
        DisplayScheduleEntry(start: '08:00', scene: 'morgon', days: [3, 4, 5]),
      ];
      final error = validateSchedule(entriesWithOverlap);
      expect(error, isNotNull);
      expect(error, contains('Två schemaposter kan inte ha samma starttid'));
    });

    test('2. Validering tillåter samma klockslag på disjunkta dagar', () {
      final entriesDisjoint = [
        DisplayScheduleEntry(start: '07:30', scene: 'morgon', days: [1, 2, 3, 4, 5]),
        DisplayScheduleEntry(start: '07:30', scene: 'standard', days: [6, 7]),
      ];
      final error = validateSchedule(entriesDisjoint);
      expect(error, isNull);
    });

    test('3. 24h-remsans beräkning överensstämmer med resolveScheduledScene', () {
      final schedule = [
        DisplayScheduleEntry(start: '06:00', scene: 'morgon'),
        DisplayScheduleEntry(start: '08:00', scene: 'standard'),
        DisplayScheduleEntry(start: '17:00', scene: 'kvall'),
        DisplayScheduleEntry(start: '22:00', scene: 'natt'),
      ];

      // Måndag (weekday 1)
      final blocks = compute24hTimeline(1, schedule);
      expect(blocks.isNotEmpty, true);

      // Total tid i blocks måste summera till exakt 1440 minuter (24h)
      final totalMinutes = blocks.fold<int>(0, (sum, b) => sum + (b.endMinutes - b.startMinutes));
      expect(totalMinutes, 1440);

      // Från 00:00 till 06:00 gäller natt (wrap över midnatt)
      expect(blocks.first.sceneId, 'natt');
      expect(blocks.first.startMinutes, 0);
      expect(blocks.first.endMinutes, 360); // 06:00

      // Från 06:00 till 08:00 gäller morgon
      expect(blocks[1].sceneId, 'morgon');
      expect(blocks[1].startMinutes, 360);
      expect(blocks[1].endMinutes, 480);
    });

    test('4. formatScheduleDays formaterar dagar korrekt', () {
      expect(formatScheduleDays(null), 'Alla dagar');
      expect(formatScheduleDays([]), 'Alla dagar');
      expect(formatScheduleDays([1, 2, 3, 4, 5, 6, 7]), 'Alla dagar');
      expect(formatScheduleDays([1, 2, 3, 4, 5]), 'Mån–Fre');
      expect(formatScheduleDays([6, 7]), 'Lör–Sön');
      expect(formatScheduleDays([1, 3, 5]), 'Mån, Ons, Fre');
    });
  });

  group('FAS 6a — Storskärmsstudion: Scenslug och borttagningsskydd', () {
    test('1. generateSlug hanterar å, ä, ö, versaler och specialtecken', () {
      expect(generateSlug('Helgfrukost & Mys!'), 'helgfrukost_mys');
      expect(generateSlug('ÅÄÖ test'), 'aao_test');
      expect(generateSlug('  Extra---Mellanrum  '), 'extra_mellanrum');
    });

    test('2. validateSceneSlug validerar format och unikhet', () {
      final existing = {'standard', 'natt', 'morgon'};

      expect(validateSceneSlug('standard', existing, isNew: true), contains('redan en scen'));
      expect(validateSceneSlug('ogiltigt slug!', existing, isNew: true), contains('endast innehålla'));
      expect(validateSceneSlug('', existing, isNew: true), contains('får inte vara tomt'));
      expect(validateSceneSlug('ny_scen', existing, isNew: true), isNull);
    });

    test('3. checkSceneDeletionAllowed skyddar standard och natt', () {
      final config = DisplayConfig.defaultConfig();
      expect(checkSceneDeletionAllowed('standard', config), contains('systemkritiska'));
      expect(checkSceneDeletionAllowed('natt', config), contains('systemkritiska'));
    });

    test('4. checkSceneDeletionAllowed skyddar scener som används i schemat', () {
      final config = DisplayConfig.defaultConfig();
      // 'morgon' används i default-schemat vid 05:30
      final error = checkSceneDeletionAllowed('morgon', config);
      expect(error, isNotNull);
      expect(error, contains('används i schemat'));
    });

    test('5. checkSceneDeletionAllowed skyddar scener som är mappade i keymap', () {
      final config = DisplayConfig(
        version: 8,
        scenes: {
          'standard': const DisplayScene(id: 'standard', name: 'Standard', layout: 'board', modules: {}),
          'natt': const DisplayScene(id: 'natt', name: 'Natt', layout: 'fullscreen', modules: {}),
          'egen_scen': const DisplayScene(id: 'egen_scen', name: 'Egen', layout: 'fullscreen', modules: {}),
        },
        schedule: [
          DisplayScheduleEntry(start: '08:00', scene: 'standard'),
        ],
        keymap: const {'1': 'standard', '6': 'egen_scen'},
      );

      final error = checkSceneDeletionAllowed('egen_scen', config);
      expect(error, isNotNull);
      expect(error, contains('kopplad till knapp 6'));
    });
  });

  group('FAS 6a — Modulmanifest: Zonfiltrering och metadata', () {
    final registry = DisplayModuleRegistry.instance;

    test('1. modulesForZone för "main" innehåller exakt rätt 8 moduler', () {
      final mainModules = registry.modulesForZone('main');
      final ids = mainModules.map((m) => m.id).toSet();
      expect(ids, {
        'veckotavla',
        'idag_nu',
        'natt',
        'foto',
        'klocka',
        'middag_vecka',
        'avgangar',
        'skolmat',
      });
      // persondag ska inte ingå om inte includeManualOnly sätts
      expect(ids.contains('persondag'), false);
    });

    test('2. modulesForZone för "side" innehåller exakt rätt 8 moduler', () {
      final sideModules = registry.modulesForZone('side');
      final ids = sideModules.map((m) => m.id).toSet();
      expect(ids, {
        'middag_vecka',
        'avgangar',
        'skolmat',
        'klocka',
        'foto',
        'sysslor_idag',
        'tavlan',
        'nedrakning',
      });
    });

    test('3. modulesForZone för footer-zoner normaliseras och innehåller 7 moduler', () {
      final f1 = registry.modulesForZone('footer1');
      final f2 = registry.modulesForZone('footer2');
      final f3 = registry.modulesForZone('footer3');
      final ids = f1.map((m) => m.id).toSet();
      expect(ids, {
        'middag_idag',
        'sysslor_idag',
        'tavlan',
        'nedrakning',
        'avgangar',
        'skolmat',
        'klocka',
      });
      expect(f2.length, 7);
      expect(f3.length, 7);
    });

    test('4. persondag är flaggad som manualOnly', () {
      final meta = registry.metaFor('persondag');
      expect(meta, isNotNull);
      expect(meta!.manualOnly, true);
    });
  });

  group('FAS 6a — Tangentmappning och Stream Deck-lathund', () {
    test('1. Controller slår upp siffertangent i keymap och sätter scen', () {
      final config = DisplayConfig(
        version: 8,
        scenes: {
          'standard': const DisplayScene(id: 'standard', name: 'Standard', layout: 'board', modules: {}),
          'natt': const DisplayScene(id: 'natt', name: 'Natt', layout: 'fullscreen', modules: {}),
          'custom': const DisplayScene(id: 'custom', name: 'Custom Scen', layout: 'fullscreen', modules: {}),
        },
        schedule: [
          DisplayScheduleEntry(start: '08:00', scene: 'standard'),
        ],
        keymap: const {'1': 'standard', '7': 'custom'},
      );

      final controller = DisplayController(
        configProvider: () => config,
      );

      controller.handleDigitKey('7');
      expect(controller.manualSceneId, 'custom');
      expect(controller.feedbackMessage, 'Custom Scen');

      // Omappad tangent sätter inte manuell scen
      controller.handleDigitKey('9');
      expect(controller.manualSceneId, 'custom'); // Oförändrad
    });

    test('2. generateCheatSheetText producerar komplett och korrekt lathund', () {
      final keymap = {'1': 'standard', '2': 'natt'};
      final scenes = {
        'standard': const DisplayScene(id: 'standard', name: 'Veckotavlan', layout: 'board', modules: {}),
        'natt': const DisplayScene(id: 'natt', name: 'Natt', layout: 'fullscreen', modules: {}),
      };
      final members = [
        const UserModel(
          uid: 'u1',
          name: 'Anna Andersson',
          email: 'anna@example.com',
          color: '#2E7D32',
          role: 'parent',
          viewMode: 'parent',
          energy: 3,
        ),
      ];

      final text = generateCheatSheetText(
        keymap: keymap,
        scenes: scenes,
        familyMembers: members,
      );

      expect(text, contains('[1] Veckotavlan (standard)'));
      expect(text, contains('[2] Natt (natt)'));
      expect(text, contains('[3] — Omappad'));
      expect(text, contains('[Shift+1] Anna Andersson'));
      expect(text, contains('[H]      Hem'));
      expect(text, contains('[N]      Natt'));
      expect(text, contains('[L]      Lågstimuli'));
    });
  });
}
