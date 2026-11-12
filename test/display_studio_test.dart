import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/display_controller.dart';
import 'package:la_familia/screens/display/display_module_registry.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';

void main() {
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

  });
}
