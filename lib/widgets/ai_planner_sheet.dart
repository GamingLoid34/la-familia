import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/family_provider.dart';
import '../services/planner_ai_service.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import 'add_event_sheet.dart';

class AiPlannerRange {
  final DateTime start;
  final DateTime end;
  const AiPlannerRange({required this.start, required this.end});
}

/// Rubrikform: "10–25 aug" / "28 aug–3 sep".
String formatAiPeriodLabel(DateTime start, DateTime end) {
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  try {
    if (s.year == e.year && s.month == e.month) {
      final month = DateFormat('MMM', 'sv').format(e);
      return '${s.day}–${e.day} $month';
    }
    return '${DateFormat('d MMM', 'sv').format(s)}–${DateFormat('d MMM', 'sv').format(e)}';
  } catch (_) {
    if (s.year == e.year && s.month == e.month) {
      return '${s.day}–${e.day} ${DateFormat('MMM').format(e)}';
    }
    return '${DateFormat('d MMM').format(s)}–${DateFormat('d MMM').format(e)}';
  }
}

DateTime _mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// Klipp intervallet till max 14 inklusiva dagar (end justeras).
AiPlannerRange clampAiRange(DateTime start, DateTime end) {
  var s = DateTime(start.year, start.month, start.day);
  var e = DateTime(end.year, end.month, end.day);
  if (e.isBefore(s)) e = s;
  final maxEnd = s.add(const Duration(days: 13));
  if (e.isAfter(maxEnd)) e = maxEnd;
  return AiPlannerRange(start: s, end: e);
}

/// Periodväljare → anropa AI → visa förslag.
Future<void> runAiPlannerFlow(BuildContext context) async {
  final range = await showModalBottomSheet<AiPlannerRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => wrapBottomSheet(ctx, const _AiPeriodPickerSheet()),
  );
  if (range == null || !context.mounted) return;

  final clamped = clampAiRange(range.start, range.end);
  final suggestions = await PlannerAiService.askPlanner(
    startDate: dateKey(clamped.start),
    endDate: dateKey(clamped.end),
  );
  if (!context.mounted) return;
  await showAiPlannerSheet(
    context,
    suggestions: suggestions,
    range: clamped,
  );
}

/// Visar AI-förslag som genomförbara kort (steg 1.5).
Future<void> showAiPlannerSheet(
  BuildContext context, {
  required List<PlannerSuggestion> suggestions,
  AiPlannerRange? range,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => wrapBottomSheet(
      ctx,
      _AiPlannerSheet(suggestions: suggestions, range: range),
    ),
  );
}

class _AiPeriodPickerSheet extends StatefulWidget {
  const _AiPeriodPickerSheet();

  @override
  State<_AiPeriodPickerSheet> createState() => _AiPeriodPickerSheetState();
}

class _AiPeriodPickerSheetState extends State<_AiPeriodPickerSheet> {
  late DateTime _start;
  late DateTime _end;
  String _preset = '7days';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    _start = t;
    _end = t.add(const Duration(days: 7));
  }

  void _applyPreset(String id) {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    setState(() {
      _preset = id;
      if (id == '7days') {
        _start = t;
        _end = t.add(const Duration(days: 7));
      } else if (id == 'thisWeek') {
        _start = _mondayOf(t);
        _end = _start.add(const Duration(days: 6));
      } else if (id == 'nextWeek') {
        _start = _mondayOf(t).add(const Duration(days: 7));
        _end = _start.add(const Duration(days: 6));
      }
    });
  }

  Future<void> _pickCustom() async {
    final dayColor = AppTheme.getDayAccentColor();
    final from = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Från datum',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: dayColor),
        ),
        child: child!,
      ),
    );
    if (from == null || !mounted) return;
    final maxTo = from.add(const Duration(days: 13));
    final to = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(from)
          ? from
          : (_end.isAfter(maxTo) ? maxTo : _end),
      firstDate: from,
      lastDate: maxTo,
      helpText: 'Till datum (max 14 dagar)',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: dayColor),
        ),
        child: child!,
      ),
    );
    if (to == null || !mounted) return;
    final clamped = clampAiRange(from, to);
    setState(() {
      _preset = 'custom';
      _start = clamped.start;
      _end = clamped.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final label = formatAiPeriodLabel(_start, _end);

    Widget chip(String id, String text) {
      final selected = _preset == id;
      return ChoiceChip(
        label: Text(text, style: const TextStyle(fontSize: 13)),
        selected: selected,
        selectedColor: dayColor.withValues(alpha: 0.2),
        onSelected: (_) => _applyPreset(id),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Välj period', style: AppTheme.sectionTitleStyle),
          const SizedBox(height: 6),
          Text(
            'AI:n tittar på familjens schema i vald period (max 14 dagar).',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('7days', 'Kommande 7 dagar'),
              chip('thisWeek', 'Denna vecka'),
              chip('nextWeek', 'Nästa vecka'),
              ActionChip(
                label: const Text('Välj datum...', style: TextStyle(fontSize: 13)),
                onPressed: _pickCustom,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: dayColor,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              AiPlannerRange(start: _start, end: _end),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: dayColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Hämta AI-förslag'),
          ),
        ],
      ),
    );
  }
}

class _AiPlannerSheet extends StatefulWidget {
  final List<PlannerSuggestion> suggestions;
  final AiPlannerRange? range;

  const _AiPlannerSheet({required this.suggestions, this.range});

  @override
  State<_AiPlannerSheet> createState() => _AiPlannerSheetState();
}

class _AiPlannerSheetState extends State<_AiPlannerSheet> {
  late final List<_CardState> _cards;

  @override
  void initState() {
    super.initState();
    _cards = widget.suggestions.map(_CardState.new).toList();
  }

  PlannerAction? _validatedAction(
    PlannerAction? action,
    FamilyProvider provider,
  ) {
    if (action == null) return null;
    final chores = provider.chores;
    final members = provider.familyMembers;

    switch (action) {
      case AssignChoreAction(:final choreId, :final assigneeUid):
        final choreExists = chores.any((d) => d.id == choreId);
        final memberExists = members.any((m) => m.uid == assigneeUid);
        if (!choreExists || !memberExists) return null;
        return action;
      case RescheduleChoreAction(:final choreId, :final newDate):
        final choreExists = chores.any((d) => d.id == choreId);
        if (!choreExists || parseDate(newDate) == null) return null;
        return action;
      case CreateEventAction(:final title, :final date, :final time, :final personUids):
        if (parseDate(date) == null) return null;
        final memberIds = members.map((m) => m.uid).toSet();
        final filtered =
            personUids.where((u) => memberIds.contains(u)).toList();
        return CreateEventAction(
          title: title,
          date: date,
          time: time,
          personUids: filtered,
        );
    }
  }

  Future<void> _runAction(int index, FamilyProvider provider) async {
    final card = _cards[index];
    if (card.done || card.busy) return;
    final action = _validatedAction(card.suggestion.action, provider);
    if (action == null) return;

    setState(() => card.busy = true);
    try {
      switch (action) {
        case AssignChoreAction():
          await _assignChore(action, card, provider);
        case RescheduleChoreAction():
          await _rescheduleChore(action, card);
        case CreateEventAction():
          await _createEvent(action, provider);
          if (mounted) setState(() => card.done = true);
      }
    } catch (e, stack) {
      developer.log('AI-åtgärd misslyckades', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte utföra: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => card.busy = false);
    }
  }

  Future<void> _assignChore(
    AssignChoreAction action,
    _CardState card,
    FamilyProvider provider,
  ) async {
    final doc = provider.chores.firstWhere((d) => d.id == action.choreId);
    final prev = doc.data() as Map<String, dynamic>;
    final prevWho = prev['who'] as String? ?? '';
    final prevWhoUid = prev['whoUid'] as String? ?? '';
    final prevDue = prev['dueDate'] as String?;

    final member = provider.familyMembers
        .firstWhere((m) => m.uid == action.assigneeUid);
    final name = action.assigneeName.isNotEmpty
        ? action.assigneeName
        : member.name;
    final due = card.suggestion.day;

    final update = <String, dynamic>{
      'who': name,
      'whoUid': action.assigneeUid,
    };
    if (parseDate(due) != null) {
      update['dueDate'] = due;
    }

    await doc.reference.update(update);
    if (!mounted) return;
    setState(() => card.done = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tilldelad $name'),
        action: SnackBarAction(
          label: 'Ångra',
          onPressed: () async {
            final undo = <String, dynamic>{
              'who': prevWho,
              'whoUid': prevWhoUid,
            };
            if (prevDue == null || prevDue.isEmpty) {
              undo['dueDate'] = FieldValue.delete();
            } else {
              undo['dueDate'] = prevDue;
            }
            await doc.reference.update(undo);
          },
        ),
      ),
    );
  }

  Future<void> _rescheduleChore(
    RescheduleChoreAction action,
    _CardState card,
  ) async {
    final provider = context.read<FamilyProvider>();
    final doc = provider.chores.firstWhere((d) => d.id == action.choreId);
    final prev = doc.data() as Map<String, dynamic>;
    final prevDue = prev['dueDate'] as String?;

    await doc.reference.update({'dueDate': action.newDate});
    if (!mounted) return;
    setState(() => card.done = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Flyttad till ${action.newDate}'),
        action: SnackBarAction(
          label: 'Ångra',
          onPressed: () async {
            if (prevDue == null || prevDue.isEmpty) {
              await doc.reference.update({'dueDate': FieldValue.delete()});
            } else {
              await doc.reference.update({'dueDate': prevDue});
            }
          },
        ),
      ),
    );
  }

  Future<void> _createEvent(
    CreateEventAction action,
    FamilyProvider provider,
  ) async {
    final day = parseDate(action.date)!;
    final members = provider.familyMembers;
    final user = provider.currentUser;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEventSheet(
        selectedDay: day,
        familyMembers: members,
        familyId: user?.familyId,
        initialTitle: action.title,
        initialTime: action.time,
        initialPersonUids: action.personUids,
      ),
    );
  }

  String? _buttonLabel(PlannerAction action) {
    return switch (action) {
      AssignChoreAction(:final assigneeName) =>
        'Tilldela ${assigneeName.isNotEmpty ? assigneeName : 'personen'}',
      RescheduleChoreAction(:final newDate) => 'Flytta till $newDate',
      CreateEventAction() => 'Skapa aktivitet',
    };
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final dayColor = AppTheme.getDayAccentColor();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.range != null
                        ? 'AI-förslag · ${formatAiPeriodLabel(widget.range!.start, widget.range!.end)}'
                        : 'AI-förslag',
                    style: AppTheme.sectionTitleStyle,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (_cards.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Inga förslag just nu.'),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
                itemCount: _cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final card = _cards[i];
                  final s = card.suggestion;
                  final valid = _validatedAction(s.action, provider);
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.cardDecoration(radius: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: dayColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.text,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                        if (card.done) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Utfört ✓',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ] else if (valid != null) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: card.busy
                                  ? null
                                  : () => _runAction(i, provider),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dayColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: card.busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(_buttonLabel(valid)!),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CardState {
  final PlannerSuggestion suggestion;
  bool done = false;
  bool busy = false;

  _CardState(this.suggestion);
}
