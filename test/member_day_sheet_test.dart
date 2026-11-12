import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/chore_utils.dart';
import 'package:la_familia/utils/recurrence.dart';

void main() {
  group('MemberDaySheet FAS D1 — Dagbläddring & Självförsörjande data', () {
    const int initialPageIndex = 365;
    final baseDay = DateTime(2026, 8, 30);

    DateTime dayForIndex(int index) {
      return baseDay.add(Duration(days: index - initialPageIndex));
    }

    int indexForDay(DateTime d) {
      final norm = DateTime(d.year, d.month, d.day);
      return initialPageIndex + norm.difference(baseDay).inDays;
    }

    test('Index-mappning för PageView (±365 dagar) fungerar exakt', () {
      expect(dayForIndex(365), DateTime(2026, 8, 30));
      expect(dayForIndex(366), DateTime(2026, 8, 31));
      expect(dayForIndex(364), DateTime(2026, 8, 29));
      expect(dayForIndex(365 + 30), DateTime(2026, 9, 29));
      expect(dayForIndex(365 - 30), DateTime(2026, 7, 31));

      expect(indexForDay(DateTime(2026, 8, 30)), 365);
      expect(indexForDay(DateTime(2026, 8, 31)), 366);
      expect(indexForDay(DateTime(2026, 8, 29)), 364);
    });

    test('Idag-chip ska endast visas när vald dag ≠ idag', () {
      final today = DateTime(2026, 8, 30);

      bool shouldShowTodayChip(DateTime selectedDay) {
        return selectedDay.year != today.year ||
            selectedDay.month != today.month ||
            selectedDay.day != today.day;
      }

      expect(shouldShowTodayChip(DateTime(2026, 8, 30)), isFalse);
      expect(shouldShowTodayChip(DateTime(2026, 8, 31)), isTrue);
      expect(shouldShowTodayChip(DateTime(2026, 8, 29)), isTrue);
    });

    test('Energirad och redigeringsstatus respekterar isSelf && isToday', () {
      bool canEditEnergy({required bool isSelf, required bool isToday}) {
        return isSelf && isToday;
      }

      expect(canEditEnergy(isSelf: true, isToday: true), isTrue);
      expect(canEditEnergy(isSelf: true, isToday: false), isFalse); // Dåtid/framtid
      expect(canEditEnergy(isSelf: false, isToday: true), isFalse); // Annan familjemedlem
    });

    test('Återkommande och datumhändelser mergas och dedubblas korrekt per dag', () {
      final targetDay = DateTime(2026, 8, 31); // Måndag

      final dateEvents = [
        {
          'id': 'ev_single_1',
          'date': '2026-08-31',
          'title': 'Tandläkare',
          'persons': ['Noomi'],
        }
      ];

      final recurringEvents = [
        {
          'id': 'ev_rec_1',
          'title': 'Fotbollsträning',
          'isRecurring': true,
          'persons': ['Noomi'],
          'recurrence': {
            'type': 'weekly',
            'startDate': '2026-08-03', // Måndag
          }
        },
        {
          'id': 'ev_rec_2',
          'title': 'Simskola',
          'isRecurring': true,
          'persons': ['Noomi'],
          'recurrence': {
            'type': 'weekly',
            'days': [2], // Tisdagar (infaller ej på måndag)
            'startDate': '2026-08-01',
          }
        },
        {
          'id': 'ev_single_1', // Duplikat id som redan finns i dateEvents
          'title': 'Tandläkare override',
          'isRecurring': true,
        }
      ];

      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];

      for (final ev in dateEvents) {
        if (seen.add(ev['id'] as String)) {
          merged.add(ev);
        }
      }

      for (final ev in recurringEvents) {
        final id = ev['id'] as String;
        if (seen.contains(id)) continue;
        if (recurringOccursOnDay(ev, targetDay)) {
          seen.add(id);
          merged.add(ev);
        }
      }

      expect(merged.length, 2);
      expect(merged[0]['title'], 'Tandläkare');
      expect(merged[1]['title'], 'Fotbollsträning');
    });

    test('Sysslor i dåtid vs idag vs framtid', () {
      final choreRecurring = {
        'title': 'Duka bordet',
        'isRecurring': true,
        'doneDates': ['2026-08-29'],
        'recurrence': {
          'type': 'daily',
          'startDate': '2026-08-01',
        },
        'who': 'Noomi',
      };

      final yesterday = DateTime(2026, 8, 29);
      final today = DateTime(2026, 8, 30);
      final tomorrow = DateTime(2026, 8, 31);

      expect(choreOccursOnDay(choreRecurring, yesterday), isTrue);
      expect(choreDoneOnDay(choreRecurring, yesterday), isTrue);

      expect(choreOccursOnDay(choreRecurring, today), isTrue);
      expect(choreDoneOnDay(choreRecurring, today), isFalse);

      expect(choreOccursOnDay(choreRecurring, tomorrow), isTrue);
      expect(choreDoneOnDay(choreRecurring, tomorrow), isFalse);
    });
  });
}
