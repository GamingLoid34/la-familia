import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/recurrence_edit.dart';

void main() {
  test('title-only edit preserves daily, unknown rules and concurrent exceptions', () {
    for (final type in ['daily', 'yearly', 'weekly']) {
      final update = recurrenceEditFields(editing: true, changed: false,
        type: type, start: '2026-10-21', exceptions: [], deleteValue: Object());
      expect(update, isEmpty);
    }
  });
  test('explicitly disabling recurrence removes both fields', () {
    final deletion = Object();
    expect(recurrenceEditFields(editing: true, changed: true, type: 'none',
      start: '2026-10-21', exceptions: [], deleteValue: deletion),
      {'recurrence': deletion, 'isRecurring': deletion});
  });
  test('new rule retains the selected calendar date', () {
    final fields = recurrenceEditFields(editing: false, changed: false, type: 'weekly',
      start: '2026-10-26', exceptions: [], deleteValue: Object());
    expect((fields['recurrence'] as Map)['startDate'], '2026-10-26');
  });
}
