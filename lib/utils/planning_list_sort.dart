import '../models/user_model.dart';
import 'date_utils.dart';

enum PlanningListSort {
  date('Datum'),
  week('Vecka'),
  person('Person/barn');

  const PlanningListSort(this.label);
  final String label;
}

class PlanningListItem<T> {
  const PlanningListItem({
    required this.value,
    required this.id,
    required this.title,
    this.date,
    this.aboutUids = const [],
  });
  final T value;
  final String id, title;
  final DateTime? date;
  final List<String> aboutUids;
}

class PlanningListGroup<T> {
  const PlanningListGroup(this.label, this.items);
  final String? label;
  final List<T> items;
}

/// Date-only deadlines are local calendar dates. Reject invalid dates rather
/// than allowing DateTime's overflow normalization to put them in another week.
DateTime? planningDueDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final result = DateTime.tryParse(value);
  return result != null && dateKey(result) == value ? result : null;
}

List<String> planningAboutUids(Map<String, dynamic> data) =>
    (data['aboutUids'] as List?)
        ?.whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList() ??
    [];

String planningPeopleLabel(List<String> uids, List<UserModel> members) {
  if (uids.isEmpty) return 'Hela familjen';
  final names = {for (final member in members) member.uid: member.name};
  final labels = uids.toSet().map((uid) {
    final name = names[uid]?.trim();
    return name == null || name.isEmpty ? 'Tidigare medlem' : name;
  }).toList()..sort(comparePlanningNames);
  return labels.join(', ');
}

int comparePlanningNames(String a, String b) {
  String key(String s) => s
      .toLowerCase()
      .replaceAll('å', '{')
      .replaceAll('ä', '|')
      .replaceAll('ö', '}');
  return key(a).compareTo(key(b));
}

/// Every entry appears once, including entries concerning several children.
/// Person filtering only uses aboutUids, never the adult responsible for a task.
List<PlanningListGroup<T>> groupPlanningList<T>(
  List<PlanningListItem<T>> source, {
  required PlanningListSort sort,
  required List<UserModel> members,
  String? personUid,
  bool newestFirst = false,
}) {
  int byDate(PlanningListItem<T> a, PlanningListItem<T> b) {
    if (a.date == null && b.date != null) return 1;
    if (a.date != null && b.date == null) return -1;
    var result = a.date == null ? 0 : a.date!.compareTo(b.date!);
    if (newestFirst) result = -result;
    if (result == 0) result = comparePlanningNames(a.title, b.title);
    return result == 0 ? a.id.compareTo(b.id) : result;
  }

  final items =
      source
          .where(
            (item) => personUid == null || item.aboutUids.contains(personUid),
          )
          .toList()
        ..sort(byDate);
  if (items.isEmpty) return [];
  if (sort == PlanningListSort.date) {
    return [PlanningListGroup(null, items.map((item) => item.value).toList())];
  }
  final grouped = <String, List<PlanningListItem<T>>>{};
  final labels = <String, String>{};
  for (final item in items) {
    late String key, label;
    if (sort == PlanningListSort.week) {
      final date = item.date;
      key = date == null
          ? ''
          : '${isoWeekYear(date)}-${isoWeekNumber(date).toString().padLeft(2, '0')}';
      label = date == null
          ? 'Utan datum'
          : 'Vecka ${isoWeekNumber(date)} · ${isoWeekYear(date)}';
    } else {
      final uids = item.aboutUids.toSet().toList()..sort();
      key = uids.join('\u0000');
      label = planningPeopleLabel(uids, members);
    }
    (grouped[key] ??= []).add(item);
    labels[key] = label;
  }
  final keys = grouped.keys.toList()
    ..sort((a, b) {
      // Ungrouped/undated items are always last, also in newest-first lists.
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      if (sort == PlanningListSort.week) {
        return newestFirst ? b.compareTo(a) : a.compareTo(b);
      }
      final result = comparePlanningNames(labels[a]!, labels[b]!);
      return result == 0 ? a.compareTo(b) : result;
    });
  return keys
      .map(
        (key) => PlanningListGroup(
          labels[key],
          grouped[key]!.map((item) => item.value).toList(),
        ),
      )
      .toList();
}
