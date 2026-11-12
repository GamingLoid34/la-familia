import 'package:provider/provider.dart';
import '../providers/family_provider.dart';
import '../utils/permissions.dart';
import '../utils/event_actions.dart';
import '../services/occurrence_mutations.dart';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/layout.dart';
import '../utils/schedule_time_utils.dart';
import '../app_theme.dart';
import 'event_reactions_row.dart';
import 'planner_event_leading.dart';

DateTime? _parseDate(dynamic v) {
  try {
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final p = v.split('-');
      if (p.length >= 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    }
  } catch (e, stack) {
    developer.log(
      'Fel vid tolkning av datum i ActivityDetailSheet',
      error: e,
      stackTrace: stack,
    );
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

class ActivityDetailSheet extends StatefulWidget {
  final QueryDocumentSnapshot docSnapshot;
  final DateTime? occurrenceDay;

  const ActivityDetailSheet({
    super.key,
    required this.docSnapshot,
    this.occurrenceDay,
  });

  @override
  State<ActivityDetailSheet> createState() => _ActivityDetailSheetState();
}

class _ActivityDetailSheetState extends State<ActivityDetailSheet> {
  late Map<String, dynamic> _data;
  late List<Map<String, dynamic>> _checklist;

  @override
  void initState() {
    super.initState();
    _data = widget.docSnapshot.data() as Map<String, dynamic>;
    _checklist = List<Map<String, dynamic>>.from(
      (_data['checklist'] as List? ?? []).cast<Map<String, dynamic>>(),
    );
  }

  bool get _allDone =>
      _checklist.isNotEmpty && _checklist.every((i) => i['isDone'] == true);

  Future<void> _openExternalUrl(String raw) async {
    var u = Uri.tryParse(raw.trim());
    if (u == null || !u.hasScheme) {
      u = Uri.tryParse('https://${raw.trim()}');
    }
    if (u != null && await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _toggleItem(int index) async {
    final newList = List<Map<String, dynamic>>.from(_checklist);
    newList[index] = {
      ...newList[index],
      'isDone': !(newList[index]['isDone'] == true),
    };
    setState(() => _checklist = newList);
    try {
      if (_data['visibility'] == 'private') {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || _data['privateOwnerUid'] != uid) {
          throw StateError('Bara ägaren kan ändra aktiviteten.');
        }
        await FirebaseFirestore.instance
            .collection('private_activities')
            .doc(uid)
            .collection('events')
            .doc(widget.docSnapshot.id)
            .update({'checklist': newList});
      } else {
        await widget.docSnapshot.reference.update({'checklist': newList});
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _checklist = List<Map<String, dynamic>>.from(
            _data['checklist'] as List? ?? [],
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunde inte spara. Försök igen.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = context.watch<FamilyProvider>().currentUser;
    if (_data['visibility'] == 'private' &&
        (FirebaseAuth.instance.currentUser?.uid != _data['privateOwnerUid'] ||
            current?.uid != _data['privateOwnerUid'] ||
            current?.familyId != _data['familyId'])) {
      return wrapBottomSheet(
        context,
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('🔒 Privat aktivitet'),
        ),
      );
    }
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
    final calDesc =
        (_data['calendarDescription'] as String?)?.trim() ??
        (_data['description'] as String?)?.trim() ??
        '';
    final calUrl = (_data['calendarUrl'] as String?)?.trim() ?? '';
    final extras = _extendedPropsMap(_data);
    final hasExtraCalendarInfo =
        location.isNotEmpty ||
        calDesc.isNotEmpty ||
        calUrl.isNotEmpty ||
        extras.isNotEmpty;

    final maxH = MediaQuery.sizeOf(context).height * 0.85;

    return wrapBottomSheet(
      context,
      Container(
        constraints: BoxConstraints(maxWidth: double.infinity, maxHeight: maxH),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (canEditDoc(current, _data) &&
                (_data['recurrence'] == null || widget.occurrenceDay != null))
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<String>(
                  tooltip: 'Ändra aktivitet',
                  onSelected: (action) {
                    final provider = context.read<FamilyProvider>();
                    final navigator = Navigator.of(context);
                    final origin = navigator.context;
                    final day =
                        widget.occurrenceDay ??
                        _parseDate(_data['date']) ??
                        DateTime.now();
                    navigator.pop();
                    handleEventMenuAction(
                      origin,
                      action: action,
                      doc: widget.docSnapshot,
                      listDay: day,
                      familyMembers: provider.familyMembers,
                      familyId: current?.familyId ?? '',
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Redigera')),
                    PopupMenuItem(value: 'delete', child: Text('Ta bort')),
                  ],
                ),
              ),
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
                            data: _data,
                            accentColor: dayColor,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          if (_data['originalOccurrenceDate'] != null) ...[
                            Text(
                              'Flyttad från ${_data['originalOccurrenceDate']}. Senare serieändringar gäller inte detta tillfälle.',
                            ),
                            if (canEditDoc(
                              context.read<FamilyProvider>().currentUser,
                              _data,
                            ))
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await undoOccurrence(
                                      widget.docSnapshot.reference,
                                      _data,
                                    );
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Kunde inte ångra: $e'),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text(
                                  'Ångra flytt – återställ enligt serien (kräver internet)',
                                ),
                              ),
                          ],
                          if (timeLine.isNotEmpty)
                            Text(
                              timeLine,
                              style: TextStyle(
                                fontSize: 18,
                                color: dayColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (persons.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: persons
                                  .map(
                                    (p) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: dayColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        p,
                                        style: TextStyle(
                                          color: dayColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_data['visibility'] == 'private')
                      const Text(
                        '🔒 Privat aktivitet',
                        textAlign: TextAlign.center,
                      )
                    else
                      EventReactionsRow(eventRef: widget.docSnapshot.reference),
                    if (hasExtraCalendarInfo) ...[
                      const SizedBox(height: 24),
                      Text(
                        'MER INFORMATION',
                        style: AppTheme.sectionLabelStyle,
                      ),
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
                                  color: AppTheme.getTextColor(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (calDesc.isNotEmpty ||
                            calUrl.isNotEmpty ||
                            extras.isNotEmpty)
                          const SizedBox(height: 14),
                      ],
                      if (calDesc.isNotEmpty)
                        SelectableText(
                          calDesc,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: AppTheme.getTextColor(),
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
                                color: dayColor,
                                fontWeight: FontWeight.w600,
                              ),
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
                                    color: AppTheme.getSubTextColor(),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  extras[k]!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                    color: AppTheme.getTextColor(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                    // Checklist
                    if (_checklist.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ATT TA MED / FÖRBEREDELSER',
                          style: AppTheme.sectionLabelStyle,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._checklist.asMap().entries.map(
                        (entry) => _AnimatedCheckItem(
                          item: entry.value,
                          dayColor: dayColor,
                          onToggle: () => _toggleItem(entry.key),
                        ),
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
                                  color: const Color(
                                    0xFF6BAE75,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Text(
                                    '🌟 Bra jobbat! Du är redo!',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6BAE75),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('no-banner')),
                      ),
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
  final Map<String, dynamic> item;
  final Color dayColor;
  final VoidCallback onToggle;

  const _AnimatedCheckItem({
    required this.item,
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
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).chain(CurveTween(curve: Curves.elasticOut)).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _tap() {
    _anim.forward().then((_) => _anim.reverse());
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final isDone = widget.item['isDone'] == true;
    final label = widget.item['item'] as String? ?? '';

    return GestureDetector(
      onTap: _tap,
      child: Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isDone
              ? widget.dayColor.withValues(alpha: 0.08)
              : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ScaleTransition(
              scale: _scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isDone ? widget.dayColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone ? widget.dayColor : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: isDone
                    ? Icon(Icons.check, color: AppTheme.onAccent, size: 18)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  color: isDone
                      ? AppTheme.getSubTextColor()
                      : AppTheme.getTextColor(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
