import 'dart:developer' as developer;
import '../models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/planning_task.dart';
import '../providers/family_provider.dart';
import '../utils/date_utils.dart';
import 'task_editor_sheet.dart';
import '../utils/planning_list_sort.dart';
import '../utils/planning_task_sort.dart';
import 'planning_list_controls.dart';

/// Barn startar aldrig en tasks-prenumeration; reglerna behåller vuxenåtkomsten.
class PlanningTasks extends StatelessWidget {
  final bool all;
  const PlanningTasks({super.key, this.all = false});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    final familyId = user?.familyId;
    if (user?.isParent != true || familyId == null || familyId.isEmpty) {
      return const SizedBox.shrink();
    }
    return _TaskList(
      key: ValueKey('$familyId/${user!.uid}/$all'),
      familyId: familyId,
      all: all,
    );
  }
}

class PlanningTasksPage extends StatelessWidget {
  const PlanningTasksPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Uppgifter')),
    body: const SingleChildScrollView(child: PlanningTasks(all: true)),
  );
}

class _TaskList extends StatefulWidget {
  final String familyId;
  final bool all;
  const _TaskList({super.key, required this.familyId, required this.all});
  @override
  State<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<_TaskList> {
  late final _query = FirebaseFirestore.instance
      .collection('tasks')
      .where('familyId', isEqualTo: widget.familyId)
      .snapshots();
  final _saving = <String>{};
  void _openEditor([PlanningTask? task]) {
    final user = context.read<FamilyProvider>().currentUser;
    if (user == null || !user.isParent || user.familyId != widget.familyId) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          TaskEditorSheet(task: task, familyId: widget.familyId, uid: user.uid),
    );
  }

  Future<void> _toggle(PlanningTask task) async {
    setState(() => _saving.add(task.id));
    try {
      // Partiell skrivning bevarar källanteckning, personer och aktivitetskoppling.
      await FirebaseFirestore.instance
          .collection('tasks')
          .doc(task.id)
          .update(
            PlanningTask.statusPatch(!task.done, FieldValue.serverTimestamp()),
          );
    } catch (error, stack) {
      final code = error is FirebaseException ? error.code : 'webbklient';
      developer.log(
        'Task status write failed: $code (${error.runtimeType})',
        name: 'PlanningTasks',
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(taskSaveErrorMessage(code))));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(task.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = context.watch<FamilyProvider>().familyMembers;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _query,
          builder: (context, snapshot) {
            final now = DateTime.now();
            final today = dateKey(now);
            final tomorrow = dateKey(
              DateTime(now.year, now.month, now.day + 1),
            );
            final tasks =
                (snapshot.data?.docs ?? [])
                    .map((d) => PlanningTask(d.id, d.data()))
                    .where((t) => widget.all || t.visibleOn(today, tomorrow))
                    .toList()
                  ..sort((a, b) {
                    if (a.done != b.done) return a.done ? 1 : -1;
                    return (a.dueDate ?? '9999').compareTo(b.dueDate ?? '9999');
                  });
            return PlanningTasksContent(
              tasks: tasks,
              members: members,
              saving: _saving,
              all: widget.all,
              loading: !snapshot.hasData,
              error: snapshot.hasError
                  ? 'Kunde inte läsa uppgifterna. Kontrollera nät och behörighet.'
                  : null,
              onToggle: _toggle,
              onEdit: _openEditor,
              onAdd: widget.all ? () => _openEditor() : null,
              onShowAll: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const PlanningTasksPage(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Samma presentation används med Firestore och i layout-/interaktionstester.
class PlanningTasksContent extends StatefulWidget {
  final List<PlanningTask> tasks;
  final List<UserModel> members;
  final Set<String> saving;
  final bool all;
  final bool loading;
  final String? error;
  final ValueChanged<PlanningTask> onToggle;
  final VoidCallback onShowAll;
  final ValueChanged<PlanningTask>? onEdit;
  final VoidCallback? onAdd;
  const PlanningTasksContent({
    super.key,
    required this.tasks,
    this.members = const [],
    this.saving = const {},
    this.all = false,
    this.loading = false,
    this.error,
    required this.onToggle,
    required this.onShowAll,
    this.onEdit,
    this.onAdd,
  });
  @override
  State<PlanningTasksContent> createState() => _PlanningTasksContentState();
}

class _PlanningTasksContentState extends State<PlanningTasksContent> {
  PlanningListSort _sort = PlanningListSort.date;
  String? _personUid;

  @override
  Widget build(BuildContext context) {
    final personUid = widget.members.any((m) => m.uid == _personUid)
        ? _personUid
        : null;
    final shown = widget.all ? widget.tasks : widget.tasks.take(3).toList();
    final sections = <Widget>[];
    if (widget.all) {
      for (final done in [false, true]) {
        final groups = groupPlanningList(
          shown.where((t) => t.done == done).map(planningTaskSortItem).toList(),
          sort: _sort,
          members: widget.members,
          personUid: personUid,
        );
        if (groups.isEmpty) continue;
        sections.add(
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(
              done ? 'KLARA' : 'ÖPPNA',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
        for (final group in groups) {
          if (done && _sort == PlanningListSort.date) {
            group.items.sort(compareCompletedPlanningTasks);
          }
          if (group.label != null) {
            sections.add(
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  group.label!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            );
          }
          sections.addAll(group.items.map(_taskTile));
        }
      }
    } else {
      sections.addAll(shown.map(_taskTile));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.all ? 'Alla uppgifter' : 'Att komma ihåg',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (widget.onAdd != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Ny uppgift'),
            ),
          ),
        if (widget.all) ...[
          const SizedBox(height: 12),
          PlanningListControls(
            sort: _sort,
            onSort: (value) => setState(() => _sort = value),
            personUid: personUid,
            onPerson: (value) => setState(() => _personUid = value),
            members: widget.members,
          ),
          if (_sort == PlanningListSort.week)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Vecka utifrån uppgiftens sista datum.'),
            ),
        ],
        if (widget.error != null)
          Text(widget.error!)
        else if (widget.loading)
          const LinearProgressIndicator()
        else if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              personUid == null
                  ? 'Inga uppgifter att visa.'
                  : 'Inga uppgifter för den valda personen.',
            ),
          )
        else
          ...sections,
        if (!widget.all)
          TextButton(
            onPressed: widget.onShowAll,
            child: Text(
              widget.tasks.length > shown.length
                  ? 'Visa alla uppgifter (${widget.tasks.length} aktuella)'
                  : 'Alla uppgifter',
            ),
          ),
      ],
    );
  }

  Widget _taskTile(PlanningTask task) {
    final about = planningAboutUids(task.data);
    final names = about.isEmpty
        ? ''
        : planningPeopleLabel(about, widget.members);
    final detail = [
      if (task.dueDate != null)
        'Senast ${task.dueDate}${task.data['hasTime'] == true ? ' ${task.data['dueTime']}' : ''}',
      if (names.isNotEmpty) names,
      if (task.data['sourceNoteId'] != null) 'Från inkorgen',
      if (widget.saving.contains(task.id)) 'Väntar på bekräftelse',
    ].join(' · ');
    return CheckboxListTile(
      key: ValueKey('task-${task.id}'),
      contentPadding: EdgeInsets.zero,
      secondary: widget.onEdit == null
          ? null
          : IconButton(
              tooltip: 'Redigera uppgift',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => widget.onEdit!(task),
            ),
      title: Text(
        task.title,
        maxLines: widget.all ? null : 2,
        overflow: widget.all ? null : TextOverflow.ellipsis,
      ),
      subtitle: detail.isEmpty
          ? null
          : Text(
              detail,
              maxLines: widget.all ? null : 2,
              overflow: widget.all ? null : TextOverflow.ellipsis,
            ),
      value: task.done,
      onChanged: widget.saving.contains(task.id)
          ? null
          : (_) => widget.onToggle(task),
    );
  }
}

String taskSaveErrorMessage(String code) => switch (code) {
  'permission-denied' =>
    'Uppgiften kunde inte sparas: åtkomst nekad (permission-denied).',
  'unauthenticated' =>
    'Logga in igen för att spara uppgiften (unauthenticated).',
  'not-found' => 'Uppgiften finns inte längre. Ladda om sidan (not-found).',
  'unavailable' =>
    'Ingen kontakt med servern. Kontrollera anslutningen (unavailable).',
  _ => 'Kunde inte spara uppgiften. Felkod: $code.',
};
