import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/settings/display_status_card.dart';

void main() {
  group('DisplayStatusData - isOnline', () {
    final now = DateTime(2026, 9, 10, 14, 0, 0);

    test('returns false when lastSeen is null', () {
      const status = DisplayStatusData();
      expect(status.isOnline(now), isFalse);
    });

    test('returns true when lastSeen is within 12 minutes', () {
      final status5m = DisplayStatusData(
        lastSeen: now.subtract(const Duration(minutes: 5)),
      );
      expect(status5m.isOnline(now), isTrue);

      final status11m = DisplayStatusData(
        lastSeen: now.subtract(const Duration(minutes: 11)),
      );
      expect(status11m.isOnline(now), isTrue);
    });

    test('returns false when lastSeen is 12 minutes or older', () {
      final status12m = DisplayStatusData(
        lastSeen: now.subtract(const Duration(minutes: 12)),
      );
      expect(status12m.isOnline(now), isFalse);

      final status30m = DisplayStatusData(
        lastSeen: now.subtract(const Duration(minutes: 30)),
      );
      expect(status30m.isOnline(now), isFalse);
    });
  });

  group('DisplayStatusData - formatStatusText', () {
    final now = DateTime(2026, 9, 10, 14, 30, 0);

    test('returns Offline (ej ansluten) when lastSeen is null', () {
      const status = DisplayStatusData();
      expect(status.formatStatusText(now), 'Offline (ej ansluten)');
    });

    test('returns Online when lastSeen is within 12 minutes', () {
      final status = DisplayStatusData(
        lastSeen: now.subtract(const Duration(minutes: 2)),
      );
      expect(status.formatStatusText(now), 'Online');
    });

    test('returns Offline sedan HH:mm when lastSeen is earlier today', () {
      final status = DisplayStatusData(
        lastSeen: DateTime(2026, 9, 10, 14, 5, 0),
      );
      expect(status.formatStatusText(now), 'Offline sedan 14:05');
    });

    test('returns Offline sedan d/M HH:mm when lastSeen is on a previous day', () {
      final status = DisplayStatusData(
        lastSeen: DateTime(2026, 9, 8, 9, 15, 0),
      );
      expect(status.formatStatusText(now), 'Offline sedan 8/9 09:15');
    });
  });

  group('DisplayStatusData - formatUptime', () {
    final now = DateTime(2026, 9, 10, 14, 0, 0);

    test('returns – when startedAt is null', () {
      const status = DisplayStatusData();
      expect(status.formatUptime(now), '–');
    });

    test('returns minutes when under 1 hour', () {
      final status = DisplayStatusData(
        startedAt: now.subtract(const Duration(minutes: 42)),
      );
      expect(status.formatUptime(now), '42 min');
    });

    test('returns hours and minutes when under 1 day', () {
      final status = DisplayStatusData(
        startedAt: now.subtract(const Duration(hours: 3, minutes: 15)),
      );
      expect(status.formatUptime(now), '3 h 15 min');
    });

    test('returns days and hours when 1 day or more', () {
      final status = DisplayStatusData(
        startedAt: now.subtract(const Duration(days: 4, hours: 7, minutes: 12)),
      );
      expect(status.formatUptime(now), '4 d 7 h');
    });
  });

  group('DisplayStatusData - formatSceneWithSource', () {
    test('returns – when activeScene is empty', () {
      const status = DisplayStatusData();
      expect(status.formatSceneWithSource(), '–');
    });

    test('formats scene and known sources correctly', () {
      expect(
        const DisplayStatusData(activeScene: 'morgon', sceneSource: 'schedule')
            .formatSceneWithSource(),
        'Morgon (schema)',
      );
      expect(
        const DisplayStatusData(activeScene: 'standard', sceneSource: 'manual')
            .formatSceneWithSource(),
        'Standard (manuell)',
      );
      expect(
        const DisplayStatusData(activeScene: 'natt', sceneSource: 'night_toggle')
            .formatSceneWithSource(),
        'Natt (nattknapp)',
      );
      expect(
        const DisplayStatusData(activeScene: 'person', sceneSource: 'person')
            .formatSceneWithSource(),
        'Person (person)',
      );
    });

    test('formats scene without source if source is empty', () {
      expect(
        const DisplayStatusData(activeScene: 'morgon', sceneSource: '')
            .formatSceneWithSource(),
        'Morgon',
      );
    });
  });

  group('DisplayStatusData - formatHealthRowText', () {
    test('formats all ok and lowStimuli off correctly', () {
      const status = DisplayStatusData(
        syncOk: true,
        transitOk: true,
        weatherOk: true,
        configVersion: 9,
        lowStimuli: false,
      );
      expect(
        status.formatHealthRowText(),
        'Synk ✓ · Tåg ✓ · Väder ✓ · v9 · Lågstimuli av · Tema ljust',
      );
    });

    test('formats degraded weather and lowStimuli on correctly', () {
      const status = DisplayStatusData(
        syncOk: true,
        transitOk: true,
        weatherOk: false,
        configVersion: 9,
        lowStimuli: true,
      );
      expect(
        status.formatHealthRowText(),
        'Synk ✓ · Tåg ✓ · Väder ⚠ · v9 · Lågstimuli på · Tema ljust',
      );
    });

    test('formats multiple failures correctly', () {
      const status = DisplayStatusData(
        syncOk: false,
        transitOk: false,
        weatherOk: false,
        configVersion: 10,
        lowStimuli: false,
      );
      expect(
        status.formatHealthRowText(),
        'Synk ⚠ · Tåg ⚠ · Väder ⚠ · v10 · Lågstimuli av · Tema ljust',
      );
    });
  });

  group('DisplayStatusData - fromMap', () {
    test('handles empty/null map gracefully', () {
      final status = DisplayStatusData.fromMap(null);
      expect(status.lastSeen, isNull);
      expect(status.activeScene, isEmpty);
      expect(status.sceneSource, isEmpty);
      expect(status.buildVersion, isEmpty);
      expect(status.startedAt, isNull);
      expect(status.testMode, isFalse);
      expect(status.lastError, isNull);
      expect(status.configVersion, 10);
      expect(status.syncOk, isTrue);
      expect(status.transitOk, isTrue);
      expect(status.weatherOk, isTrue);
      expect(status.lowStimuli, isFalse);
      expect(status.theme, 'light');
      expect(status.themeMode, 'light');
    });

    test('parses timestamps, booleans and strings correctly', () {
      final ts = Timestamp.fromDate(DateTime(2026, 9, 10, 12, 0, 0));
      final map = {
        'lastSeen': ts,
        'activeScene': 'morgon',
        'sceneSource': 'schedule',
        'buildVersion': '1.0.0+18',
        'startedAt': '2026-09-10T06:00:00.000',
        'testMode': true,
        'lastError': 'Nätverksfel vid hämtning',
        'configVersion': 10,
        'syncOk': true,
        'transitOk': true,
        'weatherOk': false,
        'lowStimuli': true,
        'theme': 'dark',
        'themeMode': 'auto',
      };

      final status = DisplayStatusData.fromMap(map);
      expect(status.lastSeen, ts.toDate());
      expect(status.activeScene, 'morgon');
      expect(status.sceneSource, 'schedule');
      expect(status.buildVersion, '1.0.0+18');
      expect(status.startedAt, DateTime(2026, 9, 10, 6, 0, 0));
      expect(status.testMode, isTrue);
      expect(status.lastError, 'Nätverksfel vid hämtning');
      expect(status.configVersion, 10);
      expect(status.syncOk, isTrue);
      expect(status.transitOk, isTrue);
      expect(status.weatherOk, isFalse);
      expect(status.lowStimuli, isTrue);
      expect(status.theme, 'dark');
      expect(status.themeMode, 'auto');
    });

    test('supports fallback field names appVersion and activeSceneId', () {
      final map = {
        'appVersion': '1.0.0+18',
        'activeSceneId': 'kvall',
      };
      final status = DisplayStatusData.fromMap(map);
      expect(status.buildVersion, '1.0.0+18');
      expect(status.activeScene, 'kvall');
    });
  });

  group('DisplayStatusData - formatThemeText', () {
    test('formats manual light/dark correctly', () {
      const light = DisplayStatusData(theme: 'light', themeMode: 'light');
      expect(light.formatThemeText(), 'Tema ljust');

      const dark = DisplayStatusData(theme: 'dark', themeMode: 'dark');
      expect(dark.formatThemeText(), 'Tema mörkt');
    });

    test('formats auto theme with effective state correctly', () {
      const autoDark = DisplayStatusData(theme: 'dark', themeMode: 'auto');
      expect(autoDark.formatThemeText(), 'Tema mörkt (auto)');

      const autoLight = DisplayStatusData(theme: 'light', themeMode: 'auto');
      expect(autoLight.formatThemeText(), 'Tema ljust (auto)');
    });
  });

  group('DisplayStatusData - formatHealthRowText with theme', () {
    test('includes theme in health row string', () {
      const status = DisplayStatusData(
        syncOk: true,
        transitOk: true,
        weatherOk: false,
        configVersion: 10,
        lowStimuli: false,
        theme: 'dark',
        themeMode: 'auto',
      );
      final text = status.formatHealthRowText();
      expect(text, 'Synk ✓ · Tåg ✓ · Väder ⚠ · v10 · Lågstimuli av · Tema mörkt (auto)');
    });
  });
}
