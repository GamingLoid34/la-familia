import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../navigation/app_navigation.dart';
import '../providers/family_provider.dart';
import '../screens/chores_page.dart';
import '../services/note_service.dart';
import '../services/task_service.dart';
import '../utils/checklist_updates.dart';
import '../utils/conflict_detector.dart';
import '../utils/date_utils.dart';
import '../utils/lesson_prep.dart';
import '../utils/tomorrow_overview_engine.dart';
import 'activity_detail_sheet.dart';
import 'member_day_sheet.dart';
import 'task_sheet.dart';
import 'vardag_header.dart';

/// "INFÖR I MORGON" på förälderns Hem (Androids `TomorrowOverviewPreview`).
///
/// Visas hela dagen för vuxna och betonas efter 18:00. Urval, sortering och
/// dubblettregler kommer från [TomorrowOverviewEngine]; den här widgeten
/// hämtar underlaget och ritar raderna. Varje rad visar vilken dag den gäller.
class TomorrowOverviewSection extends StatefulWidget {
  final DateTime now;
  const TomorrowOverviewSection({super.key, required this.now});

  @override
  State<TomorrowOverviewSection> createState() =>
      _TomorrowOverviewSectionState();
}

class _TomorrowOverviewSectionState extends State<TomorrowOverviewSection> {
  bool _expanded = false;
  final Set<String> _saving = {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _shifts;
  String? _shiftsFamily;

  static const _visibleRows = 4;

  Stream<QuerySnapshot<Map<String, dynamic>>> _shiftStream(String fid) {
    if (_shiftsFamily != fid || _shifts == null) {
      _shiftsFamily = fid;
      _shifts = FirebaseFirestore.instance
          .collection('work_shifts')
          .where('familyId', isEqualTo: fid)
          .snapshots();
    }
    return _shifts!;
  }

  Future<void> _guard(String key, String failure, Future<void> Function() f) async {
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      await f();
    } on ChecklistChangedException catch (e) {
      if (mounted) showVardagSnack(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showVardagSnack(context, '$failure: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  String _dayLabel(DateTime? d) {
    if (d == null) return '';
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
    final date = DateFormat('EEE d MMM', 'sv').format(day).replaceAll('.', '');
    if (diff == 1) return 'I morgon $date';
    if (diff == 0) return 'Idag $date';
    return date[0].toUpperCase() + date.substring(1);
  }

  QueryDocumentSnapshot? _eventDoc(FamilyProvider p, String? id) {
    if (id == null) return null;
    for (final d in [...p.tomorrowEvents, ...p.recurringEvents, ...p.todayEvents]) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _onTap(TomorrowOverviewItem item, FamilyProvider p) async {
    final tomorrow =
        DateTime(widget.now.year, widget.now.month, widget.now.day + 1);
    final fid = p.currentUser?.familyId ?? '';
    switch (item.kind) {
      case TomorrowOverviewKind.urgentTask:
      case TomorrowOverviewKind.upcomingTask:
      case TomorrowOverviewKind.prepTask when item.task != null:
        await showTaskSheet(context,
            familyId: fid,
            members: p.familyMembers,
            isParent: true,
            task: item.task);
        return;
      case TomorrowOverviewKind.noteInfo:
        await _showInfo(item, p);
        return;
      case TomorrowOverviewKind.noteReview:
        await AppNavigation.openInMer(context, MerRoute.inbox);
        return;
      case TomorrowOverviewKind.chore:
        QueryDocumentSnapshot? chore;
        for (final c in p.chores) {
          if (c.id == item.chore?.id) chore = c;
        }
        if (chore == null) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AddChoreSheet(
            familyMembers: p.familyMembers,
            familyId: fid,
            choreToEdit: chore,
            preselectedDay: tomorrow,
            startOnForm: true,
          ),
        );
        return;
      default:
        final doc = _eventDoc(p, item.eventId);
        if (doc != null) {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ActivityDetailSheet(
              docSnapshot: doc,
              occurrenceDate: tomorrow,
            ),
          );
        } else if (item.member != null) {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => MemberDaySheet(
              member: item.member!,
              currentUser: p.currentUser,
              initialDay: tomorrow,
            ),
          );
        }
    }
  }

  /// Informationsrad: Dölj (avslutar familjens visning via giltigheten, utan
  /// att radera brevet), Visa brevet och Stäng.
  Future<void> _showInfo(TomorrowOverviewItem item, FamilyProvider p) async {
    final note = item.note;
    if (note == null) return;
    final isParent = p.currentUser?.isParent == true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.title),
        content: Text(item.reason +
            (isParent
                ? '\n\nDölj tar bort raden från Hem. Brevet och det som skapades ur det ligger kvar i Inkorgen.'
                : '')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'close'),
              child: const Text('Stäng')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'open'),
              child: const Text('Visa brevet')),
          if (isParent)
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'hide'),
                child: const Text('Dölj')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'open') {
      await AppNavigation.openInMer(context, MerRoute.inbox);
    } else if (choice == 'hide') {
      final today = dateKey(widget.now);
      final from = note.validFrom == null
          ? null
          : (note.validFrom!.compareTo(today) > 0 ? today : note.validFrom);
      await _guard('note:${note.id}', 'Kunde inte dölja',
          () => NoteService.setValidity(note.id, validFrom: from, validTo: today));
    }
  }

  List<Widget> _trailing(TomorrowOverviewItem item, FamilyProvider p) {
    final c = AppTheme.colors();
    Widget btn(String key, String label, VoidCallback onTap) => TextButton(
          onPressed: _saving.contains(key) ? null : onTap,
          style: TextButton.styleFrom(
            foregroundColor: c.accent,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(44, 40),
          ),
          child: Text(_saving.contains(key) ? '…' : label,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        );

    final task = item.task;
    if (task != null) {
      final key = 'task:${task.id}';
      return [
        btn(key, 'Skjut upp', () {
          final base = parseDate(task.dueDate) ?? widget.now;
          final next = dateKey(DateTime(base.year, base.month, base.day + 1));
          _guard(key, 'Kunde inte skjuta upp',
              () => TaskService.postpone(task.id, next));
        }),
        btn(key, 'Klart',
            () => _guard(key, 'Kunde inte spara', () => TaskService.setDone(task.id, true))),
      ];
    }
    final ev = item.event;
    if (item.kind == TomorrowOverviewKind.prepTask && ev != null) {
      final key = 'prep:${ev.id}';
      final day = parseDate(item.occurrenceDate) ??
          DateTime(widget.now.year, widget.now.month, widget.now.day + 1);
      return [
        btn(key, 'Klart', () {
          _guard(key, 'Kunde inte spara', () {
            final ref = FirebaseFirestore.instance
                .collection('planner_events')
                .doc(ev.id);
            return LessonPrep.setDone(ref, day, done: true);
          });
        }),
      ];
    }
    if (item.kind == TomorrowOverviewKind.checklist &&
        ev != null &&
        item.checklistIndex != null) {
      final key = '${ev.id}:${item.checklistIndex}';
      return [
        btn(key, 'Klar', () {
          _guard(key, 'Kunde inte spara', () {
            final ref = FirebaseFirestore.instance
                .collection('planner_events')
                .doc(ev.id);
            return completeChecklistItem(ref, item.checklistIndex!, item.title);
          });
        }),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FamilyProvider>();
    final me = p.currentUser;
    final fid = me?.familyId ?? '';
    final c = AppTheme.colors();
    final evening = widget.now.hour >= 18;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: fid.isEmpty ? null : _shiftStream(fid),
      builder: (context, shiftSnap) {
        Widget content;
        final error = p.tasksError ?? p.notesError ?? shiftSnap.error;
        final loading = !p.tasksLoaded ||
            !p.notesLoaded ||
            (shiftSnap.connectionState == ConnectionState.waiting &&
                !shiftSnap.hasData);
        if (error != null) {
          content = Row(children: [
            Expanded(
              child: Text('Kunde inte läsa underlaget för i morgon.',
                  style: TextStyle(color: c.onCardPrimary)),
            ),
            TextButton(
              onPressed: p.retryAdultData,
              child: const Text('Försök igen'),
            ),
          ]);
        } else if (loading) {
          content = Row(children: [
            const Text('⏳', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text('Läser inför i morgon…',
                style: TextStyle(color: c.onCardSecondary)),
          ]);
        } else {
          final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
          final tomorrow = today.add(const Duration(days: 1));
          final todayKey = dateKey(today);
          final tomorrowKey = dateKey(tomorrow);
          final shiftDocs = (shiftSnap.data?.docs ?? const [])
              .where((d) {
                final date = d.data()['date'];
                return date == todayKey || date == tomorrowKey;
              })
              .toList();
          final eventDocs = p.tomorrowEvents;
          final conflicts = detectPickupConflicts(
            members: p.familyMembers,
            events: eventDocs,
            shifts: shiftDocs,
            weekStart: tomorrow,
            dayCount: 1,
          );
          final items = TomorrowOverviewEngine.build(
            today: today,
            members: p.familyMembers,
            events: [
              for (final d in eventDocs)
                {'id': d.id, ...(d.data() as Map<String, dynamic>)},
            ],
            shifts: [for (final d in shiftDocs) {'id': d.id, ...d.data()}],
            chores: [
              for (final d in p.chores)
                {'id': d.id, ...(d.data() as Map<String, dynamic>)},
            ],
            conflicts: conflicts,
            tasks: p.tasks,
            notes: p.inboxNotes.where((n) => !n.isDeleted).toList(),
            currentUid: me?.uid,
            baraMinaUppgifter: p.onlyMyTasks,
          );
          if (items.isEmpty) {
            content = Row(children: [
              const Text('😌', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Inget särskilt att förbereda i morgon',
                    style: TextStyle(color: c.onCardSecondary)),
              ),
            ]);
          } else {
            final shown = _expanded ? items : items.take(_visibleRows).toList();
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.divider),
                  _Row(
                    item: shown[i],
                    dayLabel: _dayLabel(shown[i].date),
                    onTap: shown[i].isClickable ? () => _onTap(shown[i], p) : null,
                    trailing: _trailing(shown[i], p),
                  ),
                ],
                if (items.length > _visibleRows)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                          _expanded ? 'Visa mindre' : 'Visa allt (${items.length})'),
                    ),
                  ),
              ],
            );
          }
        }

        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VardagSectionLabel('INFÖR I MORGON',
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                decoration: AppTheme.cardDecoration().copyWith(
                  border: evening
                      ? Border.all(color: c.accent.withValues(alpha: 0.45), width: 1.4)
                      : null,
                ),
                child: content,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final TomorrowOverviewItem item;
  final String dayLabel;
  final VoidCallback? onTap;
  final List<Widget> trailing;

  const _Row({
    required this.item,
    required this.dayLabel,
    required this.onTap,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    final reason = [
      if (dayLabel.isNotEmpty) dayLabel,
      if (item.reason.isNotEmpty) item.reason,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 28,
              child: Text(item.piktogram, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.onCardPrimary)),
              if (reason.isNotEmpty)
                Text(reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
            ]),
          ),
          ...trailing,
        ]),
      ),
    );
  }
}
