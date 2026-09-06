import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/chore_utils.dart';
import 'package:la_familia/utils/date_utils.dart';

void main() {
  group('chore_utils rotation', () {
    final chore = <String, dynamic>{
      'isRecurring': true,
      'rotationUids': ['a', 'b', 'c'],
      'recurrence': {
        'type': 'daily',
        'startDate': '2026-08-20',
        'endDate': null,
        'exceptions': <String>[],
      },
    };

    test('assignee rotates daily', () {
      expect(assigneeForDay(chore, DateTime(2026, 8, 20)), 'a');
      expect(assigneeForDay(chore, DateTime(2026, 8, 21)), 'b');
      expect(assigneeForDay(chore, DateTime(2026, 8, 22)), 'c');
      expect(assigneeForDay(chore, DateTime(2026, 8, 23)), 'a');
    });

    test('doneDates marks day done without affecting others', () {
      final d = Map<String, dynamic>.from(chore)
        ..['doneDates'] = ['2026-08-21'];
      expect(choreDoneOnDay(d, DateTime(2026, 8, 21)), isTrue);
      expect(choreDoneOnDay(d, DateTime(2026, 8, 22)), isFalse);
      expect(choreOpenOnDay(d, DateTime(2026, 8, 22)), isTrue);
      expect(choreOpenOnDay(d, DateTime(2026, 8, 21)), isFalse);
    });

    test('one-off uses isDone and dueDate', () {
      final one = <String, dynamic>{
        'isDone': false,
        'dueDate': dateKey(DateTime(2026, 8, 21)),
      };
      expect(choreOccursOnDay(one, DateTime(2026, 8, 21)), isTrue);
      expect(choreOccursOnDay(one, DateTime(2026, 8, 22)), isFalse);
      one['isDone'] = true;
      expect(choreDoneOnDay(one, DateTime(2026, 8, 21)), isTrue);
    });
  });

  group('Sysslor Just In Time & Återkommande', () {
    test('nextChoreOccurrence hittar nästa veckodag inom 14 dagar', () {
      // Tisdag-syssla
      final weeklyTuesday = <String, dynamic>{
        'isRecurring': true,
        'recurrence': {
          'type': 'weekly',
          'startDate': '2026-09-01', // tisdag
        },
      };

      // Om idag är söndag 2026-09-06: nästa tisdag är 2026-09-08
      final sunday = DateTime(2026, 9, 6);
      final next = nextChoreOccurrence(weeklyTuesday, sunday, maxDaysAhead: 14);
      expect(next, isNotNull);
      expect(next, DateTime(2026, 9, 8));
      expect(formatNextOccurrence(next!), 'nästa: tisdag 8/9');
    });

    test('nextChoreOccurrence respekterar maxDaysAhead och returnerar null om > 14 dagar', () {
      final monthly = <String, dynamic>{
        'isRecurring': true,
        'recurrence': {
          'type': 'monthly',
          'startDate': '2026-09-28',
        },
      };
      // Idag är 2026-09-01. Den 28:e är 27 dagar bort -> utanför 14 dagar
      final sept1 = DateTime(2026, 9, 1);
      final next = nextChoreOccurrence(monthly, sept1, maxDaysAhead: 14);
      expect(next, isNull);

      // Om vi söker 30 dagar framåt hittar vi den
      final next30 = nextChoreOccurrence(monthly, sept1, maxDaysAhead: 30);
      expect(next30, DateTime(2026, 9, 28));
      expect(formatNextOccurrence(next30!), 'nästa: måndag 28/9');
    });

    test('nextSaturdayAfter hittar närmaste lördag strikt efter angiven dag', () {
      // Från tisdag 2026-09-08 -> lördag 2026-09-12
      expect(nextSaturdayAfter(DateTime(2026, 9, 8)), DateTime(2026, 9, 12));
      // Från lördag 2026-09-12 -> nästa lördag 2026-09-19
      expect(nextSaturdayAfter(DateTime(2026, 9, 12)), DateTime(2026, 9, 19));
      // Från söndag 2026-09-13 -> lördag 2026-09-19
      expect(nextSaturdayAfter(DateTime(2026, 9, 13)), DateTime(2026, 9, 19));
    });

    test('Städdagsformatering för X zoner med nästa lördag', () {
      final staddagDate = DateTime(2026, 9, 12);
      const days = ['', 'måndag', 'tisdag', 'onsdag', 'torsdag', 'fredag', 'lördag', 'söndag'];
      final weekday = days[staddagDate.weekday];
      final dateStr = '$weekday ${staddagDate.day}/${staddagDate.month}';

      const zoneCount = 7;
      final zoneText = zoneCount == 1 ? '1 zon' : '$zoneCount zoner';
      final staddagRow = '🧹 Städdag · $zoneText · nästa: $dateStr';

      expect(staddagRow, '🧹 Städdag · 7 zoner · nästa: lördag 12/9');
    });

    test('Just-in-time uppdelning: recurringLater innehåller återkommande som ej är idag', () {
      final today = DateTime(2026, 9, 6); // söndag

      final chToday = <String, dynamic>{
        'chore': 'Mata katten',
        'isRecurring': true,
        'recurrence': {'type': 'daily', 'startDate': '2026-09-01'},
      };

      final chLater = <String, dynamic>{
        'chore': 'Vattna blommor',
        'isRecurring': true,
        'recurrence': {'type': 'weekly', 'startDate': '2026-09-01'}, // tisdagar
      };

      final chOneOffOpen = <String, dynamic>{
        'chore': 'Köpa lampa',
        'isRecurring': false,
        'dueDate': '2026-09-10',
        'isDone': false,
      };

      final chOneOffDone = <String, dynamic>{
        'chore': 'Boka tvättid',
        'isRecurring': false,
        'isDone': true,
      };

      final chStad = <String, dynamic>{
        'chore': 'Kök',
        'stadKey': 'kok',
        'isRecurring': true,
        'recurrence': {'type': 'weekly', 'startDate': '2026-09-05'}, // lördagar
      };

      final chores = [chToday, chLater, chOneOffOpen, chOneOffDone, chStad];

      final todayList = <Map<String, dynamic>>[];
      final openList = <Map<String, dynamic>>[];
      final recurringLaterList = <Map<String, dynamic>>[];
      final doneList = <Map<String, dynamic>>[];

      for (final d in chores) {
        if (choreIsRecurring(d)) {
          if (!choreOccursOnDay(d, today)) {
            recurringLaterList.add(d);
            continue;
          }
          if (choreDoneOnDay(d, today)) {
            doneList.add(d);
          } else {
            todayList.add(d);
          }
        } else if (d['isDone'] == true) {
          doneList.add(d);
        } else if (choreOccursOnDay(d, today)) {
          todayList.add(d);
        } else {
          openList.add(d);
        }
      }

      // IDAG: endast Mata katten
      expect(todayList.map((c) => c['chore']).toList(), ['Mata katten']);
      // ÖPPNA: endast engångssysslor som inte infaller idag
      expect(openList.map((c) => c['chore']).toList(), ['Köpa lampa']);
      // ÅTERKOMMANDE: Vattna blommor och Kök (städzon)
      expect(recurringLaterList.map((c) => c['chore']).toList(), ['Vattna blommor', 'Kök']);
      // KLARA: Boka tvättid
      expect(doneList.map((c) => c['chore']).toList(), ['Boka tvättid']);

      // Städzoner filtreras ur enskilda rader i Återkommande:
      final nonStad = recurringLaterList.where((c) => c['stadKey'] == null).toList();
      final stad = recurringLaterList.where((c) => c['stadKey'] != null).toList();
      expect(nonStad.map((c) => c['chore']).toList(), ['Vattna blommor']);
      expect(stad.length, 1);
    });
  });
}
