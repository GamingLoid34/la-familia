import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/planning_task.dart';
import 'planning_list_sort.dart';

DateTime? planningTaskDeadline(PlanningTask task) {
  final day = planningDueDate(task.dueDate);
  if (day == null || task.data['hasTime'] != true) return day;
  final parts = RegExp(
    r'^(\d{2}):(\d{2})$',
  ).firstMatch(task.data['dueTime']?.toString() ?? '');
  if (parts == null) return day;
  final hour = int.parse(parts[1]!);
  final minute = int.parse(parts[2]!);
  return hour < 24 && minute < 60
      ? DateTime(day.year, day.month, day.day, hour, minute)
      : day;
}

PlanningListItem<PlanningTask> planningTaskSortItem(PlanningTask task) {
  return PlanningListItem(
    value: task,
    id: task.id,
    title: task.title,
    date: planningTaskDeadline(task),
    aboutUids: planningAboutUids(task.data),
  );
}

int compareCompletedPlanningTasks(PlanningTask a, PlanningTask b) {
  DateTime? completed(PlanningTask task) {
    final value = task.data['doneAt'];
    return value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : null;
  }

  int dates(DateTime? first, DateTime? second, {bool newestFirst = false}) {
    if (first == null && second != null) return 1;
    if (first != null && second == null) return -1;
    if (first == null) return 0;
    return newestFirst ? second!.compareTo(first) : first.compareTo(second!);
  }

  var result = dates(completed(a), completed(b), newestFirst: true);
  if (result == 0) {
    result = dates(planningTaskDeadline(a), planningTaskDeadline(b));
  }
  if (result == 0) result = comparePlanningNames(a.title, b.title);
  return result == 0 ? a.id.compareTo(b.id) : result;
}
