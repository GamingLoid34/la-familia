import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/display_config_source.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';

void main() {
  group('FAS 6a — mergeDefaults: Icke-destruktiv uppgradering till v8', () {
    test('1. Användarredigerat schema överlever uppgradering till v8', () {
      final userSchedule = [
        {'start': '07:00', 'scene': 'frukost', 'days': [1, 2, 3, 4, 5]},
        {'start': '20:00', 'scene': 'natt'},
      ];

      final rawDoc = {
        'version': 7,
        'schedule': userSchedule,
        'scenes': {
          'standard': {'name': 'Standard', 'layout': 'board', 'modules': {'main': 'veckotavla'}},
          'natt': {'name': 'Natt', 'layout': 'fullscreen', 'modules': {'main': 'natt'}},
          'frukost': {'name': 'Frukost', 'layout': 'board', 'modules': {'main': 'idag_nu'}},
        },
      };

      final merged = mergeDefaults(rawDoc, DisplayConfig.defaultRawMap());

      expect(merged['version'], 10);
      expect(merged['schedule'], userSchedule);
      expect(merged['scenes']['frukost']['name'], 'Frukost');
    });

    test('2. Användarborttagen default-scen (finns i seededSceneIds, saknas i scenes) återkommer INTE', () {
      final rawDoc = {
        'version': 7,
        'seededSceneIds': ['standard', 'natt', 'morgon', 'kvall', 'foto', 'person'],
        'scenes': {
          // 'morgon' och 'kvall' togs bort av användaren
          'standard': {'name': 'Standard', 'layout': 'board', 'modules': {'main': 'veckotavla'}},
          'natt': {'name': 'Natt', 'layout': 'fullscreen', 'modules': {'main': 'natt'}},
          'foto': {'name': 'Foton', 'layout': 'fullscreen', 'modules': {'main': 'foto'}},
          'person': {'name': 'Person', 'layout': 'fullscreen', 'modules': {'main': 'persondag'}},
        },
      };

      final merged = mergeDefaults(rawDoc, DisplayConfig.defaultRawMap());

      expect(merged['scenes'].containsKey('morgon'), false);
      expect(merged['scenes'].containsKey('kvall'), false);
      expect(merged['scenes'].containsKey('standard'), true);
      expect(merged['scenes'].containsKey('natt'), true);
      expect(merged['seededSceneIds'].contains('morgon'), true);
    });

    test('3. Ny default-scen i koden (saknas i seededSceneIds) LÄGGS TILL', () {
      final rawDoc = {
        'version': 7,
        'seededSceneIds': ['standard', 'natt'],
        'scenes': {
          'standard': {'name': 'Standard', 'layout': 'board', 'modules': {'main': 'veckotavla'}},
          'natt': {'name': 'Natt', 'layout': 'fullscreen', 'modules': {'main': 'natt'}},
        },
      };

      final customDefaults = {
        'version': 8,
        'seededSceneIds': ['standard', 'natt', 'ny_systemscen'],
        'scenes': {
          'standard': {'name': 'Standard', 'layout': 'board', 'modules': {'main': 'veckotavla'}},
          'natt': {'name': 'Natt', 'layout': 'fullscreen', 'modules': {'main': 'natt'}},
          'ny_systemscen': {'name': 'Ny Scen', 'layout': 'fullscreen', 'modules': {'main': 'klocka'}},
        },
      };

      final merged = mergeDefaults(rawDoc, customDefaults);

      expect(merged['scenes'].containsKey('ny_systemscen'), true);
      expect(merged['seededSceneIds'].contains('ny_systemscen'), true);
    });

    test('4. Saknade toppnivånycklar (keymap, seededSceneIds) läggs till med v9-defaults', () {
      final rawDoc = {
        'version': 7,
        'scenes': {
          'standard': {'name': 'Standard', 'layout': 'board', 'modules': {'main': 'veckotavla'}},
        },
        'schedule': [
          {'start': '08:00', 'scene': 'standard'},
        ],
      };

      final merged = mergeDefaults(rawDoc, DisplayConfig.defaultRawMap());

      expect(merged['keymap'] is Map, true);
      expect(merged['keymap']['1'], 'standard');
      expect(merged['keymap']['2'], 'natt');
      expect(merged['seededSceneIds'] is List, true);
      expect(merged['seededSceneIds'].contains('standard'), true);
      expect(merged['seededSceneIds'].contains('natt'), true);
    });

    test('5. Användarens custom-scener och transit/skolmat bevaras orörda', () {
      final userTransit = {
        'stops': [
          {'id': '123', 'name': 'Min hållplats', 'icon': '🚏', 'walkMinutes': 3},
        ],
        'destinations': ['Centrum'],
        'modes': ['bus'],
        'walkMinutes': 3,
      };

      final userSkolmat = {
        'schools': [
          {'id': '99', 'name': 'Byskolan', 'municipality': 'tranas', 'source': 'mateo', 'memberUids': ['u1']},
        ],
      };

      final rawDoc = {
        'version': 7,
        'transit': userTransit,
        'skolmat': userSkolmat,
        'scenes': {
          'standard': {'name': 'Standard', 'layout': 'board', 'modules': {'main': 'veckotavla'}},
          'egen_bio': {'name': 'Biokväll', 'layout': 'fullscreen', 'modules': {'main': 'foto'}},
        },
      };

      final merged = mergeDefaults(rawDoc, DisplayConfig.defaultRawMap());

      expect(merged['transit'], userTransit);
      expect(merged['skolmat'], userSkolmat);
      expect(merged['scenes']['egen_bio']['name'], 'Biokväll');
    });
  });

  group('FAS 6b — transformV8ToV9: Idempotent transform till v9', () {
    test('1. Saknade per-stop fält kopierar rotvärden och lägger till foto', () {
      final v8Doc = {
        'version': 8,
        'transit': {
          'stops': [
            {'id': '740000041', 'name': 'Tranås station', 'icon': '🚆'},
          ],
          'destinations': ['Mjölby', 'Linköping', 'Norrköping'],
          'modes': ['train'],
          'walkMinutes': 6,
        },
      };

      final v9 = transformV8ToV9(v8Doc);

      expect(v9['version'], 9);
      expect(v9['foto']['intervalSec'], 45);

      final transit = v9['transit'] as Map<String, dynamic>;
      // Rotnycklarna ska vara kvar för bakåtkompatibilitet
      expect(transit['walkMinutes'], 6);
      expect(transit['modes'], ['train']);
      expect(transit['destinations'], ['Mjölby', 'Linköping', 'Norrköping']);

      final stops = transit['stops'] as List;
      final stop = stops.first as Map<String, dynamic>;
      expect(stop['walkMinutes'], 6);
      expect(stop['filter']['modes'], ['train']);
      expect(stop['filter']['destinations'], ['Mjölby', 'Linköping', 'Norrköping']);
    });

    test('2. Transformen är strikt idempotent vid upprepad körning', () {
      final v8Doc = {
        'version': 8,
        'transit': {
          'stops': [
            {'id': '740000041', 'name': 'Tranås station', 'icon': '🚆'},
          ],
          'destinations': ['Mjölby', 'Linköping'],
          'modes': ['train'],
          'walkMinutes': 5,
        },
      };

      final firstPass = transformV8ToV9(v8Doc);
      final secondPass = transformV8ToV9(firstPass);

      expect(secondPass, equals(firstPass));
    });

    test('3. Redan anpassade per-stop-värden skrivs INTE över', () {
      final customDoc = {
        'version': 8,
        'foto': {'intervalSec': 30},
        'transit': {
          'stops': [
            {
              'id': '740025574',
              'name': 'Tranås Storgatan',
              'icon': '🚌',
              'walkMinutes': 2,
              'filter': {
                'modes': ['bus'],
                'destinations': ['Stoeryd'],
              },
            },
          ],
          'destinations': ['Mjölby'],
          'modes': ['train'],
          'walkMinutes': 7,
        },
      };

      final v9 = transformV8ToV9(customDoc);

      expect(v9['foto']['intervalSec'], 30); // Bevarat
      final stops = v9['transit']['stops'] as List;
      final stop = stops.first as Map<String, dynamic>;
      expect(stop['walkMinutes'], 2); // INTE överskrivet av rotens 7
      expect(stop['filter']['modes'], ['bus']); // INTE överskrivet av rotens train
      expect(stop['filter']['destinations'], ['Stoeryd']); // INTE överskrivet
    });
  });

  group('FAS 6c — transformV9ToV10: Icke-destruktiv uppgradering till v10', () {
    test('1. v9-dokument utan theme får version 10 och standardtema light', () {
      final v9Doc = {
        'version': 9,
        'schedule': [
          {'start': '07:00', 'scene': 'standard'},
        ],
        'scenes': {
          'standard': {
            'name': 'Standard',
            'layout': 'board',
            'modules': {'main': 'veckotavla'},
          },
        },
        'foto': {'intervalSec': 20},
      };

      final v10 = transformV9ToV10(v9Doc);

      expect(v10['version'], 10);
      expect(v10['theme'], isNotNull);
      final theme = v10['theme'] as Map<String, dynamic>;
      expect(theme['mode'], 'light');
      expect(theme['darkFrom'], '18:00');
      expect(theme['darkTo'], '07:00');
      expect(v10['foto']['intervalSec'], 20); // Bevarat
      expect(v10['schedule'], isNotEmpty); // Bevarat
    });

    test('2. Redan anpassat theme bevaras vid uppgradering', () {
      final customDoc = {
        'version': 9,
        'theme': {
          'mode': 'auto',
          'darkFrom': '19:30',
          'darkTo': '06:45',
        },
      };

      final v10 = transformV9ToV10(customDoc);

      expect(v10['version'], 10);
      final theme = v10['theme'] as Map<String, dynamic>;
      expect(theme['mode'], 'auto');
      expect(theme['darkFrom'], '19:30');
      expect(theme['darkTo'], '06:45');
    });

    test('3. transformV9ToV10 är idempotent', () {
      final v9Doc = {
        'version': 9,
        'foto': {'intervalSec': 15},
      };

      final firstPass = transformV9ToV10(v9Doc);
      final secondPass = transformV9ToV10(firstPass);

      expect(secondPass, equals(firstPass));
      expect(secondPass['version'], 10);
    });
  });
}
