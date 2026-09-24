import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/family_provider.dart';
import '../utils/checklist_updates.dart';
import '../utils/event_actions.dart';
import '../utils/layout.dart';
import '../utils/lesson_prep.dart';
import '../utils/permissions.dart';
import 'vardag_header.dart';
import '../utils/schedule_time_utils.dart';
import '../app_theme.dart';
import 'event_reactions_row.dart';
import 'planner_event_leading.dart';

DateTime? _parseDate(dynamic v) {
  try {
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final p = v.split('-');
      if (p.length >= 3) return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    }
  } catch (e, stack) {
    developer.log('Fel vid tolkning av datum i ActivityDetailSheet', error: e, stackTrace: stack);
  }
  return null;
}

String _prettyIcsExtendedKey(String k) {
  var s = k.trim();
  if (s.toUpperCase().startsWith('X-')) {
    s = s.substring(2);
  }
  return s.replaceAll('_', ' ').replaceAll('-', ' ').trim();
}

Map<String, String> _extendedPropsMap(Map<String, dynamic> data) {
  final raw = data['calendarExtendedProps'];
  if (raw is! Map) return {};
  final out = <String, String>{};
  for (final e in raw.entries) {
    final v = e.value;
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isEmpty) continue;
    out[e.key.toString()] = s;
  }
  return out;
}

/// Gemensam aktivitetsdetalj från Hem, Kalender och Min dag.
///
/// Läser aktiviteten live, så att en avbockning någon annan gjort syns direkt
/// och så att den egna avbockningen aldrig skriver tillbaka en gammal lista.
/// [occurrenceDate] är den förekomst användaren tittar på — för en
/// återkommande aktivitet används den vid "Bara denna gång" och för
/// lektionsförberedelsen, aldrig seriens startdag eller veckans måndag.
class ActivityDetailSheet extends StatefulWidget {
  final QueryDocumentSnapshot docSnapshot;
  final DateTime? occurrenceDate;

  const ActivityDetailSheet({
    super.key,
    required this.docSnapshot,
    this.occurrenceDate,
  });

  @override
  State<ActivityDetailSheet> createState() => _ActivityDetailSheetState();
}

class _ActivityDetailSheetState extends State<ActivityDetailSheet> {
  late Map<String, dynamic> _data;
  late final DocumentReference<Map<String, dynamic>> _ref;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _gone = false;
  final Set<int> _savingRows = {};
  bool _savingPrep = false;

  List<dynamic> get _rows => checklistRowsOf(_data['checklist']);

  DateTime get _day =>
      widget.occurrenceDate ?? _parseDate(_data['date']) ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.docSnapshot.data() as Map);
    _ref = FirebaseFirestore.instance
        .collection('planner_events')
        .doc(widget.docSnapshot.id);
    _sub = _ref.snapshots().listen((snap) {
      if (!mounted) return;
      if (!snap.exists) {
        setState(() => _gone = true);
        return;
      }
      setState(() {
        _gone = false;
        _data = snap.data()!;
      });
    }, onError: (Object e, StackTrace st) {
      developer.log('ActivityDetailSheet: kunde inte läsa live',
          error: e, stackTrace: st);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool get _allDone {
    final rows = _rows;
    return rows.isNotEmpty && rows.every(checklistIsDone);
  }

  Future<void> _openExternalUrl(String raw) async {
    var u = Uri.tryParse(raw.trim());
    if (u == null || !u.hasScheme) {
      u = Uri.tryParse('https://${raw.trim()}');
    }
    if (u != null && await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  /// Bockar en rad i en transaktion mot den färska listan — andra rader och
  /// andras avbockningar rörs inte.
  Future<void> _toggleItem(int index) async {
    if (_savingRows.contains(index)) return;
    final rows = _rows;
    if (index >= rows.length) return;
    final text = checklistTextOf(rows[index]) ?? '';
    setState(() => _savingRows.add(index));
    try {
      await setChecklistItemDone(_ref, index, text,
          done: !checklistIsDone(rows[index]));
    } on ChecklistChangedException catch (e) {
      if (mounted) showVardagSnack(context, e.message, isError: true);
    } catch (e) {
      if (mounted) {
        showVardagSnack(context, 'Kunde inte spara: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingRows.remove(index));
    }
  }

  Future<void> _togglePrep() async {
    if (_savingPrep) return;
    setState(() => _savingPrep = true);
    try {
      await LessonPrep.setDone(_ref, _day,
          done: !LessonPrep.isDoneOn(_data, _day));
    } catch (e) {
      if (mounted) {
        showVardagSnack(context, 'Kunde inte spara: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingPrep = false);
    }
  }

  Future<void> _edit() async {
    final p = context.read<FamilyProvider>();
    await handleEventMenuAction(
      context,
      action: 'edit',
      doc: widget.docSnapshot,
      listDay: _day,
      familyMembers: p.familyMembers,
      familyId: p.currentUser?.familyId ?? '',
    );
  }

  Future<void> _delete() async {
    final p = context.read<FamilyProvider>();
    final deleted = await handleEventMenuAction(
      context,
      action: 'delete',
      doc: widget.docSnapshot,
      listDay: _day,
      familyMembers: p.familyMembers,
      familyId: p.currentUser?.familyId ?? '',
    );
    if (deleted && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final title = _data['title'] as String? ?? '';
    final date = _parseDate(_data['date']);
    final persons = (_data['persons'] as List? ?? []).cast<String>();
    // Prefer stored 'time' field, fall back to parsing date
    final timeStr = (_data['time'] as String?)?.isNotEmpty == true
        ? (_data['time'] as String)
        : (date != null && (date.hour != 0 || date.minute != 0)
            ? DateFormat('HH:mm').format(date)
            : '');
    final endTime = (_data['endTime'] as String?)?.trim() ?? '';
    final String timeLine;
    if (timeStr.isNotEmpty && endTime.isNotEmpty) {
      final dur = durationLabelHm(timeStr, endTime);
      timeLine = '$timeStr – $endTime${dur.isEmpty ? '' : ' ($dur)'}';
    } else {
      timeLine = timeStr;
    }

    final location = (_data['location'] as String?)?.trim() ?? '';
    final calDesc = (_data['calendarDescription'] as String?)?.trim() ??
        (_data['description'] as String?)?.trim() ??
        '';
    final calUrl = (_data['calendarUrl'] as String?)?.trim() ?? '';
    final extras = _extendedPropsMap(_data);
    final hasExtraCalendarInfo = location.isNotEmpty ||
        calDesc.isNotEmpty ||
        calUrl.isNotEmpty ||
        extras.isNotEmpty;

    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    final canEdit =
        canEditDoc(context.read<FamilyProvider>().currentUser, _data);

    return wrapBottomSheet(
      context,
      Container(
      constraints: BoxConstraints(maxWidth: double.infinity, maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle + tydlig stängning
          Row(children: [
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Stäng',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ]),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        PlannerEventLeadingHero(
                            data: _data, accentColor: dayColor),
                        const SizedBox(height: 12),
                        Text(title,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        if (timeLine.isNotEmpty)
                          Text(timeLine,
                              style: TextStyle(
                                  fontSize: 18,
                                  color: dayColor,
                                  fontWeight: FontWeight.w600)),
                        if (persons.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: persons
                                .map((p) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: dayColor.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Text(p,
                                          style: TextStyle(
                                              color: dayColor,
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  EventReactionsRow(eventRef: widget.docSnapshot.reference),
                  if (hasExtraCalendarInfo) ...[
                    const SizedBox(height: 24),
                    Text('MER INFORMATION',
                        style: AppTheme.sectionLabelStyle),
                    const SizedBox(height: 10),
                    if (location.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📍', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              location,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.35,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (calDesc.isNotEmpty || calUrl.isNotEmpty || extras.isNotEmpty)
                        const SizedBox(height: 14),
                    ],
                    if (calDesc.isNotEmpty)
                      SelectableText(
                        calDesc,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    if (calUrl.isNotEmpty) ...[
                      if (calDesc.isNotEmpty) const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openExternalUrl(calUrl),
                          icon: Icon(Icons.link_rounded, color: dayColor),
                          label: Text(
                            'Öppna länk',
                            style: TextStyle(
                                color: dayColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                    if (extras.isNotEmpty) ...[
                      if (calDesc.isNotEmpty || calUrl.isNotEmpty)
                        const SizedBox(height: 8),
                      for (final k in (extras.keys.toList()..sort()))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _prettyIcsExtendedKey(k),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                extras[k]!,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                  // Checklist
                  if (LessonPrep.isEnabled(_data)) ...[
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('FÖRBEREDELSE DAGEN INNAN',
                          style: AppTheme.sectionLabelStyle),
                    ),
                    const SizedBox(height: 8),
                    _AnimatedCheckItem(
                      label: LessonPrep.textOf(_data) ?? '',
                      isDone: LessonPrep.isDoneOn(_data, _day),
                      dayColor: dayColor,
                      onToggle: _togglePrep,
                    ),
                    Text(
                      'Gäller ${DateFormat('EEEE d MMMM', 'sv').format(_day)}.',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.getSubTextColor()),
                    ),
                  ],
                  if (_rows.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('ATT TA MED / FÖRBEREDELSER', style: AppTheme.sectionLabelStyle),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _rows.length; i++)
                      _AnimatedCheckItem(
                        label: checklistTextOf(_rows[i]) ?? '',
                        isDone: checklistIsDone(_rows[i]),
                        dayColor: dayColor,
                        onToggle: () => _toggleItem(i),
                      ),
                    // All done banner
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: _allDone
                          ? Container(
                              key: const ValueKey('done-banner'),
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6BAE75).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16)),
                              child: const Center(
                                child: Text('🌟 Bra jobbat! Du är redo!',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                                    color: Color(0xFF6BAE75))),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('no-banner')),
                    ),
                  ],
                  if (_gone) ...[
                    const SizedBox(height: 16),
                    const Text('Aktiviteten finns inte längre.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                  if (!_gone && canEdit) ...[
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Ta bort'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB3261E),
                            side: const BorderSide(color: Color(0x80B3261E)),
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _edit,
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Redigera'),
                          style: FilledButton.styleFrom(
                            backgroundColor: dayColor,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ─── ANIMATED CHECK ITEM ─────────────────────────────────────────────────────
class _AnimatedCheckItem extends StatefulWidget {
  final String label;
  final bool isDone;
  final Color dayColor;
  final VoidCallback onToggle;

  const _AnimatedCheckItem({
    required this.label,
    required this.isDone,
    required this.dayColor,
    required this.onToggle,
  });

  @override
  State<_AnimatedCheckItem> createState() => _AnimatedCheckItemState();
}

class _AnimatedCheckItemState extends State<_AnimatedCheckItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: 1.2)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_anim);
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  void _tap() {
    _anim.forward().then((_) => _anim.reverse());
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final isDone = widget.isDone;
    final label = widget.label;

    return GestureDetector(
      onTap: _tap,
      child: Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isDone
              ? widget.dayColor.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          ScaleTransition(
            scale: _scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: isDone ? widget.dayColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDone ? widget.dayColor : Colors.grey.shade400,
                  width: 2)),
              child: isDone
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: TextStyle(
            fontSize: 16,
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? Colors.grey.shade400 : AppTheme.getTextColor()))),
        ]),
      ),
    );
  }
}