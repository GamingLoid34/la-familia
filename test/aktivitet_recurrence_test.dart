import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/chore_utils.dart';
import 'package:la_familia/utils/recurrence.dart';

/// Återkomstreglerna aktivitetsformuläret och förberedelsen bygger på.
///
/// Portad från Androids `RecurrenceTest` (som i sin tur är portad från
/// `lib/utils/recurrence.dart`). Bekräftar bland annat att `"daily"` stöds av
/// läsarna, så att en daglig serie inte får tappa sin typ vid redigering.
void main() {
  Map<String, dynamic> serie(String typ,
          {String? endDate, List<String>? exceptions}) =>
      {
        'date': '2026-09-07',
        'recurrence': <String, dynamic>{
          'type': typ,
          'startDate': '2026-09-07',
          'endDate': ?endDate,
          'exceptions': ?exceptions,
        },
      };

  test('veckovis', () {
    final e = serie('weekly');
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 7)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 14)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 8)), isFalse);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 6)), isFalse);
  });

  test('varannan vecka', () {
    final e = serie('biweekly');
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 7)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 14)), isFalse);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 21)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 10, 5)), isTrue);
  });

  test('månadsvis', () {
    final e = serie('monthly');
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 7)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 10, 7)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 10, 8)), isFalse);
  });

  test('slutdatum passerat', () {
    final e = serie('weekly', endDate: '2026-09-20');
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 14)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 21)), isFalse);
  });

  test('datum i undantagen', () {
    final e = serie('weekly', exceptions: ['2026-09-14']);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 7)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 14)), isFalse);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 21)), isTrue);
  });

  test('dagligen', () {
    final e = serie('daily');
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 7)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 8)), isTrue);
    expect(recurringOccursOnDay(e, DateTime(2026, 9, 9)), isTrue);
  });

  test('turordning per dag', () {
    final chore = <String, dynamic>{
      'isRecurring': true,
      'rotationUids': ['uid_oscar', 'uid_sofia'],
      'recurrence': <String, dynamic>{'type': 'daily', 'startDate': '2026-09-07'},
    };
    expect(assigneeForDay(chore, DateTime(2026, 9, 7)), 'uid_oscar');
    expect(assigneeForDay(chore, DateTime(2026, 9, 8)), 'uid_sofia');
    expect(assigneeForDay(chore, DateTime(2026, 9, 9)), 'uid_oscar');
    expect(nextAssigneeAfter(chore, DateTime(2026, 9, 7)), 'uid_sofia');
  });

  test('utan turordning gäller whoUid', () {
    final chore = <String, dynamic>{
      'isRecurring': false,
      'whoUid': 'uid_oscar',
      'who': 'Oscar',
    };
    expect(assigneeForDay(chore, DateTime(2026, 9, 7)), 'uid_oscar');
  });

  test('expandera en serie', () {
    final dates = expandRecurrence(
        serie('weekly'), DateTime(2026, 9, 7), DateTime(2026, 9, 21));
    expect(dates, [
      DateTime(2026, 9, 7),
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 21),
    ]);
  });

  test('etiketter', () {
    expect(recurrenceLabel(serie('daily')), 'Varje dag');
    expect(recurrenceLabel(serie('weekly')), 'Varje måndag');
    expect(recurrenceLabel(serie('biweekly')), 'Varannan måndag');
  });
}
