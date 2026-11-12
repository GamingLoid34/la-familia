import 'package:flutter/material.dart';
import '../utils/date_utils.dart';

/// På många enheter ser 📅 ut som en fast kalenderblad med "17 juli" — det är typsnittet,
/// inte händelsens datum. För importerade händelser visar vi därför riktigt dagsnummer.
bool plannerEventIsCalendarImport(Map<String, dynamic> data) =>
    data['source'] == 'calendar';

int? plannerEventDayOfMonth(Map<String, dynamic> data) =>
    parseDate(data['date'])?.day;

enum PlannerEventLeadingStyle {
  /// Vit/ljus kortbakgrund, färgad ram runt dagsnummer.
  normal,

  /// Färgad yta (t.ex. "nu"-kort) — ljust dagsnummer.
  onColoredSurface,
}

class PlannerEventLeading extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accentColor;
  final double emojiSize;
  final PlannerEventLeadingStyle leadingStyle;

  const PlannerEventLeading({
    super.key,
    required this.data,
    required this.accentColor,
    this.emojiSize = 32,
    this.leadingStyle = PlannerEventLeadingStyle.normal,
  });

  @override
  Widget build(BuildContext context) {
    final day = plannerEventDayOfMonth(data);
    if (plannerEventIsCalendarImport(data) && day != null) {
      final box = emojiSize * 1.15;
      final onColor = leadingStyle == PlannerEventLeadingStyle.onColoredSurface;
      final bg = onColor
          ? Colors.white.withValues(alpha: 0.22)
          : accentColor.withValues(alpha: 0.15);
      final border = onColor
          ? Colors.white.withValues(alpha: 0.45)
          : accentColor.withValues(alpha: 0.4);
      final fg = onColor ? Colors.white : accentColor;
      return SizedBox(
        width: box,
        height: box,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Center(
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: emojiSize * 0.5,
                fontWeight: FontWeight.w800,
                color: fg,
                height: 1,
              ),
            ),
          ),
        ),
      );
    }
    final pik = data['piktogram'] as String? ?? '📅';
    return Text(pik, style: TextStyle(fontSize: emojiSize * 0.85));
  }
}

/// Större variant för detaljkort / fokusläge (samma logik).
class PlannerEventLeadingHero extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accentColor;

  const PlannerEventLeadingHero({
    super.key,
    required this.data,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final day = plannerEventDayOfMonth(data);
    if (plannerEventIsCalendarImport(data) && day != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: accentColor,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Importerad kalender',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      );
    }
    final pik = data['piktogram'] as String? ?? '📅';
    return Text(pik, style: const TextStyle(fontSize: 64));
  }
}
