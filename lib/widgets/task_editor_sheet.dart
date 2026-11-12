import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/planning_task.dart';
import '../models/task_draft.dart';
import '../providers/family_provider.dart';
import '../utils/date_utils.dart';

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({
    super.key,
    this.task,
    required this.familyId,
    required this.uid,
  });
  final PlanningTask? task;
  final String familyId;
  final String uid;
  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final _title = TextEditingController();
  final _time = TextEditingController();
  late final DocumentReference<Map<String, dynamic>> _ref;
  DateTime? _due, _showFrom;
  String? _assignee;
  final _about = <String>{};
  bool _saving = false;
  bool _uncertain = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = widget.task?.data ?? {};
    _title.text = data['title'] as String? ?? '';
    _time.text = data['hasTime'] == true
        ? (data['dueTime'] as String? ?? '')
        : '';
    _due = parseDate(data['dueDate']);
    _showFrom = parseDate(data['showFromDate']);
    _assignee = data['assigneeUid'] as String?;
    _about.addAll((data['aboutUids'] as List? ?? []).whereType<String>());
    _ref = FirebaseFirestore.instance.collection('tasks').doc(widget.task?.id);
  }

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool deadline) async {
    final value = await showDatePicker(
      context: context,
      initialDate: (deadline ? _due : _showFrom) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() {
        if (deadline) {
          _due = value;
        } else {
          _showFrom = value;
        }
      });
    }
  }

  bool _sameSession() {
    final user = context.read<FamilyProvider>().currentUser;
    return user?.uid == widget.uid &&
        user?.familyId == widget.familyId &&
        user?.isParent == true &&
        FirebaseAuth.instance.currentUser?.uid == widget.uid;
  }

  Future<void> _save() async {
    if (_saving || _uncertain || !_sameSession()) return;
    final time = _time.text.trim();
    final draft = TaskDraft(
      title: _title.text,
      dueDate: _due,
      dueTime: time.isEmpty ? null : time,
      showFromDate: _showFrom,
      assigneeUid: _assignee,
      aboutUids: _about.toList(),
    );
    final error = draft.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final write = widget.task == null
          ? _ref.set(draft.newFields(widget.familyId, widget.uid))
          : _ref.update(draft.editableFields());
      await write.timeout(const Duration(seconds: 10));
      if (mounted && _sameSession()) Navigator.pop(context);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error =
              'Sparningen kunde inte bekräftas. Stäng formuläret och kontrollera uppgiftslistan.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Sparningen kunde inte bekräftas. Kontrollera uppgiftslistan innan du försöker igen.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_saving || _uncertain || !_sameSession()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ta bort uppgiften?'),
        content: const Text('Uppgiften tas bort för hela familjen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_sameSession()) return;
    setState(() => _saving = true);
    try {
      await _ref.delete().timeout(const Duration(seconds: 10));
      if (mounted && _sameSession()) Navigator.pop(context);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error =
              'Borttagningen kunde inte bekräftas. Stäng formuläret och kontrollera uppgiftslistan.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Borttagningen kunde inte bekräftas. Kontrollera uppgiftslistan.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    if (user?.uid != widget.uid ||
        user?.familyId != widget.familyId ||
        FirebaseAuth.instance.currentUser?.uid != widget.uid) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Kontot har bytts. Öppna uppgiften igen.'),
        ),
      );
    }
    final members = provider.familyMembers;
    final adults = members.where((m) => m.isParent).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.task == null ? 'Ny uppgift' : 'Redigera uppgift',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Vad ska göras?'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _pickDate(true),
                    child: Text(
                      _due == null
                          ? 'Välj deadline'
                          : 'Senast ${dateKey(_due!)}',
                    ),
                  ),
                  if (_due != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _due = null;
                        _time.clear();
                      }),
                      child: const Text('Ta bort datum'),
                    ),
                ],
              ),
              if (_due != null)
                TextField(
                  controller: _time,
                  decoration: const InputDecoration(
                    labelText: 'Klockslag (valfritt)',
                    hintText: 'HH:MM',
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _pickDate(false),
                    child: Text(
                      _showFrom == null
                          ? 'Visa direkt'
                          : 'Visa från ${dateKey(_showFrom!)}',
                    ),
                  ),
                  if (_showFrom != null)
                    TextButton(
                      onPressed: () => setState(() => _showFrom = null),
                      child: const Text('Visa direkt'),
                    ),
                ],
              ),
              if (adults.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Ansvarig'),
                Wrap(
                  spacing: 8,
                  children: adults
                      .map(
                        (m) => FilterChip(
                          label: Text(m.name),
                          selected: _assignee == m.uid,
                          onSelected: (selected) => setState(
                            () => _assignee = selected ? m.uid : null,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              const Text('Gäller personer (valfritt)'),
              Wrap(
                spacing: 8,
                children: members
                    .map(
                      (m) => FilterChip(
                        label: Text(m.name),
                        selected: _about.contains(m.uid),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _about.add(m.uid);
                          } else {
                            _about.remove(m.uid);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.task != null)
                    TextButton(
                      onPressed: _saving || _uncertain ? null : _delete,
                      child: const Text('Ta bort'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving || _uncertain ? null : _save,
                    child: Text(_saving ? 'Sparar…' : 'Spara'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
