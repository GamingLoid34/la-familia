import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/display_chips.dart';
import 'package:la_familia/screens/display/display_theme.dart';
import 'package:la_familia/utils/day_events.dart';
import 'package:la_familia/utils/schedule_time_utils.dart';

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

  group('FAS 5.6 — Adaptiv densitet och tvåradiga aktivitetskort vid 330 px, 200 px och 135 px', () {
    testWidgets('330 px (a): "piktogram · etikett · tid" i full storlek får plats -> visa allt', (tester) async {
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

      // DisplayRamPlate visar etikett och tid
      expect(find.text('Skola'), findsOneWidget);
      expect(find.text(' · 08:15–16:15'), findsOneWidget);

      // DisplayActivityCard visar både tid och titel
      expect(find.text('Heldagsskola'), findsOneWidget);
      expect(find.text('08:15–16:15'), findsOneWidget);
    });

    testWidgets('200 px: (a) aktivitetskort -> två rader, titel synlig med ellips, tid >= 18 px. (b) ramplatta -> "📚 · 08:15–16:15" utan etikett', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
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

      // RamPlate: etiketten 'Skola' är släppt enligt trestegsregeln (b)
      expect(find.text('Skola'), findsNothing);

      // RamPlate visar "📚", " · " och "08:15–16:15" i full storlek (>= 18 px)
      expect(find.text(' · '), findsOneWidget);
      final ramTimeText = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.data == '08:15–16:15' && w.style?.color == const Color(0xFF333333),
      ));
      expect(ramTimeText.style?.fontSize, DisplayTheme.ramTextFontSize);
      expect(ramTimeText.style?.fontSize, greaterThanOrEqualTo(18.0));

      // ActivityCard: titeln släpps ALDRIG — två rader, titel synlig med ellips
      expect(find.text('Heldagsskola'), findsOneWidget);
      final cardTitleText = tester.widget<Text>(find.text('Heldagsskola'));
      expect(cardTitleText.maxLines, 1);
      expect(cardTitleText.overflow, TextOverflow.ellipsis);

      // ActivityCard: tid i full storlek (>= 18 px)
      final cardTimeText = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.data == '08:15–16:15' && w.style?.color == const Color(0xFF1A1A2E),
      ));
      expect(cardTimeText.style?.fontSize, greaterThanOrEqualTo(18.0));
      expect(cardTimeText.style?.fontWeight, FontWeight.w800);

      // Båda renderar 08:15–16:15 och piktogram
      expect(find.text('08:15–16:15'), findsNWidgets(2));
      expect(find.text('📚'), findsNWidgets(2));
    });

    testWidgets('135 px (b/c): ramplatta släpper etikett, aktivitetskort behåller två rader och titel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 135,
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

      // RamPlate släpper etiketten
      expect(find.text('Skola'), findsNothing);
      // ActivityCard behåller titeln även i smal kolumn
      expect(find.text('Heldagsskola'), findsOneWidget);
      expect(find.text('08:15–16:15'), findsNWidgets(2));
    });
  });

  group('FAS 5.6 — Lågstimuli: PÅGÅR-accent och badge följer dämpning', () {
    testWidgets('DisplayRamPlate i standardläge har mättad orange #E65100, i lågstimuli dämpad terracotta #C2654A', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 250,
              child: Column(
                children: [
                  DisplayRamPlate(
                    piktogram: '🏫',
                    label: 'Skola',
                    time: '8:00–15:10',
                    memberColor: Colors.blue,
                    isOngoing: true,
                    isLowStimuli: false,
                  ),
                  DisplayRamPlate(
                    piktogram: '🏫',
                    label: 'Skola',
                    time: '8:00–15:10',
                    memberColor: Colors.blue,
                    isOngoing: true,
                    isLowStimuli: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final containers = tester.widgetList<Container>(find.byType(Container)).toList();
      // Första plattan: standard mättad #E65100
      final dec1 = containers.firstWhere((c) =>
          c.decoration is BoxDecoration &&
          (c.decoration as BoxDecoration).border != null &&
          ((c.decoration as BoxDecoration).border as Border).top.color == const Color(0xFFE65100)).decoration as BoxDecoration;
      expect((dec1.border as Border).top.color, const Color(0xFFE65100));

      // Andra plattan: lågstimuli dämpad #C2654A
      final dec2 = containers.firstWhere((c) =>
          c.decoration is BoxDecoration &&
          (c.decoration as BoxDecoration).border != null &&
          ((c.decoration as BoxDecoration).border as Border).top.color == const Color(0xFFC2654A)).decoration as BoxDecoration;
      expect((dec2.border as Border).top.color, const Color(0xFFC2654A));

      // Badgetexterna för PÅGÅR
      final badgeTexts = tester.widgetList<Text>(find.text('PÅGÅR')).toList();
      expect(badgeTexts.length, 2);
      expect(badgeTexts[0].style?.color, const Color(0xFFE65100));
      expect(badgeTexts[1].style?.color, const Color(0xFFC2654A));
    });

    testWidgets('DisplayActivityCard i lågstimuli har dämpad terracotta #C2654A på vänsterkant och badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 250,
              child: Column(
                children: [
                  DisplayActivityCard(
                    data: const {
                      'piktogram': '⚽',
                      'title': 'Fotbollsträning',
                      'time': '17:00',
                      'endTime': '18:15',
                    },
                    memberColor: Colors.blue,
                    isOngoing: true,
                    isLowStimuli: false,
                    badgeText: 'PÅGÅR',
                  ),
                  DisplayActivityCard(
                    data: const {
                      'piktogram': '⚽',
                      'title': 'Fotbollsträning',
                      'time': '17:00',
                      'endTime': '18:15',
                    },
                    memberColor: Colors.blue,
                    isOngoing: true,
                    isLowStimuli: true,
                    badgeText: 'PÅGÅR',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Verifiera badge-texter
      final badgeTexts = tester.widgetList<Text>(find.text('PÅGÅR')).toList();
      expect(badgeTexts.length, 2);
      expect(badgeTexts[0].style?.color, const Color(0xFFE65100));
      expect(badgeTexts[1].style?.color, const Color(0xFFC2654A));
    });
  });

  group('FAS 5.5 — PÅGÅR-markering (Pin-test)', () {
    testWidgets('DisplayRamPlate med isOngoing: true renderar accentram och PÅGÅR', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 250,
              child: DisplayRamPlate(
                piktogram: '🏫',
                label: 'Skola',
                time: '8:00–15:10',
                memberColor: Colors.blue,
                isOngoing: true,
              ),
            ),
          ),
        ),
      );

      // PÅGÅR-badge ska synas
      expect(find.text('PÅGÅR'), findsOneWidget);

      // Accentram ska finnas på containern
      final container = tester.widget<Container>(find.byType(Container).first);
      final boxDec = container.decoration as BoxDecoration;
      expect(boxDec.border, isNotNull);
      expect((boxDec.border as Border).top.color, const Color(0xFFE65100));
    });

    test('Pin-test 2: now 14:38, skola 8:00–15:10 är pågående (isOngoing)', () {
      final now = DateTime(2026, 9, 10, 14, 38);
      final start = parseHmOnDate('08:00', now);
      final end = parseHmOnDate('15:10', now);

      final isOngoing = start != null &&
          end != null &&
          !now.isBefore(start) &&
          now.isBefore(end);

      expect(isOngoing, isTrue);
    });
  });

  group('FAS 5.5 — "om X"-badge på nästa aktivitet (Pin-test)', () {
    test('Pin-test 3: now 14:38, aktivitet 17:00 -> "om 2 timmar"', () {
      final now = DateTime(2026, 9, 10, 14, 38);
      final eventStart = DateTime(2026, 9, 10, 17, 0);

      final diffMinutes = eventStart.difference(now).inMinutes;
      expect(diffMinutes, 142);

      final countdown = formatCountdownMinutes(diffMinutes);
      expect(countdown, 'om 2 timmar');
    });

    testWidgets('DisplayActivityCard renderar "om 2 timmar"-badge på nästa aktivitet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: Column(
                children: [
                  DisplayActivityCard(
                    data: const {
                      'piktogram': '⚽',
                      'title': 'Fotbollsträning',
                      'time': '17:00',
                      'endTime': '18:15',
                    },
                    memberColor: Colors.blue,
                    badgeText: 'om 2 timmar',
                  ),
                  DisplayActivityCard(
                    data: const {
                      'piktogram': '🎸',
                      'title': 'Gitarrlektion',
                      'time': '19:00',
                      'endTime': '20:00',
                    },
                    memberColor: Colors.blue,
                    badgeText: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Endast första kortet ska visa "om 2 timmar"
      expect(find.text('om 2 timmar'), findsOneWidget);
      expect(find.text('Fotbollsträning'), findsOneWidget);
      expect(find.text('Gitarrlektion'), findsOneWidget);
    });
  });
}
