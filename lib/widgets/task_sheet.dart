import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import '../services/task_service.dart';
import 'vardag_header.dart';

/// Öppna formuläret för en ny eller befintlig uppgift.
Future<void> showTaskSheet(
  BuildContext context, {
  required String familyId,
  required List<UserModel> members,
  required bool isParent,
  TaskModel? task,
}) =>
    showProtectedSheet<void>(
      context,
      builder: (_) => TaskSheet(
        familyId: familyId,
        members: members,
        isParent: isParent,
        task: task,
      ),
    );

/// "Ny uppgift" / "Redigera uppgift" (Androids `TaskSheet`).
class TaskSheet extends StatefulWidget {
  final String familyId;
  final List<UserModel> members;
  final bool isParent;
  final TaskModel? task;

  const TaskSheet({
    super.key,
    required this.familyId,
    required this.members,
    required this.isParent,
    this.task,
  });

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late TaskDraft _draft;
  late final TextEditingController _title;
  late final TextEditingController _time;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _draft = widget.task != null ? TaskDraft.from(widget.task!) : const TaskDraft();
    _title = TextEditingController(text: _draft.title);
    _time = TextEditingController(text: _draft.dueTime ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    super.dispose();
  }

  static String _fmt(DateTime d) => DateFormat('EEEE d MMMM', 'sv').format(d);

  Future<DateTime?> _pickDate(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      confirmText: 'OK',
      cancelText: 'Avbryt',
    );
  }

  TaskDraft _current() {
    final t = _time.text.trim();
    return TaskDraft(
      title: _title.text,
      dueDate: _draft.dueDate,
      dueTime: _draft.dueDate == null || t.isEmpty ? null : t,
      showFromDate: _draft.showFromDate,
      assigneeUid: _draft.assigneeUid,
      aboutUids: _draft.aboutUids,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final draft = _current();
    final problem = draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (widget.familyId.isEmpty || uid == null) {
      setState(() => _error = 'Ingen familj vald.');
      return;
    }
    if (!widget.isParent) {
      setState(() => _error = 'Bara familjens vuxna kan skapa uppgifter.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final task = draft.toTask(
          familyId: widget.familyId, myUid: uid, existing: widget.task);
      if (_editing) {
        await TaskService.update(task);
      } else {
        await TaskService.add(task);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Kunde inte spara: $e';
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_saving || widget.task == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await TaskService.delete(widget.task!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Kunde inte ta bort: $e';
        });
      }
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text,
            style: AppTheme.sectionLabelStyle
                .copyWith(color: AppTheme.colors().onCardPrimary)),
      );

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.colors().accent;
    final adults = widget.members.where((m) => m.isParent).toList();
    return SheetFrame(
      title: _editing ? 'Redigera uppgift' : 'Ny uppgift',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              autofocus: !_editing,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Vad ska göras?',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            _label('SENAST'),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded),
                  label: Text(_draft.dueDate == null
                      ? 'Välj datum'
                      : _fmt(_draft.dueDate!)),
                  onPressed: () async {
                    final d = await _pickDate(_draft.dueDate);
                    if (d != null) setState(() => _draft = _draft.copyWith(dueDate: d));
                  },
                ),
              ),
              if (_draft.dueDate != null)
                TextButton(
                  onPressed: () => setState(() {
                    _draft = _draft.copyWith(clearDueDate: true, clearDueTime: true);
                    _time.clear();
                  }),
                  child: const Text('Ta bort'),
                ),
            ]),
            if (_draft.dueDate != null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _time,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: 'Klockslag (valfritt)',
                  hintText: 'HH:MM',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            _label('VISA FRÅN'),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_rounded),
                  label: Text(_draft.showFromDate == null
                      ? 'Visa direkt'
                      : _fmt(_draft.showFromDate!)),
                  onPressed: () async {
                    final d = await _pickDate(_draft.showFromDate);
                    if (d != null) {
                      setState(() => _draft = _draft.copyWith(showFromDate: d));
                    }
                  },
                ),
              ),
              if (_draft.showFromDate != null)
                TextButton(
                  onPressed: () => setState(() =>
                      _draft = _draft.copyWith(clearShowFromDate: true)),
                  child: const Text('Ta bort'),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Uppgiften ligger tyst tills den dagen, men en deadline som närmar sig visas ändå.',
                style: TextStyle(fontSize: 12, color: AppTheme.getSubTextColor()),
              ),
            ),
            if (adults.isNotEmpty) ...[
              _label('ANSVARIG'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in adults)
                    FilterChip(
                      label: Text(m.name.split(' ').first),
                      selected: _draft.assigneeUid == m.uid,
                      selectedColor: accent.withValues(alpha: 0.18),
                      checkmarkColor: accent,
                      onSelected: (_) => setState(() {
                        _draft = _draft.assigneeUid == m.uid
                            ? _draft.copyWith(clearAssignee: true)
                            : _draft.copyWith(assigneeUid: m.uid);
                      }),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _draft.assigneeUid == null
                      ? 'Ingen vald: vem som helst av de vuxna.'
                      : 'Tryck igen för att låta vem som helst ta den.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.getSubTextColor()),
                ),
              ),
            ],
            if (widget.members.isNotEmpty) ...[
              _label('GÄLLER'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in widget.members)
                    FilterChip(
                      label: Text(m.name.split(' ').first),
                      selected: _draft.aboutUids.contains(m.uid),
                      selectedColor: accent.withValues(alpha: 0.18),
                      checkmarkColor: accent,
                      onSelected: (sel) => setState(() {
                        final next = [..._draft.aboutUids];
                        sel ? next.add(m.uid) : next.remove(m.uid);
                        _draft = TaskDraft(
                          title: _title.text,
                          dueDate: _draft.dueDate,
                          dueTime: _draft.dueTime,
                          showFromDate: _draft.showFromDate,
                          assigneeUid: _draft.assigneeUid,
                          aboutUids: next,
                        );
                      }),
                    ),
                ],
              ),
            ],
            if (widget.task?.sourceNoteId != null ||
                widget.task?.eventId != null) ...[
              const SizedBox(height: 14),
              Text(
                [
                  if (widget.task?.sourceNoteId != null)
                    'Skapad från en anteckning i Inkorgen.',
                  if (widget.task?.eventId != null)
                    'Förberedelse inför en aktivitet ${widget.task!.occurrenceDate ?? ''}.'
                        .trim(),
                ].join(' '),
                style: TextStyle(fontSize: 12, color: AppTheme.getSubTextColor()),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              if (_editing)
                TextButton(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB3261E)),
                  child: const Text('Ta bort'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size(120, 48),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Spara'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
