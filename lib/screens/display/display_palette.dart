import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app_theme.dart';

/// Central temapalett för storskärmen (FAS 6c).
///
/// Samlar alla färger för ljust och mörkt läge:
/// - Bakgrund, kort, kanter, text och avdelare
/// - Dagsfärger för veckotavlan och middagsveckan
/// - Ramplattor och aktivitetskort
/// - Accentfärger och NPF-lågstimuli
class DisplayPalette {
  final bool isDark;
  final Color background;
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textMuted;
  final Color divider;

  const DisplayPalette._({
    required this.isDark,
    required this.background,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.divider,
  });

  /// Standard ljust tema (dagens storskärmsvärden).
  static const DisplayPalette light = DisplayPalette._(
    isDark: false,
    background: Color(0xFFF3F4F8),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE2E5EE),
    textPrimary: Color(0xFF1A1A2E),
    textMuted: Color(0xFF5C6877),
    divider: Color(0xFFE2E5EE),
  );

  /// Mörkt tema för väggen (FAS 6c Beslut 2).
  static const DisplayPalette dark = DisplayPalette._(
    isDark: true,
    background: Color(0xFF0F1218),
    card: Color(0xFF1A1F2A),
    cardBorder: Color(0xFF2A3140),
    textPrimary: Color(0xFFE8EAF0),
    textMuted: Color(0xFF98A2B3),
    divider: Color(0xFF242B38),
  );

  // ─── Dagsfärger (Veckotavlan & Moduler) ───────────────────────────────────

  /// Bakgrundsfärg för dagshuvudet i veckotavlan.
  ///
  /// - IDAG: full p.gradient (eller p.base i lågstimuli)
  /// - Ljust: p.base alpha 0.22 (kommande) / 0.12 (passerad) på vit/bakgrund
  /// - Mörkt: p.base alpha 0.30 (0.20 för sön) / 0.16 (passerad) på bakgrund
  Color dayHeaderBg(
    int weekday, {
    required bool isToday,
    required bool isPast,
    bool isLowStimuli = false,
  }) {
    final p = AppTheme.dayPalette(weekday);
    if (isToday) {
      return p.base;
    }
    if (isDark) {
      // Söndag (weekday 7) sänks till 0.20 i kommande för att nå WCAG AA >= 4.5:1
      final alpha = isPast ? 0.16 : (weekday == 7 ? 0.20 : 0.30);
      return Color.alphaBlend(p.base.withValues(alpha: alpha), background);
    } else {
      final alpha = isPast ? 0.12 : 0.22;
      return Color.alphaBlend(p.base.withValues(alpha: alpha), Colors.white);
    }
  }

  /// Kantfärg för dagshuvudet i veckotavlan.
  Color dayHeaderBorder(
    int weekday, {
    bool isToday = false,
    bool isPast = false,
  }) {
    if (isToday) return Colors.transparent;
    final p = AppTheme.dayPalette(weekday);
    if (isDark) {
      return Color.alphaBlend(
        p.base.withValues(alpha: isPast ? 0.18 : 0.30),
        cardBorder,
      );
    } else {
      return Color.alphaBlend(
        p.base.withValues(alpha: isPast ? 0.15 : 0.25),
        cardBorder,
      );
    }
  }

  /// Skugga för IDAG-huvudet i veckotavlan.
  ///
  /// Stängs av helt (returnerar `null`) vid lågstimuli-läge (NPF).
  List<BoxShadow>? idagHeaderBoxShadow(
    int weekday, {
    required bool isLowStimuli,
  }) {
    if (isLowStimuli) return null;
    final p = AppTheme.dayPalette(weekday);
    return [
      BoxShadow(
        color: p.base.withValues(alpha: 0.25),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Textfärg för dagshuvudets rubrik (veckodag och datum).
  ///
  /// Garanterar >= 4.5:1 (WCAG AA) i båda teman:
  /// - IDAG: Beräknas via [idagTextColorFor] mot det ljusaste gradientstoppet
  /// - Mörkt: p.light för alla dagar
  /// - Ljust: fördjupade ädelstensfärger för att klara >= 4.5:1 mot tintad bakgrund
  Color dayHeaderTextColor(
    int weekday, {
    bool isToday = false,
    bool isPast = false,
  }) {
    if (isToday) {
      return idagTextColorFor(weekday);
    }
    final p = AppTheme.dayPalette(weekday);
    if (isDark) {
      return isPast ? p.light.withValues(alpha: 0.75) : p.light;
    }

    // Ljust läge: Fördjupade ädelstenstoner för WCAG AA >= 4.5:1
    Color fg;
    switch (weekday) {
      case 1: // Måndag — smaragd (CR = 5.30:1 / 5.86:1)
        fg = const Color(0xFF1E633B);
        break;
      case 2: // Tisdag — safir (CR = 5.95:1 / 6.60:1)
        fg = const Color(0xFF23527C);
        break;
      case 3: // Onsdag — silver (CR = 5.95:1 / 6.51:1)
        fg = const Color(0xFF475260);
        break;
      case 4: // Torsdag — koppar (CR = 5.39:1 / 6.08:1)
        fg = p.deep;
        break;
      case 5: // Fredag — guld/bärnsten (CR = 6.15:1 / 6.50:1)
        fg = const Color(0xFF6B4F12);
        break;
      case 6: // Lördag — roséguld (CR = 5.80:1 / 6.38:1)
        fg = const Color(0xFF87374D);
        break;
      case 7: // Söndag — granat (CR = 5.26:1 / 6.00:1)
        fg = p.deep;
        break;
      default:
        fg = p.deep;
    }
    return isPast ? fg.withValues(alpha: 0.70) : fg;
  }

  /// Väderfärg i dagshuvudet.
  Color dayHeaderWeatherColor(
    int weekday, {
    required bool isToday,
    required bool isPast,
  }) {
    if (isToday) {
      final onCol = AppTheme.dayPalette(weekday).onColor;
      return onCol == Colors.white
          ? Colors.white.withValues(alpha: 0.90)
          : onCol.withValues(alpha: 0.85);
    }
    return dayHeaderTextColor(weekday, isToday: false, isPast: isPast)
        .withValues(alpha: 0.85);
  }

  /// Bakgrund för en dags cell i veckotavlan.
  Color dayCellBg(
    int weekday, {
    required bool isToday,
    required bool isPast,
  }) {
    final p = AppTheme.dayPalette(weekday);
    if (isToday) {
      if (isDark) {
        return Color.alphaBlend(p.base.withValues(alpha: 0.12), card);
      }
      return Color.alphaBlend(p.base.withValues(alpha: 0.09), card);
    }
    if (isDark) {
      final alpha = isPast ? 0.03 : 0.06;
      return Color.alphaBlend(p.base.withValues(alpha: alpha), card);
    } else {
      final alpha = isPast ? 0.03 : 0.05;
      return Color.alphaBlend(p.base.withValues(alpha: alpha), card);
    }
  }

  /// Kant för en dags cell i veckotavlan.
  Border dayCellBorder(int weekday, {required bool isToday}) {
    final p = AppTheme.dayPalette(weekday);
    if (isToday) {
      return Border.all(
        color: p.base,
        width: 2.0,
      );
    }
    return Border.all(
      color: cardBorder,
      width: 1.0,
    );
  }

  // ─── Ramplattor & Aktiviteter ─────────────────────────────────────────────

  /// Bakgrund för ramplatta (personens färg alpha 0.10 i ljust, 0.22 i mörkt).
  Color ramPlateBg(Color memberColor) {
    if (isDark) {
      return Color.alphaBlend(memberColor.withValues(alpha: 0.22), card);
    }
    return memberColor.withValues(alpha: 0.10);
  }

  /// Textfärg för ramplattans innehåll.
  Color ramPlateTextColor() {
    return isDark ? const Color(0xFFE8EAF0) : const Color(0xFF333333);
  }

  /// Accentfärg för pågående post (PÅGÅR).
  Color ongoingAccent({required bool isLowStimuli}) {
    return isLowStimuli ? const Color(0xFFC2654A) : const Color(0xFFE65100);
  }

  // ─── IDAG Kontrast & Textfärg ─────────────────────────────────────────────

  /// Beräknar relativ luminans enligt WCAG 2.1 (sRGB).
  static double relativeLuminance(Color color) {
    double channel(double s) {
      return s <= 0.04045
          ? s / 12.92
          : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// Beräknar kontrastkvot mellan två färger enligt WCAG 2.1.
  static double contrastRatio(Color c1, Color c2) {
    final l1 = relativeLuminance(c1);
    final l2 = relativeLuminance(c2);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Hämtar det ljusaste gradientstoppet bland [light, base, deep] för en veckodag.
  static Color lightestGradientStop(int weekday) {
    final p = AppTheme.dayPalette(weekday);
    final stops = [p.light, p.base, p.deep];
    Color lightest = stops.first;
    double maxLum = relativeLuminance(lightest);
    for (int i = 1; i < stops.length; i++) {
      final lum = relativeLuminance(stops[i]);
      if (lum > maxLum) {
        maxLum = lum;
        lightest = stops[i];
      }
    }
    return lightest;
  }

  /// Hämtar det mörkaste gradientstoppet bland [light, base, deep] för en veckodag.
  static Color darkestGradientStop(int weekday) {
    final p = AppTheme.dayPalette(weekday);
    final stops = [p.light, p.base, p.deep];
    Color darkest = stops.first;
    double minLum = relativeLuminance(darkest);
    for (int i = 1; i < stops.length; i++) {
      final lum = relativeLuminance(stops[i]);
      if (lum < minLum) {
        minLum = lum;
        darkest = stops[i];
      }
    }
    return darkest;
  }

  /// Beräknar minsta kontrastkvot för en textfärg mot alla tre gradientstopp (light, base, deep).
  static double minContrastRatioAcrossStops(Color text, int weekday) {
    final p = AppTheme.dayPalette(weekday);
    final stops = [p.light, p.base, p.deep];
    double minRatio = contrastRatio(text, stops.first);
    for (int i = 1; i < stops.length; i++) {
      final cr = contrastRatio(text, stops[i]);
      if (cr < minRatio) minRatio = cr;
    }
    return minRatio;
  }

  /// Beräknar nödvändig scrim-alpha för IDAG-huvudets textblock (FAS 6c.2).
  /// Beräknar nödvändig scrim-alpha för IDAG-huvudets textblock (FAS 6c.2 / 6d.4).
  ///
  /// Beställarens beslut: SAMMA regel alla sju dagar — vit text på scrim-band.
  /// Alpha beräknas per dag (i steg om 0.05 från 0.25) tills vit text klarar >= 4.5:1
  /// mot det ljusaste stoppet (fredag hamnar på 0.45).
  static double idagScrimAlphaFor(int weekday) {
    const white = Colors.white;
    final lightest = lightestGradientStop(weekday);
    for (int a = 25; a <= 100; a += 5) {
      final alpha = a / 100.0;
      final scrimmed =
          Color.alphaBlend(Colors.black.withValues(alpha: alpha), lightest);
      if (contrastRatio(white, scrimmed) >= 4.5) {
        return alpha;
      }
    }
    return 0.45;
  }

  /// Textfärg för IDAG-huvudet per dag (FAS 6c.2 / 6d.4).
  ///
  /// SAMMA regel alla dagar: alltid vit text på scrim-band (beställarens beslut).
  static Color idagTextColorFor(int weekday) {
    return Colors.white;
  }

  /// Hämtar IDAG-textfärg via palett-instans.
  Color idagTextColor(int weekday) => idagTextColorFor(weekday);

  /// Hämtar IDAG scrim-alpha via palett-instans (null om inget scrim behövs).
  double? idagScrimAlpha(int weekday) => idagScrimAlphaFor(weekday);

  /// Hämtar aktiv [DisplayPalette] från widget-trädet.
  static DisplayPalette of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DisplayPaletteScope>();
    return scope?.palette ?? DisplayPalette.light;
  }
}

/// Tillhandahåller [DisplayPalette] reaktivt i widget-trädet.
class DisplayPaletteScope extends InheritedWidget {
  final DisplayPalette palette;

  const DisplayPaletteScope({
    super.key,
    required this.palette,
    required super.child,
  });

  @override
  bool updateShouldNotify(DisplayPaletteScope oldWidget) {
    return oldWidget.palette.isDark != palette.isDark;
  }
}
