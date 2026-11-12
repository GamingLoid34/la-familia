import 'dart:math';

/// Tidsfönster som ska placeras på Min dag-tidslinjen (start/slut, inget
/// annat) — den enda indatan klusteralgoritmen behöver.
class TimelineSlotInput {
  final DateTime start;
  final DateTime end;

  const TimelineSlotInput({required this.start, required this.end});
}

/// Beräknad geometri + status för ett tidsfönster på tidslinjen.
/// [colIndex]/[totalCols] sätts av klusterberäkningen i ett andra pass.
class TimelineSlotLayout {
  final double top;
  final double height;
  final bool isPassed;
  final bool isOngoing;
  final bool isNext;
  int colIndex;
  int totalCols;

  TimelineSlotLayout({
    required this.top,
    required this.height,
    required this.isPassed,
    required this.isOngoing,
    required this.isNext,
    this.colIndex = 0,
    this.totalCols = 1,
  });
}

/// Placerar tidslinjeposter proportionellt (Min dag) och klustrar
/// överlappande poster i max 3 kolumner.
///
/// Ren logik utan Flutter-/Firestore-beroenden — porta 1:1 till Kotlin i
/// Android-appen (Fas 7 i MIGRATION_PLAN.md) med samma testfall.
///
/// [items] måste redan vara kronologiskt sorterade på [TimelineSlotInput.start]
/// — funktionen sorterar inte om dem.
/// [startHour] är tidslinjens första hel-timme (axelns topp = 0).
/// [nextUpcomingIndex] är index i [items] för nästa kommande post idag,
/// eller null om ingen (bara relevant när [isViewingToday]).
/// [hourHeight] är pixelhöjd per timme (Min dag använder 110.0).
List<TimelineSlotLayout> computeTimelineLayout(
  List<TimelineSlotInput> items, {
  required int startHour,
  required DateTime now,
  required int? nextUpcomingIndex,
  required bool isViewingToday,
  double hourHeight = 110.0,
}) {
  final list = <TimelineSlotLayout>[];

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final startMin = (item.start.hour - startHour) * 60 + item.start.minute;
    final endMin = (item.end.hour - startHour) * 60 + item.end.minute;
    final durationMin = max(30, endMin - startMin);

    final top = (startMin / 60.0) * hourHeight;
    final height = max(55.0, (durationMin / 60.0) * hourHeight - 4.0);

    final isOngoing = isViewingToday &&
        !now.isBefore(item.start) &&
        now.isBefore(item.end);
    final isPassed = isViewingToday && !now.isBefore(item.end);
    final isNext = isViewingToday && i == nextUpcomingIndex;

    list.add(TimelineSlotLayout(
      top: top,
      height: height,
      isPassed: isPassed,
      isOngoing: isOngoing,
      isNext: isNext,
    ));
  }

  // Klusterberäkning för överlappande händelser (max 3 kolumner).
  var clusterStart = 0;
  while (clusterStart < list.length) {
    var clusterEnd = clusterStart + 1;
    var clusterMaxBottom = list[clusterStart].top + list[clusterStart].height;

    while (clusterEnd < list.length &&
        list[clusterEnd].top < clusterMaxBottom) {
      clusterMaxBottom =
          max(clusterMaxBottom, list[clusterEnd].top + list[clusterEnd].height);
      clusterEnd++;
    }

    final colEnds = <double>[];
    for (var i = clusterStart; i < clusterEnd; i++) {
      final ev = list[i];
      int assignedCol = -1;
      for (var c = 0; c < colEnds.length && c < 3; c++) {
        if (colEnds[c] <= ev.top) {
          assignedCol = c;
          colEnds[c] = ev.top + ev.height;
          break;
        }
      }
      if (assignedCol == -1) {
        if (colEnds.length < 3) {
          assignedCol = colEnds.length;
          colEnds.add(ev.top + ev.height);
        } else {
          var minCol = 0;
          for (var c = 1; c < 3; c++) {
            if (colEnds[c] < colEnds[minCol]) minCol = c;
          }
          assignedCol = minCol;
          colEnds[minCol] = max(colEnds[minCol], ev.top + ev.height);
        }
      }
      ev.colIndex = assignedCol;
    }

    final numCols = min(3, max(1, colEnds.length));
    for (var i = clusterStart; i < clusterEnd; i++) {
      list[i].totalCols = numCols;
    }

    clusterStart = clusterEnd;
  }

  return list;
}
