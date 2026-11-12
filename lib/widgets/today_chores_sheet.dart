import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/date_utils.dart';
import '../utils/chore_utils.dart';
import '../utils/layout.dart';
import '../app_theme.dart';
import '../providers/family_provider.dart';
import '../services/notification_service.dart';
import '../services/chore_service.dart';

/// Enkel vy: bara familjens sysslor att bocka av (från hem-skärmen).
class TodayChoresSheet extends StatefulWidget {
  /// Om satt visas bara sysslor tilldelade personen (uid vinner över namn).
  final String? onlyAssignedTo;
  final String? onlyAssignedToUid;

  const TodayChoresSheet(
      {super.key, this.onlyAssignedTo, this.onlyAssignedToUid});

  @override
  State<TodayChoresSheet> createState() => _TodayChoresSheetState();
}

class _TodayChoresSheetState extends State<TodayChoresSheet> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _onChoreCompleted() {
    _confettiController.play();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final dayColor = AppTheme.getDayAccentColor();
    final today = DateTime.now();
    final raw = context.watch<FamilyProvider>().chores;
    var chores = raw.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!choreOccursOnDay(d, today)) return false;
      if (widget.onlyAssignedTo == null) return true;
      return choreAssignedToOnDay(d, today,
          uid: widget.onlyAssignedToUid ?? '',
          name: widget.onlyAssignedTo!);
    }).toList();

    // Räkna FÖRE filtrering av klara — annars blir "X av Y" alltid 0.
    final total = chores.length;
    final done = chores
        .where((d) => choreDoneOnDay(d.data() as Map<String, dynamic>, today))
        .length;

    final open = chores
        .where((d) => !choreDoneOnDay(d.data() as Map<String, dynamic>, today))
        .toList();

    return wrapBottomSheet(
      context,
      Container(
      constraints: BoxConstraints(maxWidth: double.infinity, maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SizedBox(
        height: maxH,
        child: Stack(
          children: [
            Column(
              children: [
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.onlyAssignedTo == null
                                  ? 'Sysslor idag'
                                  : 'Dina sysslor idag',
                              style: AppTheme.sectionTitleStyle,
                            ),
                            if (total > 0)
                              Text(
                                '$done av $total klara',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Stäng',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: open.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                          child: Center(
                            child: Text(
                              total > 0 && done == total
                                  ? 'Alla sysslor klara! 🌟'
                                  : 'Inga sysslor just nu. Lägg till under Planering (+).',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                          itemCount: open.length,
                          itemBuilder: (_, i) => _ChoreToggleTile(
                            key: ValueKey(open[i].id),
                            doc: open[i],
                            dayColor: dayColor,
                            onComplete: _onChoreCompleted,
                          ),
                        ),
                ),
              ],
            ),
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.1,
              numberOfParticles: 20,
              colors: [dayColor, Colors.amber, Colors.pink, Colors.purple],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _ChoreToggleTile extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;
  final VoidCallback onComplete;

  const _ChoreToggleTile({
    super.key,
    required this.doc,
    required this.dayColor,
    required this.onComplete,
  });

  @override
  State<_ChoreToggleTile> createState() => _ChoreToggleTileState();
}

class _ChoreToggleTileState extends State<_ChoreToggleTile> {
  bool _saving = false;
  bool? _optimisticDone;

  Future<void> _toggleDone(bool current) async {
    final next = !current;
    setState(() {
      _saving = true;
      _optimisticDone = next;
    });
    try {
      await ChoreService.completeChore(
        choreId: widget.doc.id,
        done: next,
        dayKey: dateKey(DateTime.now()),
      );
      if (next) {
        await NotificationService.cancelChoreInstance(
          widget.doc.id,
          DateTime.now(),
        );
      }
      if (next) widget.onComplete();
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticDone = current);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('permission-denied')
                  ? 'Du kan bara bocka av egna eller otilldelade sysslor.'
                  : 'Kunde inte spara: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _optimisticDone = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';
    final who = d['who'] as String? ?? '';
    final isDone = _optimisticDone ??
        choreDoneOnDay(d, DateTime.now());
    final weight = (d['points'] as int?) ?? 0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isDone ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        decoration: AppTheme.cardDecoration(radius: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(pik, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (who.isNotEmpty)
                      Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              if (weight > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '★$weight',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _saving ? null : () => _toggleDone(isDone),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDone ? widget.dayColor : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDone ? widget.dayColor : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (isDone
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
