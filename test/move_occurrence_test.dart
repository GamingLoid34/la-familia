import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/move_occurrence.dart';
import 'package:la_familia/utils/recurrence.dart';

void main() {
  final original = DateTime(2026, 10, 26);
  final source = <String, dynamic>{'title': 'Träning', 'familyId': 'familj', 'source': 'manual',
    'date': '2026-10-19', 'time': '07:30', 'isRecurring': true,
    'recurrence': {'type': 'weekly', 'startDate': '2026-10-19', 'exceptions': <String>[]}};
  test('moving across month preserves the series and transfers checklist status', () {
    final moved = detachedOccurrence({...source, 'lessonPrep': {'text': 'Skor', 'doneDates': ['2026-10-26']}},
      'series', original, '2026-11-03', '08:00', '09:00', 'adult');
    final updated = {...source, 'recurrence': <String, dynamic>{...source['recurrence'] as Map<String, dynamic>, 'exceptions': ['2026-10-26']}};
    expect(recurringOccursOnDay(updated, original), isFalse);
    expect(recurringOccursOnDay(updated, DateTime(2026, 11, 2)), isTrue);
    expect(moved['date'], '2026-11-03');
    expect(moved['isRecurring'], isFalse);
    expect(moved.containsKey('recurrence'), isFalse);
    expect((moved['lessonPrep'] as Map)['doneDates'], ['2026-11-03']);
  });
  test('invalid date, overnight end and imported series are rejected', () {
    expect(validateMove('2026-02-30', '07:00', ''), isNotNull);
    expect(validateMove('2026-10-26', '22:00', '01:00'), isNotNull);
    expect(validateMove('2026-10-26', '', ''), isNull);
    expect(() => detachedOccurrence({...source, 'source': 'calendar'}, 's', original,
      '2026-11-03', '08:00', '', 'adult'), throwsStateError);
  });
}
