import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/screens/display/display_school_menu_data.dart';
import 'package:la_familia/screens/display/modules/persondag_schema.dart';
import 'package:la_familia/widgets/member_avatar.dart';

void main() {
  group('FAS 6d — Skolschema: Raster och lunchlucka', () {
    test('1. Inga raster skapas när gap < 10 minuter', () {
      final lessons = [
        const LessonTimelineItem(
          title: 'Svenska',
          startHm: '08:00',
          endHm: '08:45',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 480,
          endMinutes: 525,
        ),
        const LessonTimelineItem(
          title: 'Matematik',
          startHm: '08:50',
          endHm: '09:35',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 530,
          endMinutes: 575,
        ),
      ];

      final entries = buildTimelineEntries(sortedLessons: lessons, lunchInfo: null);
      expect(entries.length, 2);
      expect(entries.whereType<BreakEntryWrapper>().isEmpty, true);
    });

    test('2. Rast skapas vid gap >= 10 minuter utanför lunchfönstret', () {
      final lessons = [
        const LessonTimelineItem(
          title: 'Svenska',
          startHm: '08:00',
          endHm: '08:45',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 480,
          endMinutes: 525,
        ),
        const LessonTimelineItem(
          title: 'Matematik',
          startHm: '09:00',
          endHm: '09:45',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 540,
          endMinutes: 585,
        ),
      ];

      final entries = buildTimelineEntries(sortedLessons: lessons, lunchInfo: null);
      expect(entries.length, 3);
      final breakEntry = entries.whereType<BreakEntryWrapper>().first;
      expect(breakEntry.item.isLunch, false);
      expect(breakEntry.item.label, 'Rast');
      expect(breakEntry.item.durationMinutes, 15);
    });

    test('3. Största luckan mellan 10:30 och 13:30 identifieras som Lunch', () {
      final lessons = [
        // Lektion 1 slutar 09:45 (gap = 15 min -> 10:00, Rast)
        const LessonTimelineItem(
          title: 'Svenska',
          startHm: '09:00',
          endHm: '09:45',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 540,
          endMinutes: 585,
        ),
        // Lektion 2: 10:00–11:00 (gap till 12:00 = 60 min, inom 10:30–13:30 -> Lunch!)
        const LessonTimelineItem(
          title: 'Matematik',
          startHm: '10:00',
          endHm: '11:00',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 600,
          endMinutes: 660,
        ),
        // Lektion 3: 12:00–12:45 (gap till 13:00 = 15 min, Rast)
        const LessonTimelineItem(
          title: 'NO',
          startHm: '12:00',
          endHm: '12:45',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 720,
          endMinutes: 765,
        ),
        // Lektion 4: 13:00–14:00
        const LessonTimelineItem(
          title: 'Idrott',
          startHm: '13:00',
          endHm: '14:00',
          piktogram: '🎒',
          schemaLabel: 'Skola',
          startMinutes: 780,
          endMinutes: 840,
        ),
      ];

      const lunchInfo = LunchInfo(
        schoolName: 'Junkaremålsskolan',
        lunch: 'Nötkebab med ris',
        vegetarian: 'Falafel med ris',
      );

      final lunchIdx = identifyLunchGapIndex(lessons);
      expect(lunchIdx, 1); // Efter lektion index 1 (Matematik)

      final entries = buildTimelineEntries(sortedLessons: lessons, lunchInfo: lunchInfo);
      final breaks = entries.whereType<BreakEntryWrapper>().toList();
      expect(breaks.length, 3);

      expect(breaks[0].item.isLunch, false);
      expect(breaks[0].item.label, 'Rast');

      expect(breaks[1].item.isLunch, true);
      expect(breaks[1].item.label, 'Lunch');
      expect(breaks[1].item.lunchText, 'Nötkebab med ris');
      expect(breaks[1].item.vegText, 'Falafel med ris');

      expect(breaks[2].item.isLunch, false);
      expect(breaks[2].item.label, 'Rast');
    });
  });

  group('FAS 6d — Skolschema: Höjdbudget och kompakt fallback', () {
    test('1. Fallback triggas när sum(min_i) > H (inte av fast >8-tröskel)', () {
      // 9 lektioner, 2 raster, lunch -> sum(min) = 9*64 + 2*24 + 56 = 680 px
      // Vid availableHeight 500 px (H = 440 px) -> sum(min) > H -> fallback triggas
      final fallbackLowH = shouldUseCompactFallback(
        lessonCount: 9,
        breakCount: 2,
        hasLunch: true,
        availableHeight: 500.0,
      );
      expect(fallbackLowH, true);

      // Vid availableHeight 800 px (H = 740 px) -> sum(min) <= H -> tidslinje renderas (>8-tröskel borttagen)
      final fallbackHighH = shouldUseCompactFallback(
        lessonCount: 9,
        breakCount: 2,
        hasLunch: true,
        availableHeight: 800.0,
      );
      expect(fallbackHighH, false);
    });

    test('2. Fallback triggas när höjden är för liten för proportionell rendering', () {
      final shouldFallback = shouldUseCompactFallback(
        lessonCount: 5,
        breakCount: 3,
        hasLunch: true,
        availableHeight: 150.0, // sum(min) = 5*64 + 3*24 + 56 = 448 px > 90 px
      );
      expect(shouldFallback, true);
    });

    test('3. Proportionell rendering används vid normal lektionsmängd och god höjd', () {
      final shouldFallback = shouldUseCompactFallback(
        lessonCount: 4,
        breakCount: 2,
        hasLunch: true,
        availableHeight: 600.0, // sum(min) = 4*64 + 2*24 + 56 = 360 px <= 540 px
      );
      expect(shouldFallback, false);
    });
  });

  group('FAS 6d — Skolschema: Nu-linjens proportionella position', () {
    test('1. Nu-linje returnerar null utanför skoldagens spann', () {
      // Skoldag 08:00 (480) - 14:00 (840)
      expect(computeNuLineFraction(nowMinutes: 479, dayStartMinutes: 480, dayEndMinutes: 840), isNull);
      expect(computeNuLineFraction(nowMinutes: 841, dayStartMinutes: 480, dayEndMinutes: 840), isNull);
    });

    test('2. Nu-linje beräknar exakt bråkdel vid aktuell tid', () {
      // Skoldag 08:00 (480) - 12:00 (720), total = 240 min
      // Kl 10:00 (600 min) -> 120 / 240 = 0.5 (50%)
      final fraction10 = computeNuLineFraction(nowMinutes: 600, dayStartMinutes: 480, dayEndMinutes: 720);
      expect(fraction10, closeTo(0.5, 0.001));

      // Testtid ändras till 10:05 (605 min) -> 125 / 240 = 0.520833
      final fraction1005 = computeNuLineFraction(nowMinutes: 605, dayStartMinutes: 480, dayEndMinutes: 720);
      expect(fraction1005, closeTo(125 / 240, 0.001));
    });
  });

  group('FAS 6d — Salladsfiltret (Beslut 5)', () {
    test('1. cleanDishTitle filtrerar bort ren salladsbuffé', () {
      expect(cleanDishTitle('Salladsbuffé'), '');
      expect(cleanDishTitle('sallad'), '');
      expect(cleanDishTitle('Buffé'), '');
      expect(cleanDishTitle('Alltid på buffén, soppa samt sallad efter säsong'), '');
    });

    test('2. cleanDishTitle rensar salladsbuffé ur sammansatta rätter', () {
      expect(cleanDishTitle('Nötkebab · Salladsbuffé'), 'Nötkebab');
      expect(cleanDishTitle('Dagens 1: Nötkebab · Alltid på buffén'), 'Nötkebab');
    });

    test('3. Tranås Kebabens Dag: nötkebab / falafel / salladsbuffé -> två rätter, ingen buffé', () {
      const compositeLunch = 'Nötkebab · Falafel · Salladsbuffé efter säsong';
      expect(cleanDishTitle(compositeLunch), 'Nötkebab · Falafel');
    });

    test('4. formatCompactLunch visar första icke-bufférätten', () {
      expect(formatCompactLunch('Nötkebab · Salladsbuffé'), 'Nötkebab');
      expect(formatCompactLunch('Salladsbuffé · Nötkebab'), 'Nötkebab');
      expect(formatCompactLunch('Salladsbuffé efter säsong'), '');
    });
  });

  group('FAS 6d — Fotoavatarer med 2.5px färgring (Beslut 4)', () {
    testWidgets('1. FamilyMemberAvatar ritar 2.5px färgring i standard och lågstimuli', (tester) async {
      final testMember = UserModel(
        uid: 'lionel-123',
        name: 'Lionel Test',
        email: 'lionel@test.com',
        familyId: 'fam-1',
        role: 'child',
        color: '#4CAF50',
        viewMode: 'child',
        energy: 3,
      );

      // 1. Default (showRing: false för mobil) -> ingen ring
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyMemberAvatar(
              member: testMember,
              size: 44,
              borderWidth: 2.5,
            ),
          ),
        ),
      );

      final containerFinderDefault = find.byType(Container).first;
      final containerDefault = tester.widget<Container>(containerFinderDefault);
      final boxDecorationDefault = containerDefault.decoration as BoxDecoration;
      expect(boxDecorationDefault.border, isNull);

      // 2. Explicit showRing: true (för storskärm) -> 2.5px färgring
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyMemberAvatar(
              member: testMember,
              size: 44,
              borderWidth: 2.5,
              showRing: true,
            ),
          ),
        ),
      );

      final containerFinder = find.byType(Container).first;
      final container = tester.widget<Container>(containerFinder);
      final boxDecoration = container.decoration as BoxDecoration;
      final border = boxDecoration.border as Border;

      expect(border.top.width, 2.5);
      expect(border.top.color, const Color(0xFF4CAF50));
    });
  });
}
