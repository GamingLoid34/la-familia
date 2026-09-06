import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/schedule_time_utils.dart';

void main() {
  group('inferBlockEndTimes', () {
    test('kedja fylls, sista utan slut, returnerar antal', () {
      final events = <Map<String, dynamic>>[
        {'date': '2026-09-07', 'time': '07:30'},
        {'date': '2026-09-07', 'time': '10:00'},
        {'date': '2026-09-07', 'time': '11:15'},
        {'date': '2026-09-07', 'time': '12:00'},
        {'date': '2026-09-07', 'time': '13:30'},
        {'date': '2026-09-07', 'time': '14:45'},
        {'date': '2026-09-07', 'time': '16:00'},
      ];

      final filled = inferBlockEndTimes(events);
      expect(filled, equals(6));

      expect(events[0]['endTime'], equals('10:00'));
      expect(events[1]['endTime'], equals('11:15'));
      expect(events[2]['endTime'], equals('12:00'));
      expect(events[3]['endTime'], equals('13:30'));
      expect(events[4]['endTime'], equals('14:45'));
      expect(events[5]['endTime'], equals('16:00'));
      expect(events[6]['endTime'], isNull);
    });

    test('rad med befintlig endTime rörs inte', () {
      final events = <Map<String, dynamic>>[
        {'date': '2026-09-07', 'time': '07:30', 'endTime': '09:00'},
        {'date': '2026-09-07', 'time': '10:00'},
        {'date': '2026-09-07', 'time': '11:15'},
      ];

      final filled = inferBlockEndTimes(events);
      expect(filled, equals(1));

      expect(events[0]['endTime'], equals('09:00'));
      expect(events[1]['endTime'], equals('11:15'));
      expect(events[2]['endTime'], isNull);
    });

    test('två olika datum blandade i oordning -> korrekt per dag utan läckage', () {
      final events = <Map<String, dynamic>>[
        {'date': '2026-09-08', 'time': '13:00'},
        {'date': '2026-09-07', 'time': '10:00'},
        {'date': '2026-09-08', 'time': '09:00'},
        {'date': '2026-09-07', 'time': '08:00'},
      ];

      final filled = inferBlockEndTimes(events);
      expect(filled, equals(2));

      final sep7_08 = events.firstWhere((e) => e['date'] == '2026-09-07' && e['time'] == '08:00');
      final sep7_10 = events.firstWhere((e) => e['date'] == '2026-09-07' && e['time'] == '10:00');
      expect(sep7_08['endTime'], equals('10:00'));
      expect(sep7_10['endTime'], isNull);

      final sep8_09 = events.firstWhere((e) => e['date'] == '2026-09-08' && e['time'] == '09:00');
      final sep8_13 = events.firstWhere((e) => e['date'] == '2026-09-08' && e['time'] == '13:00');
      expect(sep8_09['endTime'], equals('13:00'));
      expect(sep8_13['endTime'], isNull);
    });

    test('två rader med samma time -> ingen ifyllnad dem emellan', () {
      final events = <Map<String, dynamic>>[
        {'date': '2026-09-07', 'time': '09:00'},
        {'date': '2026-09-07', 'time': '09:00'},
        {'date': '2026-09-07', 'time': '11:00'},
      ];

      final filled = inferBlockEndTimes(events);
      expect(filled, equals(1));
      expect(events[0]['endTime'], isNull);
      expect(events[1]['endTime'], equals('11:00'));
      expect(events[2]['endTime'], isNull);
    });

    test('tom lista -> 0', () {
      final events = <Map<String, dynamic>>[];
      final filled = inferBlockEndTimes(events);
      expect(filled, equals(0));
    });
  });

  group('durationLabelHm', () {
    test('07:30 till 09:00 -> 1 t 30 min', () {
      expect(durationLabelHm('07:30', '09:00'), equals('1 t 30 min'));
    });

    test('12:00 till 12:45 -> 45 min', () {
      expect(durationLabelHm('12:00', '12:45'), equals('45 min'));
    });

    test('08:00 till 10:00 -> 2 t', () {
      expect(durationLabelHm('08:00', '10:00'), equals('2 t'));
    });

    test('10:00 till 10:00 -> tom sträng', () {
      expect(durationLabelHm('10:00', '10:00'), equals(''));
    });

    test('ogiltig sträng -> tom sträng', () {
      expect(durationLabelHm('abc', '10:00'), equals(''));
      expect(durationLabelHm('10:00', 'xyz'), equals(''));
      expect(durationLabelHm('', ''), equals(''));
    });
  });
}
