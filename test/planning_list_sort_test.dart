import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/models/planning_task.dart';
import 'package:la_familia/utils/inbox_list_sort.dart';
import 'package:la_familia/utils/planning_list_sort.dart';
import 'package:la_familia/utils/planning_task_sort.dart';

UserModel member(String uid, String name) => UserModel(
  uid: uid,
  name: name,
  email: '',
  color: 'ff2196f3',
  role: 'child',
  viewMode: 'child',
  energy: 3,
);

PlanningListItem<String> item(
  String id,
  String? date, [
  List<String> people = const [],
]) => PlanningListItem(
  value: id,
  id: id,
  title: id,
  date: planningDueDate(date),
  aboutUids: people,
);

void main() {
  final members = [member('a', 'Åsa'), member('b', 'Zara')];
  test(
    'task deadline includes time and completed-date sorting keeps missing acknowledgements last',
    () {
      final morning = PlanningTask('early', {
        'dueDate': '2026-10-30',
        'dueTime': '08:00',
        'hasTime': true,
      });
      final evening = PlanningTask('late', {
        'dueDate': '2026-10-30',
        'dueTime': '19:00',
        'hasTime': true,
      });
      final groups = groupPlanningList(
        [evening, morning].map(planningTaskSortItem).toList(),
        sort: PlanningListSort.date,
        members: members,
      );
      expect(groups.single.items.map((t) => t.id), ['early', 'late']);
      final completed = PlanningTask('completed', {
        'status': 'done',
        'doneAt': Timestamp.fromDate(DateTime(2026, 10, 30)),
        'dueDate': '2026-10-30',
      });
      final missing = PlanningTask('missing', {
        'status': 'done',
        'dueDate': '2030-01-01',
      });
      final done = [missing, completed]..sort(compareCompletedPlanningTasks);
      expect(done.first.id, 'completed');
    },
  );
  test('ISO-week groups preserve week-year at both calendar boundaries', () {
    final groups = groupPlanningList(
      [
        item('january', '2027-01-01'),
        item('new-week', '2027-01-04'),
        item('december', '2026-12-31'),
        item('unknown', null),
      ],
      sort: PlanningListSort.week,
      members: members,
    );
    expect(groups.map((g) => g.label), [
      'Vecka 53 · 2026',
      'Vecka 1 · 2027',
      'Utan datum',
    ]);
    expect(groups.first.items, ['december', 'january']);
    expect(groups.expand((g) => g.items).length, 4);
  });
  test('newest-first keeps missing dates last and separates years', () {
    final groups = groupPlanningList(
      [
        item('older', '2025-01-01'),
        item('newer', '2026-01-01'),
        item('missing', null),
      ],
      sort: PlanningListSort.week,
      members: members,
      newestFirst: true,
    );
    expect(groups.map((g) => g.label), [
      'Vecka 1 · 2026',
      'Vecka 1 · 2025',
      'Utan datum',
    ]);
  });
  test(
    'several children form one group and filtering does not duplicate a note',
    () {
      final source = [
        item('shared', '2026-10-30', ['a', 'b', 'a']),
        item('one', null, ['a']),
        item('family', null),
        item('former', null, ['removed']),
      ];
      final groups = groupPlanningList(
        source,
        sort: PlanningListSort.person,
        members: members,
      );
      expect(groups.map((g) => g.label), [
        'Tidigare medlem',
        'Zara, Åsa',
        'Åsa',
        'Hela familjen',
      ]);
      expect(groups.expand((g) => g.items).toSet().length, 4);
      final filtered = groupPlanningList(
        source,
        sort: PlanningListSort.person,
        members: members,
        personUid: 'b',
      );
      expect(filtered.expand((g) => g.items), ['shared']);
      expect(
        groupPlanningList(
          source,
          sort: PlanningListSort.date,
          members: members,
          personUid: 'adult',
        ),
        isEmpty,
      );
    },
  );
  test(
    'invalid deadline stays undated rather than silently moving to another month',
    () {
      expect(planningDueDate('2026-02-30'), isNull);
      expect(planningDueDate('bad'), isNull);
      expect(planningDueDate('2028-02-29'), DateTime(2028, 2, 29));
    },
  );
  test('RSS uses publication date and manual notes use added date', () {
    final added = DateTime(2026, 11, 2);
    final published = DateTime(2026, 10, 30);
    expect(
      inboxListDate({
        'publishedAt': Timestamp.fromDate(published),
        'createdAt': Timestamp.fromDate(added),
      }),
      published,
    );
    expect(
      inboxListDate({
        'publishedAt': 'bad',
        'createdAt': Timestamp.fromDate(added),
      }),
      added,
    );
    expect(inboxListDate({}), isNull);
  });
  test('pending, failed and review statuses stay meaningful under sorting', () {
    final now = DateTime(2026, 10, 30, 10);
    expect(
      inboxListSection({'status': 'needs_review'}, now),
      InboxListSection.review,
    );
    expect(inboxListSection({'status': 'saved'}, now), InboxListSection.unread);
    expect(
      inboxListSection({'status': 'saved', 'requestId': 'pending'}, now),
      InboxListSection.other,
    );
    expect(
      inboxListSection({
        'status': 'interpreting',
        'interpretingSince': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 6)),
        ),
      }, now),
      InboxListSection.failed,
    );
  });
}
