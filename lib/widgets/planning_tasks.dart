import 'dart:developer' as developer;
import '../models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/planning_task.dart';
import '../providers/family_provider.dart';
import '../utils/date_utils.dart';

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
class PlanningTasksContent extends StatelessWidget {
  final List<PlanningTask> tasks;
  final List<UserModel> members;
  final Set<String> saving;
  final bool all;
  final bool loading;
  final String? error;
  final ValueChanged<PlanningTask> onToggle;
  final VoidCallback onShowAll;
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
  });
  @override
  Widget build(BuildContext context) {
    final shown = all ? tasks : tasks.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          all ? 'Alla uppgifter' : 'Att komma ihåg',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (error != null)
          Text(error!)
        else if (loading)
          const LinearProgressIndicator()
        else if (tasks.isEmpty)
          const Text('Inga uppgifter att visa.')
        else
          ...shown.map((task) {
            final about = (task.data['aboutUids'] as List?) ?? [];
            final names = members
                .where((m) => about.contains(m.uid))
                .map((m) => m.name)
                .join(', ');
            final detail = [
              if (task.dueDate != null)
                'Senast ${task.dueDate}${task.data['hasTime'] == true ? ' ${task.data['dueTime']}' : ''}',
              if (names.isNotEmpty) names,
              if (task.data['sourceNoteId'] != null) 'Från inkorgen',
              if (saving.contains(task.id)) 'Väntar på bekräftelse',
            ].join(' · ');
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                task.title,
                maxLines: all ? null : 2,
                overflow: all ? null : TextOverflow.ellipsis,
              ),
              subtitle: detail.isEmpty
                  ? null
                  : Text(
                      detail,
                      maxLines: all ? null : 2,
                      overflow: all ? null : TextOverflow.ellipsis,
                    ),
              value: task.done,
              onChanged: saving.contains(task.id)
                  ? null
                  : (_) => onToggle(task),
            );
          }),
        if (!all)
          TextButton(
            onPressed: onShowAll,
            child: Text(
              tasks.length > shown.length
                  ? 'Visa alla uppgifter (${tasks.length} aktuella)'
                  : 'Alla uppgifter',
            ),
          ),
      ],
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
