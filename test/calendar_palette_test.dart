import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/app_theme.dart';
import 'package:la_familia/screens/login_page.dart';

double contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
}

void main() {
  test('calendar accent stays neutral across weekdays with readable text', () {
    addTearDown(() => AppTheme.mode.value = ThemeMode.system);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      AppTheme.mode.value = mode;
      final expected = AppTheme.calendarPalette(1);
      for (var day = 1; day <= 7; day++) {
        final palette = AppTheme.calendarPalette(day);
        expect(palette.base, expected.base);
        expect(AppTheme.getDayAccentColor(day), expected.base);
        for (final background in [palette.light, palette.base, palette.deep]) {
          expect(
            contrast(palette.onColor, background),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(
        contrast(AppTheme.getTextColor(), AppTheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppTheme.getSubTextColor(), AppTheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
    // TV scenes retain their established palette and their own contrast rules.
    expect(AppTheme.dayPalette(1).base, isNot(AppTheme.dayPalette(5).base));
  });

  test(
    'appearance preference can be stored and follows the device by default',
    () {
      for (final mode in ThemeMode.values) {
        expect(AppTheme.modeFromStorage(AppTheme.modeToStorage(mode)), mode);
      }
      expect(AppTheme.modeFromStorage(null), ThemeMode.system);
      expect(AppTheme.modeFromStorage('unrecognised'), ThemeMode.system);
    },
  );

  testWidgets('sign-in uses Vardag branding on a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    expect(find.text('Logga in'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/vardag_logo.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark sign-in uses a readable dark surface and light logo', (
    tester,
  ) async {
    AppTheme.mode.value = ThemeMode.dark;
    addTearDown(() => AppTheme.mode.value = ThemeMode.system);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.materialTheme(Brightness.light),
        darkTheme: AppTheme.materialTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const LoginPage(),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.color, const Color(0xFFA4CBE0));
    final card = tester.widget<Container>(
      find
          .byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == AppTheme.surface,
          )
          .first,
    );
    expect((card.decoration as BoxDecoration).color, const Color(0xFF202427));
    expect(find.text('Logga in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
