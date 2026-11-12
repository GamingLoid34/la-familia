import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/planning_task.dart';

void main() {
  test('veckobrevets förfallna och kommande uppgifter visas, klara döljs', () {
    bool visible(Map<String, dynamic> data) =>
        PlanningTask('id', data).visibleOn('2026-10-22', '2026-10-23');
    expect(visible({'sourceNoteId': 'brev', 'dueDate': '2026-10-21'}), isTrue);
    expect(visible({'sourceNoteId': 'brev', 'dueDate': '2026-10-23'}), isTrue);
    expect(visible({'dueDate': '2026-10-30'}), isFalse);
    expect(
      visible({'dueDate': '2026-10-30', 'showFromDate': '2026-10-22'}),
      isTrue,
    );
    expect(
      visible({'dueDate': '2026-10-23', 'showFromDate': '2026-10-23'}),
      isFalse,
    );
    expect(visible({'status': 'done'}), isFalse);
    expect(visible({}), isTrue);
  });
  test('avbockning och återöppning ändrar bara status och doneAt', () {
    final original = {
      'sourceNoteId': 'brev',
      'eventId': 'träning',
      'aboutUids': ['barn'],
      'title': 'Ta med matsäck',
    };
    final completed = {
      ...original,
      ...PlanningTask.statusPatch(true, 'server time'),
    };
    expect(completed['sourceNoteId'], 'brev');
    expect(completed['eventId'], 'träning');
    expect(completed['aboutUids'], ['barn']);
    expect(completed['doneAt'], 'server time');
    expect(PlanningTask.statusPatch(false, 'unused'), {
      'status': 'open',
      'doneAt': null,
    });
  });
}
