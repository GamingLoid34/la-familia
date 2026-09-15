import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/app_theme.dart';
import 'package:la_familia/screens/display/display_palette.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';

double _relativeLuminance(Color color) {
  double channel(double s) {
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

Color _composite(Color fg, Color bg) {
  final alpha = fg.a;
  final r = (fg.r * alpha + bg.r * (1 - alpha)).clamp(0.0, 1.0);
  final g = (fg.g * alpha + bg.g * (1 - alpha)).clamp(0.0, 1.0);
  final b = (fg.b * alpha + bg.b * (1 - alpha)).clamp(0.0, 1.0);
  return Color.fromRGBO(
    (r * 255).round(),
    (g * 255).round(),
    (b * 255).round(),
    1.0,
  );
}

void main() {
  group('DisplayThemeConfig - Tema och tidsintervall', () {
    test('mode light ger alltid ljust tema oavsett klockslag', () {
      const cfg = DisplayThemeConfig(
        mode: 'light',
        darkFrom: '18:00',
        darkTo: '07:00',
      );
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 22, 0)), isFalse);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 3, 0)), isFalse);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 12, 0)), isFalse);
      expect(cfg.resolveEffectiveMode(DateTime(2026, 9, 10, 22, 0)), 'light');
    });

    test('mode dark ger alltid mörkt tema oavsett klockslag', () {
      const cfg = DisplayThemeConfig(
        mode: 'dark',
        darkFrom: '18:00',
        darkTo: '07:00',
      );
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 12, 0)), isTrue);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 22, 0)), isTrue);
      expect(cfg.resolveEffectiveMode(DateTime(2026, 9, 10, 12, 0)), 'dark');
    });

    test('mode auto med midnattsvändning (18:00 till 07:00)', () {
      const cfg = DisplayThemeConfig(
        mode: 'auto',
        darkFrom: '18:00',
        darkTo: '07:00',
      );

      // 18:00 är mörkt (start inkluderas)
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 18, 0)), isTrue);
      expect(cfg.resolveEffectiveMode(DateTime(2026, 9, 10, 18, 0)), 'dark');

      // 23:30 är mörkt
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 23, 30)), isTrue);

      // Midnatt 00:00 är mörkt
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 0, 0)), isTrue);

      // 06:59 är mörkt
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 6, 59)), isTrue);

      // 07:00 är ljust (slutpunkten återgår till ljust)
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 7, 0)), isFalse);
      expect(cfg.resolveEffectiveMode(DateTime(2026, 9, 10, 7, 0)), 'light');

      // 12:00 är ljust
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 12, 0)), isFalse);

      // 17:59 är ljust
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 17, 59)), isFalse);
    });

    test('mode auto utan midnattsvändning (08:00 till 16:00)', () {
      const cfg = DisplayThemeConfig(
        mode: 'auto',
        darkFrom: '08:00',
        darkTo: '16:00',
      );

      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 7, 59)), isFalse);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 8, 0)), isTrue);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 12, 0)), isTrue);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 16, 0)), isFalse);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 20, 0)), isFalse);
    });

    test('mode auto med samma start och slut (18:00 till 18:00)', () {
      const cfg = DisplayThemeConfig(
        mode: 'auto',
        darkFrom: '18:00',
        darkTo: '18:00',
      );
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 18, 0)), isFalse);
      expect(cfg.resolveIsDark(DateTime(2026, 9, 10, 12, 0)), isFalse);
    });
  });

  group('FAS 6c — WCAG AA Kontrastkvoter (>= 4.5:1 för alla 10 par)', () {
    const light = DisplayPalette.light;
    const dark = DisplayPalette.dark;

    test('Par 1: Primärtext / kort (Ljust: #1A1A2E / #FFFFFF)', () {
      final ratio = _contrastRatio(light.textPrimary, light.card);
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(ratio, closeTo(17.06, 0.1));
    });

    test('Par 2: Primärtext / kort (Mörkt: #E8EAF0 / #1A1F2A)', () {
      final ratio = _contrastRatio(dark.textPrimary, dark.card);
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(ratio, closeTo(13.71, 0.1));
    });

    test('Par 3: Dämpad text / kort (Ljust: #5C6877 / #FFFFFF)', () {
      final ratio = _contrastRatio(light.textMuted, light.card);
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(ratio, closeTo(5.67, 0.1));
    });

    test('Par 4: Dämpad text / kort (Mörkt: #98A2B3 / #1A1F2A)', () {
      final ratio = _contrastRatio(dark.textMuted, dark.card);
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(ratio, closeTo(6.40, 0.1));
    });

    test('Par 5: Chip-tid / ramplatta (Ljust: #333333 mot ramplatta)', () {
      final text = light.ramPlateTextColor();
      for (final hex in AppTheme.memberColorPalette) {
        final memberColor = AppTheme.colorFromHex(hex);
        final plateBg = light.ramPlateBg(memberColor);
        final effectiveBg = _composite(plateBg, light.background);
        final ratio = _contrastRatio(text, effectiveBg);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'Misslyckades för medlemsfärg $hex i ljust tema',
        );
      }
    });

    test('Par 6: Chip-tid / ramplatta (Mörkt: #E8EAF0 mot ramplatta)', () {
      final text = dark.ramPlateTextColor();
      for (final hex in AppTheme.memberColorPalette) {
        final memberColor = AppTheme.colorFromHex(hex);
        final plateBg = dark.ramPlateBg(memberColor);
        final ratio = _contrastRatio(text, plateBg);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'Misslyckades för medlemsfärg $hex i mörkt tema',
        );
      }
    });

    test('Par 7: Dagshuvudtext / tint kommande (båda teman, alla 7 dagar)', () {
      for (int wd = 1; wd <= 7; wd++) {
        // Ljust
        final lightBg = light.dayHeaderBg(wd, isToday: false, isPast: false);
        final effectiveLightBg = _composite(lightBg, light.background);
        final lightText = light.dayHeaderTextColor(wd);
        final lightRatio = _contrastRatio(lightText, effectiveLightBg);
        expect(
          lightRatio,
          greaterThanOrEqualTo(4.5),
          reason:
              'Ljust tema vardag $wd misslyckades kontrastkrav (fick $lightRatio:1)',
        );

        // Mörkt
        final darkBg = dark.dayHeaderBg(wd, isToday: false, isPast: false);
        final effectiveDarkBg = _composite(darkBg, dark.background);
        final darkText = dark.dayHeaderTextColor(wd);
        final darkRatio = _contrastRatio(darkText, effectiveDarkBg);
        expect(
          darkRatio,
          greaterThanOrEqualTo(4.5),
          reason:
              'Mörkt tema vardag $wd misslyckades kontrastkrav (fick $darkRatio:1)',
        );
      }
    });

    test('Par 8: Dagshuvudtext / tint passerad (båda teman, alla 7 dagar)', () {
      for (int wd = 1; wd <= 7; wd++) {
        // Ljust
        final lightBg = light.dayHeaderBg(wd, isToday: false, isPast: true);
        final effectiveLightBg = _composite(lightBg, light.background);
        final lightText = light.dayHeaderTextColor(wd);
        final lightRatio = _contrastRatio(lightText, effectiveLightBg);
        expect(
          lightRatio,
          greaterThanOrEqualTo(4.5),
          reason:
              'Ljust tema passerad vardag $wd misslyckades (fick $lightRatio:1)',
        );

        // Mörkt
        final darkBg = dark.dayHeaderBg(wd, isToday: false, isPast: true);
        final effectiveDarkBg = _composite(darkBg, dark.background);
        final darkText = dark.dayHeaderTextColor(wd);
        final darkRatio = _contrastRatio(darkText, effectiveDarkBg);
        expect(
          darkRatio,
          greaterThanOrEqualTo(4.5),
          reason:
              'Mörkt tema passerad vardag $wd misslyckades (fick $darkRatio:1)',
        );
      }
    });

    test('Par 9: IDAG-text / gradientstopp och scrim (alla 7 dagar)', () {
      for (int wd = 1; wd <= 7; wd++) {
        final text = DisplayPalette.idagTextColorFor(wd);
        final scrim = DisplayPalette.idagScrimAlphaFor(wd);
        final p = AppTheme.dayPalette(wd);
        final stops = [p.light, p.base, p.deep];

        for (final stop in stops) {
          final effectiveBg = Color.alphaBlend(
            Colors.black.withValues(alpha: scrim),
            stop,
          );
          final ratio = _contrastRatio(text, effectiveBg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'IDAG-kontrast vardag $wd misslyckades mot stopp $stop (fick $ratio:1)',
          );
        }
      }
    });

    test('Par 10: Footertext / kort (båda teman)', () {
      final lightRatio = _contrastRatio(light.textPrimary, light.card);
      expect(lightRatio, greaterThanOrEqualTo(4.5));

      final darkRatio = _contrastRatio(dark.textPrimary, dark.card);
      expect(darkRatio, greaterThanOrEqualTo(4.5));
    });
  });

  group('FAS 6c.2 — IDAG-huvud: Symmetrisk kontrastregel & Scrim-band', () {
    test(
      'Mäter min-kvoten och verifierar vit text med scrim för alla sju dagar',
      () {
        const white = Colors.white;

        for (int wd = 1; wd <= 7; wd++) {
          expect(DisplayPalette.idagTextColorFor(wd), equals(white));

          final alpha = DisplayPalette.idagScrimAlphaFor(wd);
          // Verifiera att scrim-alphat höjer kontrasten mot ljusaste stoppet till >= 4.5:1
          final lightest = DisplayPalette.lightestGradientStop(wd);
          final scrimmed = Color.alphaBlend(
            Colors.black.withValues(alpha: alpha),
            lightest,
          );
          expect(_contrastRatio(white, scrimmed), greaterThanOrEqualTo(4.5));
        }
      },
    );

    test(
      'Exakta scrim-alpha värden per veckodag (alla 7 dagar vit text på scrim)',
      () {
        expect(DisplayPalette.idagScrimAlphaFor(1), equals(0.35)); // Mån
        expect(DisplayPalette.idagScrimAlphaFor(2), equals(0.30)); // Tis
        expect(DisplayPalette.idagScrimAlphaFor(3), equals(0.40)); // Ons
        expect(DisplayPalette.idagScrimAlphaFor(4), equals(0.25)); // Tor
        expect(DisplayPalette.idagScrimAlphaFor(5), equals(0.45)); // Fre
        expect(DisplayPalette.idagScrimAlphaFor(6), equals(0.35)); // Lör
        expect(DisplayPalette.idagScrimAlphaFor(7), equals(0.25)); // Sön
      },
    );

    test(
      'Ljusaste och mörkaste gradientstopp identifieras korrekt för alla 7 veckodagar',
      () {
        for (int wd = 1; wd <= 7; wd++) {
          final p = AppTheme.dayPalette(wd);
          expect(DisplayPalette.lightestGradientStop(wd), equals(p.light));
          expect(DisplayPalette.darkestGradientStop(wd), equals(p.deep));
        }
      },
    );

    test(
      'dayHeaderTextColor returnerar idagTextColorFor när isToday är true',
      () {
        for (int wd = 1; wd <= 7; wd++) {
          expect(
            DisplayPalette.light.dayHeaderTextColor(wd, isToday: true),
            equals(DisplayPalette.idagTextColorFor(wd)),
          );
          expect(
            DisplayPalette.dark.dayHeaderTextColor(wd, isToday: true),
            equals(DisplayPalette.idagTextColorFor(wd)),
          );
        }
      },
    );

    test(
      'idagHeaderBoxShadow är aktiv i standardläge och stängs av i lågstimuli för alla 7 dagar',
      () {
        for (int wd = 1; wd <= 7; wd++) {
          // Lågstimuli = false -> skugga finns
          final shadows = DisplayPalette.light.idagHeaderBoxShadow(
            wd,
            isLowStimuli: false,
          );
          expect(shadows, isNotNull);
          expect(shadows!.length, 1);
          expect(
            shadows.first.color,
            AppTheme.dayPalette(wd).base.withValues(alpha: 0.25),
          );
          expect(shadows.first.blurRadius, 6);

          // Lågstimuli = true -> ingen skugga (null)
          final noShadows = DisplayPalette.light.idagHeaderBoxShadow(
            wd,
            isLowStimuli: true,
          );
          expect(noShadows, isNull);
        }
      },
    );
  });
}
