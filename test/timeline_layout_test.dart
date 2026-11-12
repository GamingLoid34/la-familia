import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/timeline_layout.dart';

/// Testerna för computeTimelineLayout (Min dag-tidslinjens proportionella
/// placering + klustring av överlappande poster). Extraherad ur den tidigare
/// privata `_computeLayout` i min_dag_view.dart så den kan enhetstestas direkt
/// — Android portar samma algoritm 1:1 i Fas 7 (MIGRATION_PLAN.md) med
/// motsvarande 24 tester.
void main() {
  DateTime d(int h, int m) => DateTime(2026, 9, 16, h, m);

  group('computeTimelineLayout — geometri (top/height)', () {
    test('En post 09:00–10:00 med startHour 7 ger top=220 (2h*110), height baserad på 60 min', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(10, 0))],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      expect(result, hasLength(1));
      expect(result[0].top, 220.0); // (9-7)*60 = 120 min -> 120/60*110
      expect(result[0].height, closeTo(106.0, 0.001)); // 60/60*110 - 4
    });

    test('Kort post (15 min) klampas till minst 30 min varaktighet i höjdberäkningen', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(9, 15))],
        startHour: 9,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      // durationMin = max(30, 15) = 30 -> height = max(55, 30/60*110-4) = 55
      expect(result[0].height, 55.0);
    });

    test('Höjden har ett golv på 55 px även för en 0-minuters post', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(9, 0))],
        startHour: 9,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      expect(result[0].height, 55.0);
    });

    test('hourHeight-parametern skalar top/height proportionellt', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(8, 0), end: d(9, 0))],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
        hourHeight: 60.0,
      );
      expect(result[0].top, 60.0); // 1h * 60
      expect(result[0].height, closeTo(56.0, 0.001)); // 60/60*60 - 4
    });
  });

  group('computeTimelineLayout — status (isPassed/isOngoing/isNext)', () {
    test('Pågående post: now inom [start, end) -> isOngoing, varken passed eller next', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(10, 0))],
        startHour: 7,
        now: d(9, 30),
        nextUpcomingIndex: null,
        isViewingToday: true,
      );
      expect(result[0].isOngoing, isTrue);
      expect(result[0].isPassed, isFalse);
    });

    test('Passerad post: now == end räknas som passerad (inte ongoing)', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(10, 0))],
        startHour: 7,
        now: d(10, 0),
        nextUpcomingIndex: null,
        isViewingToday: true,
      );
      expect(result[0].isOngoing, isFalse);
      expect(result[0].isPassed, isTrue);
    });

    test('now == start räknas som ongoing (inte passerad, inte framtida)', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(10, 0))],
        startHour: 7,
        now: d(9, 0),
        nextUpcomingIndex: null,
        isViewingToday: true,
      );
      expect(result[0].isOngoing, isTrue);
      expect(result[0].isPassed, isFalse);
    });

    test('isViewingToday=false stänger av isPassed/isOngoing/isNext helt', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(10, 0))],
        startHour: 7,
        now: d(9, 30), // skulle vara "ongoing" om isViewingToday vore true
        nextUpcomingIndex: 0,
        isViewingToday: false,
      );
      expect(result[0].isOngoing, isFalse);
      expect(result[0].isPassed, isFalse);
      expect(result[0].isNext, isFalse);
    });

    test('nextUpcomingIndex pekar ut exakt en post som isNext', () {
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(9, 30)),
          TimelineSlotInput(start: d(11, 0), end: d(11, 30)),
          TimelineSlotInput(start: d(13, 0), end: d(13, 30)),
        ],
        startHour: 7,
        now: d(10, 0),
        nextUpcomingIndex: 1,
        isViewingToday: true,
      );
      expect(result[0].isNext, isFalse);
      expect(result[1].isNext, isTrue);
      expect(result[2].isNext, isFalse);
    });

    test('nextUpcomingIndex == null ger ingen post markerad som isNext', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(9, 30))],
        startHour: 7,
        now: d(10, 0),
        nextUpcomingIndex: null,
        isViewingToday: true,
      );
      expect(result[0].isNext, isFalse);
    });
  });

  group('computeTimelineLayout — klustring av överlappande poster', () {
    test('Icke-överlappande poster får alla colIndex 0 och totalCols 1', () {
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(9, 30)),
          TimelineSlotInput(start: d(10, 0), end: d(10, 30)),
        ],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      for (final r in result) {
        expect(r.colIndex, 0);
        expect(r.totalCols, 1);
      }
    });

    test('Två helt överlappande poster delar upp i 2 kolumner', () {
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
        ],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      expect(result[0].totalCols, 2);
      expect(result[1].totalCols, 2);
      expect({result[0].colIndex, result[1].colIndex}, {0, 1});
    });

    test('Tre helt överlappande poster delar upp i 3 kolumner (taket)', () {
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
        ],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      for (final r in result) {
        expect(r.totalCols, 3);
      }
      expect(
        result.map((r) => r.colIndex).toSet(),
        {0, 1, 2},
      );
    });

    test('Fyra helt överlappande poster: fjärde delar en kolumn med en tidigare (max 3 kolumner)', () {
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
        ],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      for (final r in result) {
        expect(r.totalCols, 3);
        expect(r.colIndex, inInclusiveRange(0, 2));
      }
    });

    test('En post som slutar precis när nästa börjar räknas INTE som överlappande', () {
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(10, 0), end: d(11, 0)),
        ],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      expect(result[0].totalCols, 1);
      expect(result[1].totalCols, 1);
      expect(result[0].colIndex, 0);
      expect(result[1].colIndex, 0);
    });

    test('Kedjeöverlapp (A-B överlappar, B-C överlappar, A-C inte) klustras ihop som en grupp', () {
      // A: 09:00-10:00, B: 09:30-10:30 (överlappar A), C: 10:15-11:00 (överlappar B, inte A)
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 30), end: d(10, 30)),
          TimelineSlotInput(start: d(10, 15), end: d(11, 0)),
        ],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      // Hela kedjan behandlas som ETT kluster -> alla tre får samma totalCols,
      // och ingen kolumn återanvänds innan den faktiskt är ledig.
      expect(result[0].totalCols, result[1].totalCols);
      expect(result[1].totalCols, result[2].totalCols);
      expect(result[0].colIndex, isNot(result[1].colIndex));
    });

    test('Två separata kluster (ingen överlappning mellan grupperna) räknas oberoende', () {
      final result = computeTimelineLayout(
        [
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(9, 0), end: d(10, 0)),
          TimelineSlotInput(start: d(14, 0), end: d(15, 0)),
        ],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      expect(result[0].totalCols, 2);
      expect(result[1].totalCols, 2);
      expect(result[2].totalCols, 1);
      expect(result[2].colIndex, 0);
    });
  });

  group('computeTimelineLayout — gränsfall', () {
    test('Tom lista ger tom lista utan fel', () {
      final result = computeTimelineLayout(
        const [],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: true,
      );
      expect(result, isEmpty);
    });

    test('En ensam post placeras korrekt utan klustring', () {
      final result = computeTimelineLayout(
        [TimelineSlotInput(start: d(9, 0), end: d(9, 30))],
        startHour: 7,
        now: d(12, 0),
        nextUpcomingIndex: null,
        isViewingToday: false,
      );
      expect(result, hasLength(1));
      expect(result[0].colIndex, 0);
      expect(result[0].totalCols, 1);
    });
  });
}
