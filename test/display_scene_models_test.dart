import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';

void main() {
  group('FAS 3 — display_scene_models: Cyklisk schemaupplösning', () {
    final schedule = [
      DisplayScheduleEntry(start: '05:30', scene: 'standard'),
      DisplayScheduleEntry(start: '22:00', scene: 'natt'),
    ];

    test('1. Exakta klockslag med standard-schemat (05:30 och 22:00)', () {
      // 00:00 (midnatt) -> natt (wrap över midnatt från 22:00)
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 0, 0), schedule),
        'natt',
      );

      // 03:00 (natt) -> natt (wrap över midnatt från 22:00)
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 3, 0), schedule),
        'natt',
      );

      // 05:29 (minuten före daggränsen) -> natt
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 5, 29), schedule),
        'natt',
      );

      // 05:30 (exakt morgongränsen) -> standard
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 5, 30), schedule),
        'standard',
      );

      // 12:00 (mitt på dagen) -> standard
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 12, 0), schedule),
        'standard',
      );

      // 21:59 (minuten före kvällsgränsen) -> standard
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 21, 59), schedule),
        'standard',
      );

      // 22:00 (exakt kvällsgränsen) -> natt
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 22, 0), schedule),
        'natt',
      );

      // 23:59 (sista minuten på dygnet) -> natt
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 23, 59), schedule),
        'natt',
      );
    });

    test('2. Osorterad schedule sorteras korrekt internt', () {
      final unsortedSchedule = [
        DisplayScheduleEntry(start: '22:00', scene: 'natt'),
        DisplayScheduleEntry(start: '05:30', scene: 'standard'),
      ];

      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 14, 0), unsortedSchedule),
        'standard',
      );
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 4, 0), unsortedSchedule),
        'natt',
      );
    });

    test('3. Flerdelat schema med flera dag- och kvällsfaser', () {
      final multiSchedule = [
        DisplayScheduleEntry(start: '06:00', scene: 'morgon'),
        DisplayScheduleEntry(start: '09:00', scene: 'standard'),
        DisplayScheduleEntry(start: '17:00', scene: 'middag'),
        DisplayScheduleEntry(start: '21:30', scene: 'natt'),
      ];

      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 5, 0), multiSchedule),
        'natt', // wrap från 21:30
      );
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 6, 0), multiSchedule),
        'morgon',
      );
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 8, 59), multiSchedule),
        'morgon',
      );
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 9, 0), multiSchedule),
        'standard',
      );
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 18, 0), multiSchedule),
        'middag',
      );
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 21, 30), multiSchedule),
        'natt',
      );
    });

    test('4. Tom schedule returnerar fallback "standard"', () {
      expect(
        resolveScheduledScene(DateTime(2026, 9, 5, 12, 0), const []),
        'standard',
      );
    });
  });

  group('FAS 3 — display_scene_models: Parsning och fallback', () {
    test('1. Standard fallback konfiguration är komplett (v3)', () {
      final config = DisplayConfig.defaultConfig();
      expect(config.version, 3);
      expect(config.scenes.containsKey('morgon'), true);
      expect(config.scenes.containsKey('standard'), true);
      expect(config.scenes.containsKey('kvall'), true);
      expect(config.scenes.containsKey('natt'), true);
      expect(config.scenes['morgon']?.layout, 'board');
      expect(config.scenes['standard']?.layout, 'board');
      expect(config.scenes['kvall']?.layout, 'sidebar');
      expect(config.scenes['natt']?.layout, 'fullscreen');
      expect(config.schedule.length, 5);
    });

    test('2. Giltig karta parsas felfritt', () {
      final raw = {
        'version': 2,
        'scenes': {
          'standard': {
            'name': 'Veckotavlan',
            'layout': 'board',
            'modules': {'main': 'veckotavla'},
          },
          'natt': {
            'name': 'Natt',
            'layout': 'fullscreen',
            'modules': {'main': 'natt'},
          },
        },
        'schedule': [
          {'start': '06:00', 'scene': 'standard', 'days': [1, 2, 3, 4, 5]},
          {'start': '23:00', 'scene': 'natt'},
        ],
      };

      var fallbackCalled = false;
      final config = DisplayConfig.parseWithFallback(
        raw,
        onFallbackTriggered: (_) => fallbackCalled = true,
      );

      expect(fallbackCalled, false);
      expect(config.version, 2);
      expect(config.scenes.length, 2);
      expect(config.schedule.first.start, '06:00');
      expect(config.schedule.first.days, [1, 2, 3, 4, 5]);
      expect(config.schedule.last.days, null);
    });

    test('3. Ogiltig data (null, saknade scener) triggar fallback', () {
      var fallbackReason = '';
      final configNull = DisplayConfig.parseWithFallback(
        null,
        onFallbackTriggered: (r) => fallbackReason = r,
      );
      expect(fallbackReason.isNotEmpty, true);
      expect(configNull.scenes.containsKey('standard'), true);

      fallbackReason = '';
      final configNoStandard = DisplayConfig.parseWithFallback(
        {
          'version': 1,
          'scenes': {
            'annan': {'layout': 'board'},
          },
          'schedule': [
            {'start': '00:00', 'scene': 'annan'},
          ],
        },
        onFallbackTriggered: (r) => fallbackReason = r,
      );
      expect(fallbackReason.contains('standard'), true);
      expect(configNoStandard.scenes.containsKey('standard'), true);
    });

    test('4. Tom schedule triggar fallback', () {
      var fallbackReason = '';
      final configEmptySchedule = DisplayConfig.parseWithFallback(
        {
          'version': 1,
          'scenes': {
            'standard': {'layout': 'board'},
          },
          'schedule': [],
        },
        onFallbackTriggered: (r) => fallbackReason = r,
      );
      expect(fallbackReason.isNotEmpty, true);
      expect(configEmptySchedule.schedule.length, 5);
    });
  });

  group('FAS 4 — display_scene_models: Veckodagsstyrd schemaupplösning', () {
    final v3Schedule = DisplayConfig.defaultConfig().schedule;

    test('1. Vardagar (måndag-fredag): 05:30 morgon, 08:30 standard, 17:00 kväll, 22:00 natt', () {
      // Måndag 2026-09-07 (DateTime.monday = 1)
      final monday = DateTime(2026, 9, 7);
      expect(monday.weekday, DateTime.monday);

      expect(resolveScheduledScene(DateTime(2026, 9, 7, 5, 30), v3Schedule), 'morgon');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 7, 0), v3Schedule), 'morgon');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 8, 29), v3Schedule), 'morgon');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 8, 30), v3Schedule), 'standard');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 12, 0), v3Schedule), 'standard');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 16, 59), v3Schedule), 'standard');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 17, 0), v3Schedule), 'kvall');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 21, 59), v3Schedule), 'kvall');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 22, 0), v3Schedule), 'natt');
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 23, 59), v3Schedule), 'natt');
    });

    test('2. Helg (lördag-söndag): 07:30 standard (inte 05:30 morgon)', () {
      // Lördag 2026-09-05 (DateTime.saturday = 6)
      final saturday = DateTime(2026, 9, 5);
      expect(saturday.weekday, DateTime.saturday);

      // Kl 06:15 på lördag morgon -> har inte startat 07:30 standard än.
      // Ska wrappa till fredag kvälls sista post (22:00 natt)
      expect(resolveScheduledScene(DateTime(2026, 9, 5, 6, 15), v3Schedule), 'natt');
      expect(resolveScheduledScene(DateTime(2026, 9, 5, 7, 29), v3Schedule), 'natt');
      expect(resolveScheduledScene(DateTime(2026, 9, 5, 7, 30), v3Schedule), 'standard');
      expect(resolveScheduledScene(DateTime(2026, 9, 5, 8, 0), v3Schedule), 'standard');
      expect(resolveScheduledScene(DateTime(2026, 9, 5, 8, 30), v3Schedule), 'standard');
    });

    test('3. Wrap över midnatt måndag 03:00 -> hämtar söndagens sista post', () {
      // Måndag 03:00
      expect(resolveScheduledScene(DateTime(2026, 9, 7, 3, 0), v3Schedule), 'natt');
    });

    test('4. DisplayScheduleEntry toMap och fromMap med days', () {
      final entryWithDays = DisplayScheduleEntry(
        start: '06:30',
        scene: 'morgon',
        days: [1, 2, 3],
      );
      final map = entryWithDays.toMap();
      expect(map['start'], '06:30');
      expect(map['scene'], 'morgon');
      expect(map['days'], [1, 2, 3]);

      final parsed = DisplayScheduleEntry.fromMap(map);
      expect(parsed.start, '06:30');
      expect(parsed.scene, 'morgon');
      expect(parsed.days, [1, 2, 3]);

      final entryWithoutDays = DisplayScheduleEntry(
        start: '22:00',
        scene: 'natt',
      );
      expect(entryWithoutDays.toMap().containsKey('days'), false);

      final parsedNoDays = DisplayScheduleEntry.fromMap({'start': '22:00', 'scene': 'natt'});
      expect(parsedNoDays.days, null);
    });
  });
}
