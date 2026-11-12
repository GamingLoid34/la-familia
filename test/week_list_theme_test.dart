import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/app_theme.dart';
import 'package:la_familia/widgets/week_list.dart';

void main() {
  testWidgets('veckans rubriker går att läsa i både mörkt och ljust läge', (
    tester,
  ) async {
    await initializeDateFormatting('sv');
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      AppTheme.mode.value = mode;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.materialTheme(
            mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            body: WeekList(
              members: const [],
              events: const [],
              weekStart: DateTime(2020, 10, 5),
            ),
          ),
        ),
      );
      await tester.pump();
      final label = find.textContaining('Måndag 5 okt');
      expect(label, findsOneWidget);
      final ink = tester.widget<Text>(label).style!.color!;
      final ancestor = find.ancestor(
        of: label,
        matching: find.byType(Material),
      );
      final background = tester.widgetList<Material>(ancestor).first.color!;
      final l1 = ink.computeLuminance();
      final l2 = background.computeLuminance();
      final contrast =
          (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    }
    AppTheme.mode.value = ThemeMode.system;
  });
}
