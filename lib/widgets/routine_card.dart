import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../utils/date_utils.dart';

/// Morgon-/kvällsrutin på Hem (ROADMAP Etapp 7).
///
/// Rutiner är trygghet, inte uppgifter — inga poäng, ingen press. Stora
/// tryckytor, ett steg i taget, nollställs automatiskt varje dag via
/// `doneDate`: när lagrat datum inte är idag räknas inga steg som klara.
class RoutineCard extends StatelessWidget {
  final QueryDocumentSnapshot routineDoc;

  const RoutineCard({super.key, required this.routineDoc});

  Future<void> _toggleStep(
    Map<String, dynamic> d,
    List<int> doneToday,
    int index,
  ) async {
    final next = List<int>.from(doneToday);
    if (next.contains(index)) {
      next.remove(index);
    } else {
      next.add(index);
    }
    try {
      await routineDoc.reference.update({
        'doneDate': dateKey(DateTime.now()),
        'doneSteps': next,
      });
    } catch (e, stack) {
      developer.log('RoutineCard toggle misslyckades',
          error: e, stackTrace: stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = routineDoc.data() as Map<String, dynamic>;
    final steps = (d['steps'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (steps.isEmpty) return const SizedBox.shrink();

    final palette = AppTheme.dayPalette();
    final isMorning = (d['type'] as String? ?? 'morning') == 'morning';

    // Auto-reset: gårdagens avbockningar räknas inte.
    final today = dateKey(DateTime.now());
    final doneToday = (d['doneDate'] == today)
        ? (d['doneSteps'] as List? ?? []).cast<int>()
        : const <int>[];
    final allDone = doneToday.length >= steps.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isMorning ? '🌅' : '🌙',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMorning ? 'Morgonrutin' : 'Kvällsrutin',
                  style: AppTheme.cardTitleStyle,
                ),
              ),
              Text(
                allDone ? 'Klart! 🌟' : '${doneToday.length} av ${steps.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: allDone ? palette.deep : Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate(steps.length, (i) {
            final step = steps[i];
            final done = doneToday.contains(i);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _toggleStep(d, doneToday, i),
                child: Padding(
                  // Stor tryckyta — lätt att träffa även på morgonen.
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Text(step['piktogram'] as String? ?? '✅',
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          step['title'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            color: done
                                ? Colors.grey.shade400
                                : AppTheme.getTextColor(),
                          ),
                        ),
                      ),
                      if (step['tid'] != null &&
                          (step['tid'] as String).isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(left: 6, right: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            step['tid'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: done
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 8),
                      ],
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: done ? palette.base : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: done ? palette.base : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: done
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
