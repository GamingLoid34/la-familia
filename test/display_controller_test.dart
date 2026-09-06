import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/app_theme.dart';
import 'package:la_familia/screens/display/display_controller.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'lowStimuli': false});
    AppTheme.lowStimuli = false;
  });

  group('FAS 2 & 3 — Storskärm: DisplayController', () {
    test('1. home nollställer weekOffset och manuell scen', () {
      final now = DateTime(2026, 9, 2, 14, 0); // dagtid
      final controller = DisplayController(nowProvider: () => now);

      controller.handleCommand('week_next');
      controller.handleCommand('week_next');
      expect(controller.weekOffset, 2);

      controller.handleCommand('night_toggle');
      expect(controller.manualSceneId, 'natt');
      expect(controller.isNight(now), true);

      // Kör home
      controller.handleCommand('home');
      expect(controller.weekOffset, 0);
      expect(controller.manualSceneId, isNull);
      expect(controller.isNight(now), false);
      expect(controller.feedbackMessage, 'Aktuell vecka');

      controller.dispose();
    });

    test('2. week_next/prev begränsas till ±8 veckor', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final controller = DisplayController(nowProvider: () => now);

      // Bläddra framåt 12 gånger -> ska stanna vid 8
      for (var i = 0; i < 12; i++) {
        controller.handleCommand('week_next');
      }
      expect(controller.weekOffset, 8);

      // Bläddra bakåt 20 gånger -> ska stanna vid -8
      for (var i = 0; i < 20; i++) {
        controller.handleCommand('week_prev');
      }
      expect(controller.weekOffset, -8);

      controller.dispose();
    });

    test(
        '3. night_toggle-övergångarna (schema-natt → vaken-överstyrning → schemagräns rensar)',
        () {
      final nightTime = DateTime(2026, 9, 2, 23, 0); // natt (22:00–05:30)
      final morningTime = DateTime(2026, 9, 3, 6, 0); // morgon/dag
      final dayTime = DateTime(2026, 9, 3, 14, 0); // dag
      final nextNight = DateTime(2026, 9, 3, 23, 0); // nästa natt

      var currentTime = nightTime;
      final controller = DisplayController(nowProvider: () => currentTime);

      // 1. Vid natt: schemat är natt
      expect(controller.isNight(currentTime), true);
      expect(controller.manualSceneId, isNull);

      // 2. Tryck natt_toggle under schemanatt -> vaken-överstyrning till standard
      controller.handleCommand('night_toggle');
      expect(controller.manualSceneId, 'standard');
      expect(controller.isNight(currentTime), false);
      expect(controller.feedbackMessage, 'Veckotavlan');

      // 3. Tiden rullar förbi morgongränsen (05:30) -> schemagräns nådd
      currentTime = morningTime;
      controller.checkScheduleBoundary(currentTime);
      expect(controller.manualSceneId, isNull);
      expect(controller.isNight(currentTime), false);

      // 4. Tryck natt_toggle under schemadag -> natt-överstyrning
      currentTime = dayTime;
      controller.handleCommand('night_toggle');
      expect(controller.manualSceneId, 'natt');
      expect(controller.isNight(currentTime), true);
      expect(controller.feedbackMessage, 'Natt');

      // 5. Tiden rullar förbi kvällsgränsen (22:00) -> schemagräns nådd
      currentTime = nextNight;
      controller.checkScheduleBoundary(currentTime);
      expect(controller.manualSceneId, isNull);
      expect(controller.isNight(currentTime), true);

      controller.dispose();
    });

    test('3b. night_toggle avbryts utan ändring om målscenen saknas i konfig', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final customConfig = DisplayConfig(
        version: 1,
        scenes: {
          'custom': const DisplayScene(
            id: 'custom',
            name: 'Special',
            layout: 'fullscreen',
            modules: {'main': 'klocka'},
          ),
        },
        schedule: [DisplayScheduleEntry(start: '00:00', scene: 'custom')],
      );

      final controller = DisplayController(
        nowProvider: () => now,
        configProvider: () => customConfig,
      );

      // 'natt' saknas i customConfig -> ingen ändring
      controller.handleCommand('night_toggle');
      expect(controller.manualSceneId, isNull);
      expect(controller.effectiveSceneId(now), 'custom');

      controller.dispose();
    });

    test('4. Okända och reserverade kommandon ignoreras utan fel', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final controller = DisplayController(nowProvider: () => now);

      // Okänt kommando kraschar inte
      expect(() => controller.handleCommand('unknown_foo'), returnsNormally);
      expect(controller.weekOffset, 0);

      // Reserverade kommandon
      expect(() => controller.handleCommand('today'), returnsNormally);
      expect(() => controller.handleCommand('meals'), returnsNormally);
      expect(controller.weekOffset, 0);

      controller.dispose();
    });

    test('5. Auto-hem återställer efter satt tid', () async {
      final now = DateTime(2026, 9, 2, 14, 0);
      final controller = DisplayController(
        nowProvider: () => now,
        autoHomeDuration: const Duration(milliseconds: 50),
      );

      controller.handleCommand('week_next');
      expect(controller.weekOffset, 1);

      // Vänta längre än 50 ms
      await Future.delayed(const Duration(milliseconds: 80));
      expect(controller.weekOffset, 0);

      controller.dispose();
    });

    test('6. low_stimuli_toggle växlar inställningen och sparas', () async {
      final now = DateTime(2026, 9, 2, 14, 0);
      final controller = DisplayController(nowProvider: () => now);

      expect(AppTheme.lowStimuli, false);
      controller.handleCommand('low_stimuli_toggle');
      expect(AppTheme.lowStimuli, true);
      expect(controller.feedbackMessage, 'Lågstimuli på');

      await Future.delayed(const Duration(milliseconds: 30));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('lowStimuli'), true);

      controller.handleCommand('low_stimuli_toggle');
      expect(AppTheme.lowStimuli, false);
      expect(controller.feedbackMessage, 'Lågstimuli av');

      await Future.delayed(const Duration(milliseconds: 30));
      expect(prefs.getBool('lowStimuli'), false);

      controller.dispose();
    });

    test('7. reload anropar onReload och sätter feedback', () {
      var reloadCalled = false;
      final controller = DisplayController(
        onReload: ({replaceUrl}) => reloadCalled = true,
      );

      controller.handleCommand('reload');
      expect(reloadCalled, true);
      expect(controller.feedbackMessage, 'Laddar om…');

      controller.dispose();
    });

    test('8. scene:<id> styrning och validering', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final controller = DisplayController(nowProvider: () => now);

      // Sätt morgon manuellt
      controller.handleCommand('scene:morgon');
      expect(controller.manualSceneId, 'morgon');
      expect(controller.effectiveSceneId(now), 'morgon');
      expect(controller.feedbackMessage, 'Morgon');

      // Byt till kväll
      controller.handleCommand('scene:kvall');
      expect(controller.manualSceneId, 'kvall');
      expect(controller.effectiveSceneId(now), 'kvall');
      expect(controller.feedbackMessage, 'Kväll');

      // Sätt natt manuellt
      controller.handleCommand('scene:natt');
      expect(controller.manualSceneId, 'natt');
      expect(controller.effectiveSceneId(now), 'natt');
      expect(controller.feedbackMessage, 'Natt');

      // Byt till standard
      controller.handleCommand('scene:standard');
      expect(controller.manualSceneId, 'standard');
      expect(controller.effectiveSceneId(now), 'standard');
      expect(controller.feedbackMessage, 'Veckotavlan');

      // Okänd scen ignoreras utan att ändra manuell scen
      controller.handleCommand('scene:okand_xyz');
      expect(controller.manualSceneId, 'standard');

      controller.dispose();
    });

    test('9. 10-minuters återgångstimer för manuell scen (timeout återgår till schema)', () async {
      final now = DateTime(2026, 9, 2, 14, 0); // dagtid -> scheduled är standard
      final controller = DisplayController(
        nowProvider: () => now,
        sceneTimeoutDuration: const Duration(milliseconds: 60),
      );

      controller.handleCommand('scene:morgon');
      expect(controller.manualSceneId, 'morgon');
      expect(controller.effectiveSceneId(now), 'morgon');

      // Efter timeout återgår till schemalagd scen (standard)
      await Future.delayed(const Duration(milliseconds: 90));
      expect(controller.manualSceneId, isNull);
      expect(controller.effectiveSceneId(now), 'standard');

      controller.dispose();
    });

    test('10. Nytt scenkommando förnyar timeouten', () async {
      final now = DateTime(2026, 9, 2, 14, 0);
      final controller = DisplayController(
        nowProvider: () => now,
        sceneTimeoutDuration: const Duration(milliseconds: 70),
      );

      controller.handleCommand('scene:morgon');
      expect(controller.manualSceneId, 'morgon');

      // Vänta 45 ms (innan timeout) och skicka nytt scenkommando
      await Future.delayed(const Duration(milliseconds: 45));
      controller.handleCommand('scene:kvall');
      expect(controller.manualSceneId, 'kvall');

      // Efter 40 ms från senaste (totalt 85 ms) är kväll fortfarande aktiv p.g.a. förnyad timer
      await Future.delayed(const Duration(milliseconds: 40));
      expect(controller.manualSceneId, 'kvall');

      // Efter ytterligare 45 ms har även nya timern löpt ut
      await Future.delayed(const Duration(milliseconds: 45));
      expect(controller.manualSceneId, isNull);

      controller.dispose();
    });

    test('11. Home eller schemagräns avbryter återgångstimern omedelbart', () async {
      final now = DateTime(2026, 9, 2, 14, 0);
      final controller = DisplayController(
        nowProvider: () => now,
        sceneTimeoutDuration: const Duration(milliseconds: 100),
      );

      controller.handleCommand('scene:morgon');
      expect(controller.manualSceneId, 'morgon');

      // Home nollställer omedelbart
      controller.handleCommand('home');
      expect(controller.manualSceneId, isNull);

      controller.dispose();
    });
  });
}
