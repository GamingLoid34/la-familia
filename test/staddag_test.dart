import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/data/stadzoner.dart';
import 'package:la_familia/utils/chore_utils.dart';
import 'package:la_familia/utils/date_utils.dart';

void main() {
  group('Städdag — Måldatum och progressberäkning', () {
    const swedishMonths = [
      '',
      'januari',
      'februari',
      'mars',
      'april',
      'maj',
      'juni',
      'juli',
      'augusti',
      'september',
      'oktober',
      'november',
      'december',
    ];

    DateTime resolveTargetDate(DateTime now) {
      return now.weekday == DateTime.saturday
          ? DateTime(now.year, now.month, now.day)
          : getNextSaturday(now);
    }

    String resolveDateSubtitle(DateTime now, DateTime targetDate) {
      return now.weekday == DateTime.saturday
          ? 'Idag!'
          : 'Lördag ${targetDate.day} ${swedishMonths[targetDate.month]}';
    }

    test('Måldatum är idag om det är lördag', () {
      final saturday = DateTime(2026, 9, 12, 10, 30); // 2026-09-12 is a Saturday
      expect(saturday.weekday, equals(DateTime.saturday));

      final target = resolveTargetDate(saturday);
      expect(target.year, equals(2026));
      expect(target.month, equals(9));
      expect(target.day, equals(12));
      expect(resolveDateSubtitle(saturday, target), equals('Idag!'));
    });

    test('Måldatum är kommande lördag om idag är söndag', () {
      final sunday = DateTime(2026, 9, 6, 14, 0); // Sunday
      expect(sunday.weekday, equals(DateTime.sunday));

      final target = resolveTargetDate(sunday);
      expect(target.weekday, equals(DateTime.saturday));
      expect(target.day, equals(12));
      expect(target.month, equals(9));
      expect(resolveDateSubtitle(sunday, target), equals('Lördag 12 september'));
    });

    test('Måldatum är kommande lördag om idag är onsdag', () {
      final wednesday = DateTime(2026, 9, 9, 8, 15); // Wednesday
      expect(wednesday.weekday, equals(DateTime.wednesday));

      final target = resolveTargetDate(wednesday);
      expect(target.weekday, equals(DateTime.saturday));
      expect(target.day, equals(12));
      expect(resolveDateSubtitle(wednesday, target), equals('Lördag 12 september'));
    });

    test('Måldatum är imorgon om idag är fredag', () {
      final friday = DateTime(2026, 9, 11, 20, 0); // Friday
      expect(friday.weekday, equals(DateTime.friday));

      final target = resolveTargetDate(friday);
      expect(target.weekday, equals(DateTime.saturday));
      expect(target.day, equals(12));
      expect(resolveDateSubtitle(friday, target), equals('Lördag 12 september'));
    });

    test('Avbockning i förväg räknas mot måldatumets dateKey', () {
      final wednesday = DateTime(2026, 9, 9);
      final upcomingSaturday = resolveTargetDate(wednesday);
      final saturdayKey = dateKey(upcomingSaturday);

      // Syssla avbockad för kommande lördag (gjord i förväg på onsdag)
      final choreData = {
        'isRecurring': true,
        'recurrence': {
          'type': 'weekly',
          'days': [6], // lördag
        },
        'stadKey': 'stad_badrum',
        'doneDates': [saturdayKey],
      };

      // Progress mot kommande lördag ska vara sann
      expect(choreDoneOnDay(choreData, upcomingSaturday), isTrue);

      // Men inte avbockad för tidigare lördag
      final pastSaturday = DateTime(2026, 9, 5);
      expect(choreDoneOnDay(choreData, pastSaturday), isFalse);
    });

    test('Alla 7 zoner från stadZoner mappas i definierad ordning', () {
      expect(stadZoner.length, equals(7));
      final keys = stadZoner.map((z) => z.key).toList();
      expect(keys, equals([
        'stad_badrum',
        'stad_toalett',
        'stad_kok',
        'stad_damm',
        'stad_golv',
        'stad_textil',
        'stad_sopor',
      ]));

      // Alla kan slås upp via stadZonByKey
      for (final key in keys) {
        expect(stadZonByKey(key), isNotNull);
        expect(stadZonByKey(key)!.key, equals(key));
      }
    });

    test('Partitionering av dagens sysslor delar upp stadKey och övriga', () {
      final chores = [
        {'title': 'Tömma diskmaskin', 'stadKey': null},
        {'title': 'Vattna blommor', 'stadKey': ''},
        {'title': 'Badrum', 'stadKey': 'stad_badrum'},
        {'title': 'Toalett', 'stadKey': 'stad_toalett'},
        {'title': 'Kök', 'stadKey': 'stad_kok'},
        {'title': 'Damm & ytor', 'stadKey': 'stad_damm'},
        {'title': 'Golv', 'stadKey': 'stad_golv'},
        {'title': 'Sängar & tvätt', 'stadKey': 'stad_textil'},
        {'title': 'Sopor & återvinning', 'stadKey': 'stad_sopor'},
      ];

      final stadChores = chores.where((c) {
        final k = c['stadKey'];
        return k != null && k.isNotEmpty;
      }).toList();
      final otherChores = chores.where((c) {
        final k = c['stadKey'];
        return k == null || k.isEmpty;
      }).toList();

      expect(stadChores.length, equals(7));
      expect(otherChores.length, equals(2));
    });

    test('Städdag-kort beräknar progress via choreDoneOnDay för dagen', () {
      final saturday = DateTime(2026, 9, 12);
      final satKey = dateKey(saturday);

      final stadChores = [
        {'title': 'Badrum', 'stadKey': 'stad_badrum', 'isRecurring': true, 'recurrence': {'type': 'weekly'}, 'doneDates': [satKey]},
        {'title': 'Toalett', 'stadKey': 'stad_toalett', 'isRecurring': true, 'recurrence': {'type': 'weekly'}, 'doneDates': [satKey]},
        {'title': 'Kök', 'stadKey': 'stad_kok', 'isRecurring': true, 'recurrence': {'type': 'weekly'}, 'doneDates': [satKey]},
        {'title': 'Damm & ytor', 'stadKey': 'stad_damm', 'isRecurring': true, 'recurrence': {'type': 'weekly'}, 'doneDates': <String>[]},
        {'title': 'Golv', 'stadKey': 'stad_golv', 'isRecurring': true, 'recurrence': {'type': 'weekly'}, 'doneDates': <String>[]},
        {'title': 'Sängar & tvätt', 'stadKey': 'stad_textil', 'isRecurring': true, 'recurrence': {'type': 'weekly'}, 'doneDates': <String>[]},
        {'title': 'Sopor & återvinning', 'stadKey': 'stad_sopor', 'isRecurring': true, 'recurrence': {'type': 'weekly'}, 'doneDates': <String>[]},
      ];

      final doneCount = stadChores.where((d) => choreDoneOnDay(d, saturday)).length;
      expect(doneCount, equals(3));
      final label = 'Städdag · $doneCount av ${stadChores.length} klara';
      expect(label, equals('Städdag · 3 av 7 klara'));
    });

    test('Månadsvyns pill-etikett visar 🧹 istället för 7 när städzoner är öppna', () {
      final saturday = DateTime(2026, 9, 12);
      final satKey = dateKey(saturday);

      String resolveChorePillLabel({
        required List<Map<String, dynamic>> stadChores,
        required List<Map<String, dynamic>> otherChores,
      }) {
        final otherOpen = otherChores.where((c) => !choreDoneOnDay(c, saturday)).length;
        final hasOpenStad = stadDocsOpen(stadChores, saturday);

        if (hasOpenStad && otherOpen > 0) {
          return '🧹 +$otherOpen';
        } else if (hasOpenStad) {
          return '🧹';
        } else if (otherOpen > 0) {
          return otherOpen == 1 ? '✅' : '✅ ×$otherOpen';
        }
        return '';
      }

      final all7OpenStad = List.generate(7, (i) => {
        'stadKey': 'stad_$i',
        'isRecurring': true,
        'recurrence': {'type': 'weekly'},
        'doneDates': <String>[],
      });

      // 1. Endast 7 städzoner öppna -> '🧹' (inte '✅ ×7')
      expect(resolveChorePillLabel(stadChores: all7OpenStad, otherChores: []), equals('🧹'));

      // 2. 7 städzoner öppna + 2 övriga öppna -> '🧹 +2'
      final twoOther = [
        {'stadKey': null, 'isDone': false},
        {'stadKey': null, 'isDone': false},
      ];
      expect(resolveChorePillLabel(stadChores: all7OpenStad, otherChores: twoOther), equals('🧹 +2'));

      // 3. Alla 7 städzoner klara + 1 övrig öppen -> '✅'
      final all7DoneStad = List.generate(7, (i) => {
        'stadKey': 'stad_$i',
        'isRecurring': true,
        'recurrence': {'type': 'weekly'},
        'doneDates': [satKey],
      });
      final oneOther = [{'stadKey': null, 'isDone': false}];
      expect(resolveChorePillLabel(stadChores: all7DoneStad, otherChores: oneOther), equals('✅'));
    });
  });
}

bool stadDocsOpen(List<Map<String, dynamic>> docs, DateTime day) {
  return docs.isNotEmpty && docs.any((c) => !choreDoneOnDay(c, day));
}

