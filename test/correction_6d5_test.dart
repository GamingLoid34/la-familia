import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/display_chips.dart';
import 'package:la_familia/screens/display/display_palette.dart';
import 'package:la_familia/screens/display/modules/footer_modules.dart';

/// Korrigering 6d.5: visuell verifiering — inget scrollbart på väggen,
/// FittedBox(scaleDown) endast i de beslutade undantagen, och
/// typografiundantagen (10/11/12/13/14 px) återställda till före build 26.
void main() {
  setUpAll(() async {
    final fontLoader = FontLoader('Nunito');
    for (final path in [
      'assets/fonts/Nunito-Regular.ttf',
      'assets/fonts/Nunito-Bold.ttf',
      'assets/fonts/Nunito-SemiBold.ttf',
      'assets/fonts/Nunito-ExtraBold.ttf',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        fontLoader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
    }
    await fontLoader.load();
  });

  group('6d.5 punkt 1: inget scrollbart på väggen (DisplayRamPlate/DisplayActivityCard)', () {
    testWidgets('Gren a (330 px): ingen SingleChildScrollView/ListView omsluter innehållet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 330,
              child: Column(
                children: [
                  const DisplayRamPlate(
                    piktogram: '📚',
                    label: 'Skola',
                    time: '08:15–16:15',
                    memberColor: Colors.blue,
                  ),
                  DisplayActivityCard(
                    data: const {
                      'piktogram': '📚',
                      'title': 'Heldagsskola',
                      'time': '08:15',
                      'endTime': '16:15',
                    },
                    memberColor: Colors.blue,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Gren c (mycket smal, 90 px): FittedBox(scaleDown) är enda undantaget, ingen scroll, inget overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 90,
              child: Column(
                children: [
                  const DisplayRamPlate(
                    piktogram: '📚',
                    label: 'Mycketlångetikettsomintefårplats',
                    time: '08:15–16:15',
                    memberColor: Colors.blue,
                  ),
                  DisplayActivityCard(
                    data: const {
                      'piktogram': '📚',
                      'title': 'Heldagsskola',
                      'time': '08:15',
                      'endTime': '16:15',
                    },
                    memberColor: Colors.blue,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(FittedBox), findsWidgets);
      // Ingen RenderFlex-overflow eller annat layoutfel
      expect(tester.takeException(), isNull);
    });
  });

  group('6d.5 punkt 2: typografiundantag återställda', () {
    testWidgets('Chip-badge (ej schema) 12 px w800; schema-badge (isLarge) 18 px', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DisplayRamPlate(
                  piktogram: '🏫',
                  label: 'Skola',
                  time: '8:00–15:10',
                  memberColor: Colors.blue,
                  isOngoing: true,
                ),
                DisplayRamPlate(
                  piktogram: '🏫',
                  label: 'Skola',
                  time: '8:00–15:10',
                  memberColor: Colors.blue,
                  isOngoing: true,
                  isLarge: true,
                ),
              ],
            ),
          ),
        ),
      );

      final badgeTexts = tester.widgetList<Text>(find.text('PÅGÅR')).toList();
      expect(badgeTexts.length, 2);
      expect(badgeTexts[0].style?.fontSize, 12);
      expect(badgeTexts[0].style?.fontWeight, FontWeight.w800);
      expect(badgeTexts[1].style?.fontSize, 18);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DisplayFooterCard: footerkicker är 14 px i alla footerkort', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: Column(
                children: const [
                  DisplayFooterCard(
                    iconData: Icons.directions_run,
                    iconColor: Colors.green,
                    title: 'Sysslor',
                    content: '3 kvar idag',
                  ),
                  DisplayFooterCard(
                    iconData: Icons.restaurant,
                    iconColor: Colors.orange,
                    title: 'Middag',
                    content: 'Kebabpytt',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final kickers = tester.widgetList<Text>(find.text('Sysslor')).followedBy(tester.widgetList<Text>(find.text('Middag'))).toList();
      expect(kickers.length, 2);
      for (final t in kickers) {
        expect(t.style?.fontSize, 14);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('6d.5 punkt 3: visuell verifiering — idag_nu-chip (DisplayActivityCard) med PÅGÅR-badge i 330 px och 200 px', () {
    Widget buildChip() => DisplayActivityCard(
          data: const {
            'piktogram': '🏊',
            'title': 'Simträning',
            'time': '09:00',
            'endTime': '11:00',
          },
          memberColor: Colors.blue,
          isFolded: true,
          isOngoing: true,
          badgeText: 'PÅGÅR',
        );

    testWidgets('330 px: PÅGÅR-badge synlig, ingen scroll-omslutning, inget overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 330, child: buildChip()),
          ),
        ),
      );

      expect(find.text('PÅGÅR'), findsOneWidget);
      final badge = tester.widget<Text>(find.text('PÅGÅR'));
      expect(badge.style?.fontSize, 12);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('200 px: PÅGÅR-badge fortfarande synlig, inget overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 200, child: buildChip()),
          ),
        ),
      );

      expect(find.text('PÅGÅR'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('6d.5 punkt 3: DisplayPalette-oberoende — footerkort renderar utan fel i mörkt tema', () {
    testWidgets('DisplayFooterCard i mörkt tema, smal bredd', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DisplayPaletteScope(
            palette: DisplayPalette.dark,
            child: const Scaffold(
              body: SizedBox(
                width: 220,
                child: DisplayFooterCard(
                  iconData: Icons.cleaning_services,
                  iconColor: Colors.teal,
                  title: 'Tavlan',
                  content: 'Inga sysslor kvar',
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
