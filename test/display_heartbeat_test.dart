import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/display_clock.dart';
import 'package:la_familia/screens/display/display_heartbeat.dart';
import 'package:la_familia/screens/display/display_log.dart';

void main() {
  group('DisplayHeartbeat - buildPayload', () {
    test('constructs payload with expected keys and values', () {
      String scene = 'morgon';
      String source = 'schedule';
      bool isTest = false;
      String? error;

      final heartbeat = DisplayHeartbeat(
        familyId: 'fam_123',
        activeSceneProvider: () => scene,
        sceneSourceProvider: () => source,
        testModeProvider: () => isTest,
        lastErrorProvider: () => error,
        configVersionProvider: () => 10,
        syncOkProvider: () => true,
        transitOkProvider: () => true,
        weatherOkProvider: () => true,
        lowStimuliProvider: () => false,
      );

      final payload = heartbeat.buildPayload();

      expect(payload['activeScene'], 'morgon');
      expect(payload['activeSceneId'], 'morgon');
      expect(payload['sceneSource'], 'schedule');
      expect(payload['appVersion'], DisplayLog.appVersion);
      expect(payload['buildVersion'], DisplayLog.appVersion);
      expect(payload['configVersion'], 10);
      expect(payload['syncOk'], isTrue);
      expect(payload['transitOk'], isTrue);
      expect(payload['weatherOk'], isTrue);
      expect(payload['lowStimuli'], isFalse);
      expect(payload['theme'], 'light');
      expect(payload['themeMode'], 'light');
      expect(payload['testMode'], isFalse);
      expect(payload['lastError'], isNull);
      expect(payload['startedAt'], isNotNull);
      expect(payload['lastSeen'], isNotNull);

      // Test with custom health flags and dark theme
      final heartbeatCustom = DisplayHeartbeat(
        familyId: 'fam_123',
        activeSceneProvider: () => 'kvall',
        sceneSourceProvider: () => 'manual',
        configVersionProvider: () => 10,
        syncOkProvider: () => true,
        transitOkProvider: () => true,
        weatherOkProvider: () => false,
        lowStimuliProvider: () => true,
        themeProvider: () => 'dark',
        themeModeProvider: () => 'auto',
        lastErrorProvider: () => 'Väderfel: SMHI timeout',
      );
      final payload2 = heartbeatCustom.buildPayload();
      expect(payload2['activeScene'], 'kvall');
      expect(payload2['sceneSource'], 'manual');
      expect(payload2['weatherOk'], isFalse);
      expect(payload2['lowStimuli'], isTrue);
      expect(payload2['theme'], 'dark');
      expect(payload2['themeMode'], 'auto');
      expect(payload2['lastError'], 'Väderfel: SMHI timeout');

      heartbeat.dispose();
      heartbeatCustom.dispose();
    });
  });

  group('DisplayHeartbeat - testMode & DisplayClock', () {
    setUp(() {
      DisplayClock.reset();
    });

    tearDown(() {
      DisplayClock.reset();
    });

    test('heartbeat utan testTime → testMode false (även med display=1)', () {
      DisplayClock.init(
        uri: Uri.parse('https://la-familia-5d9f5.web.app/?display=1'),
      );
      expect(DisplayClock.isTestTime, isFalse);

      final heartbeat = DisplayHeartbeat(
        familyId: 'fam_123',
        activeSceneProvider: () => 'standard',
        sceneSourceProvider: () => 'schedule',
      );

      final payload = heartbeat.buildPayload();
      expect(payload['testMode'], isFalse);
      heartbeat.dispose();
    });

    test('heartbeat med testTime → testMode true', () {
      DisplayClock.init(
        uri: Uri.parse(
          'https://la-familia-5d9f5.web.app/?display=1&testTime=2026-09-10T14:00',
        ),
      );
      expect(DisplayClock.isTestTime, isTrue);

      final heartbeat = DisplayHeartbeat(
        familyId: 'fam_123',
        activeSceneProvider: () => 'standard',
        sceneSourceProvider: () => 'schedule',
      );

      final payload = heartbeat.buildPayload();
      expect(payload['testMode'], isTrue);
      heartbeat.dispose();
    });
  });

  group('DisplayLog - health flag transitions', () {
    test('transitions syncOk, transitOk, and weatherOk based on logged events', () {
      DisplayLog.instance.clear();
      expect(DisplayLog.instance.syncOk, isTrue);
      expect(DisplayLog.instance.transitOk, isTrue);
      expect(DisplayLog.instance.weatherOk, isTrue);

      // Weather error transitions weatherOk to false
      DisplayLog.instance.log('väder', 'Väderfel: Inget svar från SMHI');
      expect(DisplayLog.instance.weatherOk, isFalse);

      // Weather success transitions back to true
      DisplayLog.instance.log('väder', 'Väder hämtat (10 dagar). Nästa om 30 min.');
      expect(DisplayLog.instance.weatherOk, isTrue);

      // Transit error transitions transitOk to false
      DisplayLog.instance.log('transit-fel', 'Fel vid anrop till displayTransit: 500');
      expect(DisplayLog.instance.transitOk, isFalse);

      // Transit success transitions back to true
      DisplayLog.instance.log('transit', 'displayTransit hämtat (Tranås: 5 avgångar)');
      expect(DisplayLog.instance.transitOk, isTrue);

      // Sync error transitions syncOk to false
      DisplayLog.instance.log('strömfel', 'Fel vid hämtning av schema');
      expect(DisplayLog.instance.syncOk, isFalse);

      // Clear resets all flags
      DisplayLog.instance.clear();
      expect(DisplayLog.instance.syncOk, isTrue);
      expect(DisplayLog.instance.transitOk, isTrue);
      expect(DisplayLog.instance.weatherOk, isTrue);
    });
  });
}
