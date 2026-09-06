import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_theme.dart';
import '../../../providers/family_provider.dart';
import '../display_module_registry.dart';
import 'footer_modules.dart';

/// Modul: Nedräkning ("nedrakning") (FAS 4).
/// Visar de 2–3 närmaste framtida målen från familjens `countdowns`.
/// Fungerar både som footerkort (88 px) och som fullstort kort.
class NedrakningModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const NedrakningModule({super.key, required this.moduleContext});

  DateTime? _parseTargetDate(Map<String, dynamic> data) {
    final raw = data['targetDate'] ??
        data['targetTime'] ??
        data['date'] ??
        data['endDate'];

    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final fid = provider.currentUser?.familyId ?? '';
    final palette = AppTheme.dayPalette(moduleContext.now.weekday);

    if (fid.isEmpty) {
      return DisplayFooterCard(
        iconData: Icons.celebration_rounded,
        iconColor: palette.base,
        title: 'Nedräkning',
        content: 'Ingen familj vald',
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('countdowns')
          .where('familyId', isEqualTo: fid)
          .snapshots(),
      builder: (context, snapshot) {
        final now = moduleContext.now;
        final today = DateTime(now.year, now.month, now.day);

        final items = <_CountdownItem>[];

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final targetDate = _parseTargetDate(data);
            if (targetDate == null) continue;

            final targetDay = DateTime(
              targetDate.year,
              targetDate.month,
              targetDate.day,
            );
            final diffDays = targetDay.difference(today).inDays;
            if (diffDays < 0) continue; // passerad

            final title = (data['title'] ??
                    data['name'] ??
                    data['label'] ??
                    'Mål')
                .toString()
                .trim();
            final emoji = (data['emoji'] ?? data['icon'] ?? '🎈')
                .toString()
                .trim();

            items.add(_CountdownItem(
              title: title.isNotEmpty ? title : 'Mål',
              emoji: emoji.isNotEmpty ? emoji : '🎈',
              diffDays: diffDays,
            ));
          }
        }

        // Sortera närmast först
        items.sort((a, b) => a.diffDays.compareTo(b.diffDays));

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight <= 100) {
              // Footerläge
              final footerText = items.isEmpty
                  ? 'Inga aktiva nedräkningar'
                  : items.take(2).map((item) {
                      final dayStr = item.diffDays == 0
                          ? 'Idag'
                          : item.diffDays == 1
                              ? '1 dag'
                              : '${item.diffDays} dagar';
                      return '${item.emoji} $dayStr · ${item.title}';
                    }).join('   ·   ');

              return DisplayFooterCard(
                iconData: Icons.celebration_rounded,
                iconColor: palette.base,
                title: 'Nedräkning',
                content: footerText,
              );
            }

            // Stort kortläge (om placerad i main eller side)
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E5EE)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.celebration_rounded,
                        size: 22,
                        color: palette.base,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Nedräkningar',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E5EE)),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Inga aktiva nedräkningar',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 15,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length.clamp(0, 5),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final dayStr = item.diffDays == 0
                              ? 'Idag'
                              : item.diffDays == 1
                                  ? '1 dag'
                                  : '${item.diffDays} dagar';

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FA),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  item.emoji,
                                  style: const TextStyle(fontSize: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.base.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    dayStr,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: palette.deep,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _CountdownItem {
  final String title;
  final String emoji;
  final int diffDays;

  _CountdownItem({
    required this.title,
    required this.emoji,
    required this.diffDays,
  });
}
