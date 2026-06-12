import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../providers/family_provider.dart';
import '../utils/person_match.dart';

/// Enkel vy: bara familjens sysslor att bocka av (från hem-skärmen).
class TodayChoresSheet extends StatelessWidget {
  /// Om satt visas bara sysslor tilldelade personen (uid vinner över namn).
  final String? onlyAssignedTo;
  final String? onlyAssignedToUid;

  const TodayChoresSheet({super.key, this.onlyAssignedTo, this.onlyAssignedToUid});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final dayColor = AppTheme.getDayAccentColor();
    final raw = context.watch<FamilyProvider>().chores;
    var chores = onlyAssignedTo == null
        ? raw.toList()
        : raw.where((d) {
            return assignedToPerson(d.data() as Map<String, dynamic>,
                uid: onlyAssignedToUid ?? '', name: onlyAssignedTo!);
          }).toList();
    chores = chores
        .where((d) => (d.data() as Map)['isDone'] != true)
        .toList();

    final sorted = List<QueryDocumentSnapshot>.from(chores)
      ..sort((a, b) {
        final da = (a.data() as Map)['isDone'] == true ? 1 : 0;
        final db = (b.data() as Map)['isDone'] == true ? 1 : 0;
        return da.compareTo(db);
      });

    final done =
        chores.where((d) => (d.data() as Map)['isDone'] == true).length;
    final total = chores.length;

    return Container(
      width: screenW,
      constraints: BoxConstraints(maxWidth: screenW, maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SizedBox(
        height: maxH,
        child: Column(
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
                          onlyAssignedTo == null
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
              child: sorted.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                      child: Center(
                        child: Text(
                          'Inga sysslor just nu. Lägg till under Planering (+).',
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
                      itemCount: sorted.length,
                      itemBuilder: (_, i) => _ChoreToggleTile(
                        key: ValueKey(sorted[i].id),
                        doc: sorted[i],
                        dayColor: dayColor,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoreToggleTile extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;

  const _ChoreToggleTile({
    super.key,
    required this.doc,
    required this.dayColor,
  });

  @override
  State<_ChoreToggleTile> createState() => _ChoreToggleTileState();
}

class _ChoreToggleTileState extends State<_ChoreToggleTile> {
  bool _saving = false;

  Future<void> _toggleDone(bool current) async {
    setState(() => _saving = true);
    try {
      await widget.doc.reference.update({'isDone': !current});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';
    final who = d['who'] as String? ?? '';
    final isDone = d['isDone'] == true;
    final points = (d['points'] as int?) ?? 10;

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
              const SizedBox(width: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+$points ⭐',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ),
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
