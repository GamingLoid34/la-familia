import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/task_service.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../widgets/task_sheet.dart';
import '../widgets/vardag_header.dart';

/// Fria uppgifter under Mer (Androids `TaskListScreen`). Bara för vuxna.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final Set<String> _savingIds = {};

  Future<void> _setDone(TaskModel t, bool done) async {
    if (_savingIds.contains(t.id)) return;
    setState(() => _savingIds.add(t.id));
    try {
      await TaskService.setDone(t.id, done);
    } catch (e) {
      if (mounted) showVardagSnack(context, 'Kunde inte spara: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingIds.remove(t.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FamilyProvider>();
    final me = p.currentUser;
    final isParent = me?.isParent == true;
    final fid = me?.familyId ?? '';
    final colors = AppTheme.colors();

    Widget body;
    if (!isParent) {
      body = _Message('Uppgifter är till för familjens vuxna.', colors.onPage);
    } else if (!p.tasksLoaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.tasksError != null) {
      body = _ErrorMessage(
        text: 'Kunde inte läsa uppgifterna: ${p.tasksError}',
        onRetry: p.retryAdultData,
      );
    } else {
      final open = p.tasks.where((t) => !t.isDone).toList()
        ..sort(TaskModel.compareOpen);
      final done = p.tasks.where((t) => t.isDone).toList()
        ..sort(TaskModel.compareDone);
      if (open.isEmpty && done.isEmpty) {
        body = _Message(
            'Inga uppgifter än. Tryck på plus för att lägga till något som ska bli gjort.',
            colors.onPage);
      } else {
        final today = dateKey(DateTime.now());
        body = ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (open.isNotEmpty) ...[
              const VardagSectionLabel('ÖPPNA'),
              _TaskGroup(
                tasks: open,
                members: p.familyMembers,
                today: today,
                savingIds: _savingIds,
                onToggle: _setDone,
                onOpen: (t) => showTaskSheet(context,
                    familyId: fid, members: p.familyMembers, isParent: true, task: t),
              ),
            ],
            if (done.isNotEmpty) ...[
              const VardagSectionLabel('KLARA'),
              _TaskGroup(
                tasks: done,
                members: p.familyMembers,
                today: today,
                savingIds: _savingIds,
                onToggle: _setDone,
                onOpen: (t) => showTaskSheet(context,
                    familyId: fid, members: p.familyMembers, isParent: true, task: t),
              ),
            ],
          ],
        );
      }
    }

    return Scaffold(
      backgroundColor: colors.pageBackground,
      floatingActionButton: isParent
          ? FloatingActionButton(
              tooltip: 'Ny uppgift',
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              elevation: AppTheme.lowStimuli ? 0 : 6,
              onPressed: () => showTaskSheet(context,
                  familyId: fid, members: p.familyMembers, isParent: true),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: WindowSize.of(context).isExpanded
                  ? WindowSize.settingsMaxWidth
                  : double.infinity),
          child: Column(children: [
            VardagTitleHeader(
                title: 'Uppgifter', onBack: () => Navigator.of(context).maybePop()),
            Expanded(child: body),
          ]),
        ),
      ),
    );
  }
}

class _TaskGroup extends StatelessWidget {
  final List<TaskModel> tasks;
  final List<UserModel> members;
  final String today;
  final Set<String> savingIds;
  final void Function(TaskModel, bool) onToggle;
  final void Function(TaskModel) onOpen;

  const _TaskGroup({
    required this.tasks,
    required this.members,
    required this.today,
    required this.savingIds,
    required this.onToggle,
    required this.onOpen,
  });

  String _subtitle(TaskModel t) {
    final parts = <String>[];
    if (t.dueDate != null) {
      final d = parseDate(t.dueDate);
      var s = 'Senast ${d != null ? DateFormat('EEE d MMM', 'sv').format(d) : t.dueDate}';
      if (t.hasTime && t.dueTime != null) s += ' ${t.dueTime}';
      parts.add(s);
    }
    if (t.assigneeUid != null) {
      final m = members.where((m) => m.uid == t.assigneeUid);
      if (m.isNotEmpty) parts.add(m.first.name.split(' ').first);
    }
    if (t.eventId != null) parts.add('Förberedelse');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    return VardagCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        for (var i = 0; i < tasks.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 56, color: c.divider),
          Builder(builder: (context) {
            final t = tasks[i];
            final sub = _subtitle(t);
            final overdue = t.isOverdue(today);
            return InkWell(
              onTap: () => onOpen(t),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
                child: Row(children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: savingIds.contains(t.id)
                        ? const Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)))
                        : Checkbox(
                            value: t.isDone,
                            activeColor: c.accent,
                            semanticLabel: t.isDone ? 'Öppna igen' : 'Klart',
                            onChanged: (v) => onToggle(t, v == true),
                          ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: t.isDone ? c.onCardSecondary : c.onCardPrimary,
                              decoration:
                                  t.isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (sub.isNotEmpty)
                            Text(
                              sub,
                              style: TextStyle(
                                fontSize: 12,
                                color: overdue
                                    ? const Color(0xFFB3261E)
                                    : c.onCardSecondary,
                                fontWeight:
                                    overdue ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ],
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final Color color;
  const _Message(this.text, this.color);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: color)),
        ),
      );
}

class _ErrorMessage extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  const _ErrorMessage({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: VardagCard(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('⚠️', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.onCardPrimary)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: c.accent),
              child: const Text('Försök igen'),
            ),
          ]),
        ),
      ),
    );
  }
}
