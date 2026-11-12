import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/task_draft.dart';

void main() {
  test('validates required title, time and date ordering', () {
    expect(const TaskDraft(title: ' ').validate(), isNotNull);
    expect(
      const TaskDraft(title: 'Packa', dueTime: '09:00').validate(),
      contains('datum'),
    );
    expect(
      TaskDraft(
        title: 'Packa',
        dueDate: DateTime(2026, 11, 2),
        dueTime: '25:80',
      ).validate(),
      contains('HH:MM'),
    );
    expect(
      TaskDraft(
        title: 'Packa',
        dueDate: DateTime(2026, 11, 2),
        showFromDate: DateTime(2026, 11, 3),
      ).validate(),
      contains('deadline'),
    );
    expect(
      TaskDraft(
        title: 'Packa',
        dueDate: DateTime(2026, 11, 2),
        dueTime: '09:15',
      ).validate(),
      isNull,
    );
  });

  test(
    'a new task has the shared contract and editing cannot reset source or completion',
    () {
      final draft = TaskDraft(
        title: ' Packa ',
        dueDate: DateTime(2026, 11, 2),
        dueTime: '09:15',
        aboutUids: ['child'],
      );
      final created = draft.newFields('family', 'parent');
      expect(created['title'], 'Packa');
      expect(created['familyId'], 'family');
      expect(created['createdByUid'], 'parent');
      expect(created['status'], 'open');
      expect(created['doneAt'], isNull);
      expect(created['hasTime'], true);
      expect(created['aboutUids'], ['child']);
      expect(draft.editableFields().keys, isNot(contains('sourceNoteId')));
      expect(draft.editableFields().keys, isNot(contains('eventId')));
      expect(draft.editableFields().keys, isNot(contains('status')));
      expect(draft.editableFields().keys, isNot(contains('doneAt')));
    },
  );
}
