import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../utils/planning_list_sort.dart';

class PlanningListControls extends StatelessWidget {
  const PlanningListControls({
    super.key,
    required this.sort,
    required this.onSort,
    required this.personUid,
    required this.onPerson,
    required this.members,
  });
  final PlanningListSort sort;
  final ValueChanged<PlanningListSort> onSort;
  final String? personUid;
  final ValueChanged<String?> onPerson;
  final List<UserModel> members;

  @override
  Widget build(BuildContext context) {
    final people = members.toList()
      ..sort((a, b) => comparePlanningNames(a.name, b.name));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 420
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: DropdownButtonFormField<PlanningListSort>(
                key: ValueKey('sort-${sort.name}'),
                initialValue: sort,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sortera',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: PlanningListSort.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onSort(value);
                },
              ),
            ),
            SizedBox(
              width: width,
              child: DropdownButtonFormField<String>(
                key: ValueKey('person-${personUid ?? ''}'),
                initialValue: people.any((m) => m.uid == personUid)
                    ? personUid!
                    : '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Gäller',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Alla personer')),
                  ...people.map(
                    (member) => DropdownMenuItem(
                      value: member.uid,
                      child: Text(member.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    onPerson(value == null || value.isEmpty ? null : value),
              ),
            ),
          ],
        );
      },
    );
  }
}
