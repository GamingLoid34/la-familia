import 'package:flutter/material.dart';

class AppTheme {
  // ─── NPF Day Colors ────────────────────────────────────────────────────────
  static Color getNpfDayColor(int weekday) {
    switch (weekday) {
      case 1:
        return const Color(0xFF6BAE75); // Monday  — sage green
      case 2:
        return const Color(0xFF7EB5D6); // Tuesday — slate blue
      case 3:
        return const Color(0xFFBDBDBD); // Wednesday — silver grey
      case 4:
        return const Color(0xFFA0714F); // Thursday — cognac brown
      case 5:
        return const Color(0xFFEDD87A); // Friday  — honey gold
      case 6:
        return const Color(0xFFE8A5B0); // Saturday — dusty rose
      case 7:
        return const Color(0xFFD95F4B); // Sunday  — brick red
      default:
        return const Color(0xFF6BAE75);
    }
  }

  /// Returns dark text for light NPF days, white for saturated days.
  static Color getNpfTextColor(int weekday) {
    switch (weekday) {
      case 3: // Wednesday grey
      case 5: // Friday yellow
      case 6: // Saturday rose
        return const Color(0xFF1A1A2E);
      default:
        return Colors.white;
    }
  }

  static Color getDayAccentColor([int? weekday]) =>
      getNpfDayColor(weekday ?? DateTime.now().weekday);

  // ─── App Background ────────────────────────────────────────────────────────
  static BoxDecoration getBackground() {
    final color = getNpfDayColor(DateTime.now().weekday);
    return BoxDecoration(
      color: Color.alphaBlend(
        color.withValues(alpha: 0.08),
        const Color(0xFFF5F0EB),
      ),
    );
  }

  // ─── Colors ────────────────────────────────────────────────────────────────
  static Color getCardColor() => Colors.white;
  static Color getTextColor() => const Color(0xFF1A1A2E);
  static Color getSubTextColor() => Colors.grey.shade500;

  // ─── Card Decoration ───────────────────────────────────────────────────────
  static BoxDecoration cardDecoration({
    double radius = 20,
    Color? color,
  }) =>
      BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      );

  // ─── Event Icons ───────────────────────────────────────────────────────────
  static IconData getEventIcon(String title, String type) {
    final t = title.toLowerCase();
    if (t.contains('läkare') || t.contains('bup') || t.contains('sjukhus'))
      return Icons.local_hospital_rounded;
    if (t.contains('skola') || t.contains('läxa')) return Icons.school_rounded;
    if (t.contains('tandläkare') || t.contains('tand'))
      return Icons.medical_services_rounded;
    if (type == 'work' || t.contains('jobb')) return Icons.work_rounded;
    if (type == 'food' || t.contains('middag') || t.contains('lunch'))
      return Icons.restaurant_rounded;
    if (t.contains('sport') || t.contains('fotboll') || t.contains('simning'))
      return Icons.sports_rounded;
    if (t.contains('möte')) return Icons.handshake_rounded;
    return Icons.event_rounded;
  }

  // ─── Typography ────────────────────────────────────────────────────────────
  static TextStyle get pageTitleStyle => const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
      );

  static TextStyle get sectionLabelStyle => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 0.08 * 11,
      );

  static TextStyle get sectionTitleStyle => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A2E),
      );

  static TextStyle get cardTitleStyle => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A2E),
      );

  static TextStyle get bodyStyle => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Color(0xFF1A1A2E),
      );

  static TextStyle get captionStyle => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: Colors.grey.shade500,
      );
}
