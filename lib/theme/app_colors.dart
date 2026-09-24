import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Färgläge för sidorna (Android-appen Vardags `ColorMode`).
///
/// Sparas lokalt som sträng (`colorMode` i SharedPreferences). Okänt eller
/// saknat värde tolkas som [weekday].
enum ColorMode {
  weekday('weekday', 'Veckodagsfärg'),
  neutral('neutral', 'Neutral');

  const ColorMode(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static ColorMode fromStorage(String? value) {
    final v = value?.trim().toLowerCase();
    for (final m in ColorMode.values) {
      if (m.storageValue == v) return m;
    }
    return ColorMode.weekday;
  }
}

/// Kontrast och färgblandning enligt WCAG 2.1 (Androids `ContrastUtils`).
class ContrastUtils {
  ContrastUtils._();

  static const aaNormalText = 4.5;
  static const aaLargeText = 3.0;

  static double luminance(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [fraction] av [foreground] mot [background], som ogenomskinlig färg.
  static Color blend(Color foreground, double fraction, Color background) {
    final f = fraction.clamp(0.0, 1.0);
    return Color.from(
      alpha: 1,
      red: foreground.r * f + background.r * (1 - f),
      green: foreground.g * f + background.g * (1 - f),
      blue: foreground.b * f + background.b * (1 - f),
    );
  }
}

/// Färgroller för en skärm, beräknade centralt (Androids `AppColors`).
///
/// Rollerna skiljer text **på kort** från text **på sidbakgrunden**: i
/// veckodagsläget är sidan stark och korten ljusa, så samma textfärg kan inte
/// fungera på båda.
@immutable
class AppColors {
  final Color pageBackground;
  final Color header;
  final Color cardSurface;
  final Color onCardPrimary;
  final Color onCardSecondary;
  final Color onCardIcon;
  final Color onPage;
  final Color onPageSecondary;
  final Color cardBorder;
  final Color divider;
  final Color accent;
  final Color onAccent;

  const AppColors({
    required this.pageBackground,
    required this.header,
    required this.cardSurface,
    required this.onCardPrimary,
    required this.onCardSecondary,
    required this.onCardIcon,
    required this.onPage,
    required this.onPageSecondary,
    required this.cardBorder,
    required this.divider,
    required this.accent,
    required this.onAccent,
  });

  static const _neutralPage = Color(0xFFF0F0ED);
  static const _neutralCard = Color(0xFFFDFDFC);
  static const _neutralPrimary = Color(0xFF30332F);
  static const _neutralSecondary = Color(0xFF686C66);
  static const _neutralIcon = Color(0xFF555754);
  static const _lowStimuliPage = Color(0xFFF4F6F8);
  static const ink = Color(0xFF1A1A2E);

  /// Sekundär text på tonade kort — klarar WCAG AA på alla sju dagar.
  static const inkSecondary = Color(0xFF5F6368);
  static const _inkOnStrong = Color(0xFF000000);

  /// Kortens andel basfärg i veckodagsläget (ogenomskinlig blandning mot vitt).
  static const cardTintFraction = 0.18;

  /// Lågstimuli vinner alltid, sedan neutralt, sedan veckodag.
  static AppColors compute({
    required ColorMode mode,
    required bool lowStimuli,
    required DayPalette palette,
  }) {
    if (lowStimuli) return _lowStimuli(palette);
    if (mode == ColorMode.neutral) return _neutral();
    return _weekday(palette);
  }

  static AppColors _lowStimuli(DayPalette p) => AppColors(
        pageBackground: _lowStimuliPage,
        header: p.base,
        cardSurface: Colors.white,
        onCardPrimary: ink,
        onCardSecondary: inkSecondary,
        onCardIcon: inkSecondary,
        onPage: ContrastUtils.ratio(p.deep, _lowStimuliPage) >=
                ContrastUtils.aaNormalText
            ? p.deep
            : ink,
        onPageSecondary: inkSecondary,
        cardBorder: Colors.black.withValues(alpha: 0.06),
        divider: const Color(0xFFE0E0E0),
        accent: p.base,
        onAccent: p.onColor,
      );

  static AppColors _neutral() => AppColors(
        pageBackground: _neutralPage,
        header: _neutralPage,
        cardSurface: _neutralCard,
        onCardPrimary: _neutralPrimary,
        onCardSecondary: _neutralSecondary,
        onCardIcon: _neutralIcon,
        onPage: _neutralPrimary,
        onPageSecondary: _neutralSecondary,
        cardBorder: const Color(0x14000000),
        divider: const Color(0x14000000),
        accent: _neutralIcon,
        onAccent: Colors.white,
      );

  static AppColors _weekday(DayPalette p) {
    final page = p.base;
    final onPage = readableOn(page);
    return AppColors(
      pageBackground: page,
      header: page,
      cardSurface: ContrastUtils.blend(page, cardTintFraction, Colors.white),
      onCardPrimary: ink,
      onCardSecondary: inkSecondary,
      onCardIcon: inkSecondary,
      onPage: onPage,
      onPageSecondary: onPage.withValues(alpha: 0.82),
      cardBorder: Colors.black.withValues(alpha: 0.07),
      divider: Colors.black.withValues(alpha: 0.08),
      accent: p.deep,
      onAccent: Colors.white,
    );
  }

  /// Vit eller svart förgrund mot [background], den som mäter bäst.
  static Color readableOn(Color background) =>
      ContrastUtils.ratio(Colors.white, background) >=
              ContrastUtils.ratio(_inkOnStrong, background)
          ? Colors.white
          : _inkOnStrong;

  /// Vald flik i bottennavet: accenten 25 % mot svart.
  Color get navSelected => Color.lerp(accent, Colors.black, 0.25)!;

  /// Header och sida är samma yta ⇒ inga rundade nederhörn på headern.
  bool get headerMergesWithPage => header == pageBackground;
}
