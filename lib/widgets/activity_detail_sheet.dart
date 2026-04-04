import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';

DateTime? _parseDate(dynamic v) {
  try {
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final p = v.split('-');
      if (p.length >= 3) return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    }
  } catch (_) {}
  return null;
}

class ActivityDetailSheet extends StatefulWidget {
  final QueryDocumentSnapshot docSnapshot;

  const ActivityDetailSheet({super.key, required this.docSnapshot});

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
        (_data['checklist'] as List? ?? []).cast<Map<String, dynamic>>());
  }

  bool get _allDone => _checklist.isNotEmpty && _checklist.every((i) => i['isDone'] == true);

  Future<void> _toggleItem(int index) async {
    final newList = List<Map<String, dynamic>>.from(_checklist);
    newList[index] = {...newList[index], 'isDone': !(newList[index]['isDone'] == true)};
    setState(() => _checklist = newList);
    await widget.docSnapshot.reference.update({'checklist': newList});
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final pik = _data['piktogram'] as String? ?? '📅';
    final title = _data['title'] as String? ?? '';
    final date = _parseDate(_data['date']);
    final persons = (_data['persons'] as List? ?? []).cast<String>();
    // Prefer stored 'time' field, fall back to parsing date
    final timeStr = (_data['time'] as String?)?.isNotEmpty == true
        ? (_data['time'] as String)
        : (date != null && (date.hour != 0 || date.minute != 0)
            ? DateFormat('HH:mm').format(date)
            : '');

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Giant piktogram
                  Text(pik, style: const TextStyle(fontSize: 64)),
                  const SizedBox(height: 12),
                  // Title
                  Text(title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  // Time
                  if (timeStr.isNotEmpty)
                    Text(timeStr,
                      style: TextStyle(fontSize: 18, color: dayColor, fontWeight: FontWeight.w600)),
                  // Persons
                  if (persons.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: persons.map((p) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: dayColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20)),
                        child: Text(p, style: TextStyle(color: dayColor, fontWeight: FontWeight.w600)),
                      )).toList(),
                    ),
                  ],
                  // Checklist
                  if (_checklist.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('ATT TA MED / FÖRBEREDELSER', style: AppTheme.sectionLabelStyle),
                    ),
                    const SizedBox(height: 8),
                    ..._checklist.asMap().entries.map((entry) =>
                        _AnimatedCheckItem(
                          item: entry.value,
                          dayColor: dayColor,
                          onToggle: () => _toggleItem(entry.key),
                        )),
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
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
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
