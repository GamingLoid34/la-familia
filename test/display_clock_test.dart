import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/screens/display/display_clock.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('sv_SE', null);
  });

  tearDown(() {
    DisplayClock.reset();
    DisplayClock.setRealNowProvider(DateTime.now);
  });

  group('DisplayClock', () {
    test('standardläge använder verklig tid och isTestTime är falskt', () {
      DisplayClock.reset();
      expect(DisplayClock.isTestTime, isFalse);
      expect(DisplayClock.offset, Duration.zero);

      final before = DateTime.now();
      final clockNow = DisplayClock.now();
      final after = DateTime.now();

      expect(clockNow.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(clockNow.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('giltig testTime med display=1 beräknar korrekt offset', () {
      final realNow = DateTime(2026, 9, 8, 12, 0);
      final uri = Uri.parse('http://localhost:8080/?display=1&testTime=2026-09-07T05:29');

      DisplayClock.init(
        uri: uri,
        realNowProvider: () => realNow,
      );

      expect(DisplayClock.isTestTime, isTrue);
      final expectedTarget = DateTime(2026, 9, 7, 5, 29);
      expect(DisplayClock.offset, expectedTarget.difference(realNow));
      expect(DisplayClock.now(), expectedTarget);
    });

    test('klockan tickar framåt med verklig tid', () {
      var currentReal = DateTime(2026, 9, 8, 12, 0);
      final uri = Uri.parse('http://localhost:8080/?display=1&testTime=2026-09-07T05:29');

      DisplayClock.init(
        uri: uri,
        realNowProvider: () => currentReal,
      );

      expect(DisplayClock.now(), DateTime(2026, 9, 7, 5, 29));

      // Simulera att verklig tid går 1 minut framåt
      currentReal = currentReal.add(const Duration(minutes: 1));
      expect(DisplayClock.now(), DateTime(2026, 9, 7, 5, 30));
    });

    test('testTime ignoreras om display != 1', () {
      final realNow = DateTime(2026, 9, 8, 12, 0);
      final uri = Uri.parse('http://localhost:8080/?testTime=2026-09-07T05:29');

      DisplayClock.init(
        uri: uri,
        realNowProvider: () => realNow,
      );

      expect(DisplayClock.isTestTime, isFalse);
      expect(DisplayClock.offset, Duration.zero);
      expect(DisplayClock.now(), realNow);
    });

    test('ogiltigt datumformat ignoreras', () {
      final realNow = DateTime(2026, 9, 8, 12, 0);
      final uri = Uri.parse('http://localhost:8080/?display=1&testTime=inte-ett-datum');

      DisplayClock.init(
        uri: uri,
        realNowProvider: () => realNow,
      );

      expect(DisplayClock.isTestTime, isFalse);
      expect(DisplayClock.offset, Duration.zero);
      expect(DisplayClock.now(), realNow);
    });

    test('formatOffset formaterar positiv och negativ duration korrekt', () {
      expect(DisplayClock.formatOffset(const Duration(hours: 2, minutes: 15)), '+2h 15m');
      expect(DisplayClock.formatOffset(const Duration(hours: 0, minutes: 5)), '+0h 5m');
      expect(DisplayClock.formatOffset(-const Duration(hours: 1, minutes: 30)), '-1h 30m');
      expect(DisplayClock.formatOffset(Duration.zero), '+0h 0m');
    });

    test('formatBannerText formaterar enligt specifikationen', () {
      final dt = DateTime(2026, 9, 7, 5, 29); // Måndag 7 sep 05:29
      final text = DisplayClock.formatBannerText(dt);
      expect(text, '⚠ TESTTID · mån 7 sep 05:29');
    });
  });
}
