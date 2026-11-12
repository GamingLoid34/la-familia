import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../utils/day_events.dart';
import '../../../utils/schedule_time_utils.dart';
import '../../../utils/school_subject_utils.dart';
import '../display_formatters.dart';
import '../display_palette.dart';
import '../display_school_menu_data.dart';

/// Representerar ett enskilt lektionsblock för schematidslinjen (FAS 6d & 6d.2).
class LessonTimelineItem {
  final QueryDocumentSnapshot? doc;
  final String title;
  final String rawTitle;
  final String cleanTitle;
  final String expandedTitle;
  final String? subtitle;
  final String startHm;
  final String endHm;
  final String? location;
  final String? classCode;
  final String piktogram;
  final String schemaLabel;
  final int startMinutes;
  final int endMinutes;
  final ScheduleSemanticType semantic;

  int get durationMinutes => endMinutes - startMinutes;

  const LessonTimelineItem({
    this.doc,
    String? title,
    String? rawTitle,
    String? cleanTitle,
    String? expandedTitle,
    this.subtitle,
    required this.startHm,
    required this.endHm,
    this.location,
    this.classCode,
    required this.piktogram,
    required this.schemaLabel,
    required this.startMinutes,
    required this.endMinutes,
    this.semantic = ScheduleSemanticType.lesson,
  })  : title = title ?? rawTitle ?? 'Lektion',
        rawTitle = rawTitle ?? title ?? 'Lektion',
        cleanTitle = cleanTitle ?? title ?? 'Lektion',
        expandedTitle = expandedTitle ?? title ?? 'Lektion';
}

/// Representerar en rast, lunchlucka eller ombytesmarkör i schematidslinjen (FAS 6d.2).
class BreakTimelineItem {
  final int startMinutes;
  final int endMinutes;
  final String label; // 'Rast', 'Lunch' eller 'Ombyte'
  final bool isLunch;
  final bool isOmbyte;
  final String? lunchText;
  final String? vegText;
  final bool isNudge;

  int get durationMinutes => endMinutes - startMinutes;
  String get startHm => formatMinutesToWallHm(startMinutes);
  String get endHm => formatMinutesToWallHm(endMinutes);

  const BreakTimelineItem({
    required this.startMinutes,
    required this.endMinutes,
    required this.label,
    this.isLunch = false,
    this.isOmbyte = false,
    this.lunchText,
    this.vegText,
    this.isNudge = false,
  });
}

/// Hjälpfunktion för att formatera minuter till HH:MM.
String formatMinutesToWallHm(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Element i den sammansatta tidslinjen.
sealed class TimelineEntry {
  int get startMinutes;
  int get endMinutes;
  int get durationMinutes => endMinutes - startMinutes;
}

class LessonEntryWrapper extends TimelineEntry {
  final LessonTimelineItem item;
  @override
  int get startMinutes => item.startMinutes;
  @override
  int get endMinutes => item.endMinutes;

  LessonEntryWrapper(this.item);
}

class BreakEntryWrapper extends TimelineEntry {
  final BreakTimelineItem item;
  @override
  int get startMinutes => item.startMinutes;
  @override
  int get endMinutes => item.endMinutes;

  BreakEntryWrapper(this.item);
}

/// Tolkar tid 'HH:mm' till minuter från midnatt.
int parseTimeToMinutes(String? timeStr) {
  if (timeStr == null || timeStr.trim().isEmpty) return 1440;
  final clean = timeStr.trim().replaceAll('–', '-').split('-').first.trim();
  final parts = clean.split(':');
  if (parts.length >= 2) {
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }
  return 1440;
}

/// Identifierar lunchluckan bland lektionerna (FAS 6d Beslut 2):
/// Största luckan (gap >= 10 min) mellan 10:30 (630 min) och 13:30 (810 min).
int identifyLunchGapIndex(List<LessonTimelineItem> sortedItems) {
  if (sortedItems.length < 2) return -1;

  const int windowStart = 630; // 10:30
  const int windowEnd = 810; // 13:30

  int bestIdx = -1;
  int bestGap = 0;

  for (int i = 0; i < sortedItems.length - 1; i++) {
    final cur = sortedItems[i];
    final nxt = sortedItems[i + 1];
    final gap = nxt.startMinutes - cur.endMinutes;

    if (gap >= 10) {
      final gapStart = cur.endMinutes;
      final gapEnd = nxt.startMinutes;
      final inWindow = gapStart < windowEnd && gapEnd > windowStart;

      if (inWindow && gap > bestGap) {
        bestGap = gap;
        bestIdx = i;
      }
    }
  }

  return bestIdx;
}

/// Bygger den kompletta listan av tidslinje-poster (FAS 6d.2).
/// Händelsesemantik ur tabellen:
/// - rast|paus -> RAST (luft + etikett)
/// - lunch -> LUNCH-luckan med matsedel eller nudge
/// - ombyte -> smal markör (14 min "Ombyte" i dämpad text)
/// - luckor >= 10 min utan rast-post renderas som rast (eller lunch om i fönstret)
List<TimelineEntry> buildTimelineEntries({
  List<LessonTimelineItem>? sortedItems,
  List<LessonTimelineItem>? sortedLessons,
  required LunchInfo? lunchInfo,
}) {
  final items = sortedItems ?? sortedLessons ?? const [];
  if (items.isEmpty) return const [];

  final hasExplicitLunch = items.any((it) => it.semantic == ScheduleSemanticType.lunch);
  final lunchGapIdx = hasExplicitLunch ? -1 : identifyLunchGapIndex(items);
  final entries = <TimelineEntry>[];

  for (int i = 0; i < items.length; i++) {
    final cur = items[i];

    if (cur.semantic == ScheduleSemanticType.rast) {
      entries.add(BreakEntryWrapper(
        BreakTimelineItem(
          startMinutes: cur.startMinutes,
          endMinutes: cur.endMinutes,
          label: 'Rast',
        ),
      ));
    } else if (cur.semantic == ScheduleSemanticType.ombyte) {
      entries.add(BreakEntryWrapper(
        BreakTimelineItem(
          startMinutes: cur.startMinutes,
          endMinutes: cur.endMinutes,
          label: 'Ombyte',
          isOmbyte: true,
        ),
      ));
    } else if (cur.semantic == ScheduleSemanticType.lunch) {
      final isNudge = lunchInfo != null && lunchInfo.isNudge;
      final cleanLunch = lunchInfo != null && lunchInfo.lunch != null && !isNudge
          ? cleanDishTitle(lunchInfo.lunch!)
          : (isNudge ? lunchInfo.lunch : null);
      final hasVeg = !isNudge && hasDistinctVegetarian(cleanLunch, lunchInfo?.vegetarian);
      final cleanVeg = hasVeg ? cleanDishTitle(lunchInfo!.vegetarian!) : null;

      entries.add(BreakEntryWrapper(
        BreakTimelineItem(
          startMinutes: cur.startMinutes,
          endMinutes: cur.endMinutes,
          label: 'Lunch',
          isLunch: true,
          lunchText: cleanLunch,
          vegText: cleanVeg,
          isNudge: isNudge,
        ),
      ));
    } else {
      // Riktig lektion
      entries.add(LessonEntryWrapper(cur));
    }

    // Skapa luckor mellan poster (>= 10 min)
    if (i < items.length - 1) {
      final nxt = items[i + 1];
      final gap = nxt.startMinutes - cur.endMinutes;

      if (gap >= 10) {
        final isLunch = (i == lunchGapIdx);
        final isNudge = isLunch && lunchInfo != null && lunchInfo.isNudge;
        final cleanLunch = isLunch && lunchInfo != null && lunchInfo.lunch != null && !isNudge
            ? cleanDishTitle(lunchInfo.lunch!)
            : (isNudge ? lunchInfo.lunch : null);
        final hasVeg = isLunch && !isNudge && hasDistinctVegetarian(cleanLunch, lunchInfo?.vegetarian);
        final cleanVeg = hasVeg ? cleanDishTitle(lunchInfo!.vegetarian!) : null;

        entries.add(BreakEntryWrapper(
          BreakTimelineItem(
            startMinutes: cur.endMinutes,
            endMinutes: nxt.startMinutes,
            label: isLunch ? 'Lunch' : 'Rast',
            isLunch: isLunch,
            lunchText: (cleanLunch != null && cleanLunch.isNotEmpty) ? cleanLunch : null,
            vegText: (cleanVeg != null && cleanVeg.isNotEmpty) ? cleanVeg : null,
            isNudge: isNudge,
          ),
        ));
      }
    }
  }

  return entries;
}

/// Beräknar minsta höjd för en tidslinjepost (FAS 6d.2 Build 24):
/// - Lektion >= 20 min: 64 px (tvåradigt block: ämne 28 px w700, tid 20 px w600)
/// - Lektion < 20 min: 32 px (enradigt block: tid + ämne på en rad, 20 px)
/// - Rast-luft: 24 px
/// - Ombyte-markör: 24 px
/// - Lunchlucka: 56 px
/// Resultat av höjdberäkning för schemarader (FAS 6d.3).
class ScheduleHeightsResult {
  final List<double> heights;
  final bool useSqueezedBreaks;
  final bool isOverflowing;

  const ScheduleHeightsResult({
    required this.heights,
    required this.useSqueezedBreaks,
    required this.isOverflowing,
  });
}

/// Beräknar höjd h_i = clamp(d_i * k, min_i, max_i) för schemarader (FAS 6d.3):
/// - Lektion: min 48 / max 88 px
/// - Rast: 24/24 px (kan krympas till 18 px)
/// - Ombyte: 24/24 px (kan krympas till 18 px)
/// - Lunch: 48/64 px
/// k väljs per dag som största värde där sum(h_i) <= H (start 1.2 px/min).
/// Aldrig uppblåst — ledig höjd under schemat är tillåten och fylls inte upp.
ScheduleHeightsResult computeScheduleRowHeights({
  required List<TimelineEntry> entries,
  required double availableHeight,
  double kStart = 1.2,
}) {
  double entryMin(TimelineEntry e, {bool squeezeBreaks = false}) {
    if (e is LessonEntryWrapper) return 48.0;
    if (e is BreakEntryWrapper) {
      if (e.item.isLunch) return 48.0;
      if (e.item.isOmbyte) return squeezeBreaks ? 18.0 : 24.0;
      return squeezeBreaks ? 18.0 : 24.0;
    }
    return 24.0;
  }

  double entryMax(TimelineEntry e) {
    if (e is LessonEntryWrapper) return 88.0;
    if (e is BreakEntryWrapper) {
      if (e.item.isLunch) return 64.0;
      if (e.item.isOmbyte) return 24.0;
      return 24.0;
    }
    return 24.0;
  }

  final dividerTotal = entries.length > 1 ? (entries.length - 1) * 1.0 : 0.0;
  final effectiveAvailable = (availableHeight - dividerTotal).clamp(0.0, 5000.0);

  double sumHeightsForK(double k, {bool squeezeBreaks = false}) {
    double sum = 0.0;
    for (final e in entries) {
      final minH = entryMin(e, squeezeBreaks: squeezeBreaks);
      final maxH = entryMax(e);
      final d = e.durationMinutes > 0 ? e.durationMinutes : 1;
      final h = (d * k).clamp(minH, maxH);
      sum += h;
    }
    return sum;
  }

  if (!availableHeight.isFinite) {
    final heights = entries.map((e) {
      final minH = entryMin(e);
      final maxH = entryMax(e);
      final d = e.durationMinutes > 0 ? e.durationMinutes : 1;
      return (d * kStart).clamp(minH, maxH);
    }).toList();
    return ScheduleHeightsResult(heights: heights, useSqueezedBreaks: false, isOverflowing: false);
  }

  // 1. Prova k = 1.2 (startvärde)
  final sumStandardK = sumHeightsForK(kStart, squeezeBreaks: false);
  if (sumStandardK <= effectiveAvailable) {
    final heights = entries.map((e) {
      final minH = entryMin(e);
      final maxH = entryMax(e);
      final d = e.durationMinutes > 0 ? e.durationMinutes : 1;
      return (d * kStart).clamp(minH, maxH);
    }).toList();
    return ScheduleHeightsResult(heights: heights, useSqueezedBreaks: false, isOverflowing: false);
  }

  // 2. Minska k så att sumHeightsForK(k) <= effectiveAvailable
  final sumStandardMin = sumHeightsForK(0.0, squeezeBreaks: false);
  if (sumStandardMin <= effectiveAvailable) {
    double low = 0.0;
    double high = kStart;
    for (int iter = 0; iter < 16; iter++) {
      final mid = (low + high) / 2;
      if (sumHeightsForK(mid, squeezeBreaks: false) <= effectiveAvailable) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final kChosen = low;
    final heights = entries.map((e) {
      final minH = entryMin(e);
      final maxH = entryMax(e);
      final d = e.durationMinutes > 0 ? e.durationMinutes : 1;
      return (d * kChosen).clamp(minH, maxH);
    }).toList();
    return ScheduleHeightsResult(heights: heights, useSqueezedBreaks: false, isOverflowing: false);
  }

  // 3. Prova att klämma rast/ombyte till 18 px
  final sumSqueezedMin = sumHeightsForK(0.0, squeezeBreaks: true);
  if (sumSqueezedMin <= effectiveAvailable) {
    final heights = entries.map((e) => entryMin(e, squeezeBreaks: true)).toList();
    return ScheduleHeightsResult(heights: heights, useSqueezedBreaks: true, isOverflowing: false);
  }

  // 4. Ryms inte ens med 18 px -> fallback till lista
  final heights = entries.map((e) => entryMin(e, squeezeBreaks: true)).toList();
  return ScheduleHeightsResult(heights: heights, useSqueezedBreaks: true, isOverflowing: true);
}

/// Kontrollerar om kompakt lista ska användas som fallback (FAS 6d.3):
/// Lista används ENDAST som absolut sista utväg om inte ens minimihöjderna ryms.
bool shouldUseCompactFallback({
  List<TimelineEntry>? entries,
  List<LessonTimelineItem>? realLessons,
  int? lessonCount,
  int totalSpanMinutes = 360,
  int breakCount = 0,
  bool hasLunch = false,
  required double availableHeight,
}) {
  if (!availableHeight.isFinite || availableHeight <= 0) return false;

  const double headerAndPadding = 70.0;
  final availableTimelineH = availableHeight - headerAndPadding;
  if (availableTimelineH <= 0) return true;

  if (entries != null && entries.isNotEmpty) {
    return computeScheduleRowHeights(
      entries: entries,
      availableHeight: availableTimelineH,
    ).isOverflowing;
  }

  double sumMinSqueezed = 0.0;
  if (realLessons != null && realLessons.isNotEmpty) {
    sumMinSqueezed += realLessons.length * 48.0;
    sumMinSqueezed += breakCount * 18.0;
    if (hasLunch) sumMinSqueezed += 48.0;
  } else if (lessonCount != null) {
    sumMinSqueezed = (lessonCount * 48.0) + (breakCount * 18.0) + (hasLunch ? 48.0 : 0.0);
  }

  return sumMinSqueezed > availableTimelineH;
}

/// Beräknar proportionell position (0.0 .. 1.0) för nu-linjen.
double? computeNuLineFraction({
  required int nowMinutes,
  required int dayStartMinutes,
  required int dayEndMinutes,
}) {
  final totalDuration = dayEndMinutes - dayStartMinutes;
  if (totalDuration <= 0) return null;
  if (nowMinutes < dayStartMinutes || nowMinutes > dayEndMinutes) return null;
  return (nowMinutes - dayStartMinutes) / totalDuration;
}

/// Huvud-widget för skolschemat i personvyn (`persondag`) (FAS 6d, 6d.2 & 6d.3).
class PersondagSchemaView extends StatelessWidget {
  final List<QueryDocumentSnapshot> scheduleDocs;
  final Color memberColor;
  final DateTime now;
  final bool isLowStimuli;
  final LunchInfo? lunchInfo;
  final DisplayPalette displayPalette;
  final bool isTomorrow;
  final bool showHeader;
  final bool hasCardWrapper;

  const PersondagSchemaView({
    super.key,
    required this.scheduleDocs,
    required this.memberColor,
    required this.now,
    required this.isLowStimuli,
    this.lunchInfo,
    required this.displayPalette,
    this.isTomorrow = false,
    this.showHeader = true,
    this.hasCardWrapper = true,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Parsa alla schemaposter och applicera semantik och ämnesexpansion
    final allItems = <LessonTimelineItem>[];

    for (final doc in scheduleDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final timeStr = (d['time'] as String? ?? '').trim();
      if (timeStr.isEmpty) continue; // heldagsposter ignoreras här

      final endStr = (d['endTime'] as String? ?? '').trim();
      final startM = parseTimeToMinutes(timeStr);
      var endM = endStr.isNotEmpty ? parseTimeToMinutes(endStr) : startM + 45;
      if (endM <= startM) endM = startM + 45;

      final sHm = formatWallTime(timeStr);
      final eHm = endStr.isNotEmpty ? formatWallTime(endStr) : '';

      final rawTitle = (d['title'] as String? ?? '').trim();
      final cleanTitle = cleanLessonTitle(rawTitle);
      final semantic = classifyScheduleSemantic(cleanTitle);
      final calDesc = (d['calendarDescription'] as String?)?.trim();
      final cleanedSubject = cleanAndExpandSubjectTitle(rawTitle, calendarDescription: calDesc);
      final expandedTitle = cleanedSubject.subject;
      final classCode = cleanedSubject.classCode;

      // Om calendarDescription bär kursnamn som skiljer sig från titeln, visa koden som undertitel
      String? subtitle;
      if (calDesc != null && calDesc.isNotEmpty) {
        final match = RegExp(r'^(kurs|ämne):\s*(.+)$', caseSensitive: false).firstMatch(calDesc);
        if (match != null) {
          final extracted = match.group(2)?.trim() ?? '';
          if (extracted.isNotEmpty && extracted.toLowerCase() != cleanTitle.toLowerCase()) {
            subtitle = cleanTitle;
          }
        }
      }

      final sal = (d['location'] as String?)?.trim();
      final pik = schemaPiktogramFor(d);
      final label = schemaLabelFor(d);

      allItems.add(LessonTimelineItem(
        doc: doc,
        rawTitle: rawTitle,
        cleanTitle: cleanTitle,
        expandedTitle: expandedTitle,
        classCode: classCode,
        subtitle: subtitle,
        startHm: sHm,
        endHm: eHm,
        location: (sal != null && sal.isNotEmpty) ? sal : null,
        piktogram: pik,
        schemaLabel: label,
        startMinutes: startM,
        endMinutes: endM,
        semantic: semantic,
      ));
    }

    if (allItems.isEmpty) {
      return const SizedBox.shrink();
    }

    allItems.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    // Endast riktiga lektioner räknas mot tröskeln
    final realLessons = allItems.where((it) => it.semantic == ScheduleSemanticType.lesson).toList();

    final entries = buildTimelineEntries(
      sortedItems: allItems,
      lunchInfo: lunchInfo,
    );

    final dayStart = allItems.first.startMinutes;
    final dayEnd = allItems.last.endMinutes;
    final totalSpanMinutes = (dayEnd - dayStart).clamp(1, 1440);
    final spanTimeStr = formatWallRange(allItems.first.startHm, allItems.last.endHm);
    final headerPik = allItems.first.piktogram;
    final headerLabel = allItems.first.schemaLabel;
    final headerText = spanTimeStr.isNotEmpty
        ? '$headerPik $headerLabel · $spanTimeStr'
        : '$headerPik $headerLabel';

    final nowMinutes = isTomorrow ? -1 : (now.hour * 60 + now.minute);
    final nuFraction = isTomorrow
        ? null
        : computeNuLineFraction(
            nowMinutes: nowMinutes,
            dayStartMinutes: dayStart,
            dayEndMinutes: dayEnd,
          );

    // Hitta nästa lektion (för countdown)
    LessonTimelineItem? nextLesson;
    int minCountdown = 999999;
    if (!isTomorrow) {
      for (final l in realLessons) {
        final diff = l.startMinutes - nowMinutes;
        if (diff > 0 && diff < minCountdown) {
          minCountdown = diff;
          nextLesson = l;
        }
      }
    }

    final ongoingAccent = displayPalette.ongoingAccent(isLowStimuli: isLowStimuli);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final double headerAndPaddingH = (showHeader ? 44.0 : 0.0) + 16.0;
        final double availableTimelineH = maxH.isFinite
            ? (maxH - headerAndPaddingH)
            : 5000.0;

        final heightsResult = computeScheduleRowHeights(
          entries: entries,
          availableHeight: availableTimelineH,
          kStart: 1.2,
        );

        if (heightsResult.isOverflowing) {
          return _buildCompactListFallback(
            headerText: headerText,
            items: allItems,
            nowMinutes: nowMinutes,
            nextLesson: nextLesson,
            minCountdown: minCountdown,
            ongoingAccent: ongoingAccent,
            maxHeight: maxH,
            showHeader: showHeader,
            hasCardWrapper: hasCardWrapper,
            isTomorrow: isTomorrow,
          );
        }

        return _buildProportionalTimeline(
          headerText: headerText,
          entries: entries,
          rowHeights: heightsResult.heights,
          totalSpanMinutes: totalSpanMinutes,
          nuFraction: nuFraction,
          nowMinutes: nowMinutes,
          nextLesson: nextLesson,
          minCountdown: minCountdown,
          ongoingAccent: ongoingAccent,
          maxHeight: maxH,
          showHeader: showHeader,
          hasCardWrapper: hasCardWrapper,
          isTomorrow: isTomorrow,
        );
      },
    );
  }

  /// Bygger schemaraderna enligt FAS 6d.3 (aldrig uppblåst, ledig höjd förblir ledig).
  Widget _buildProportionalTimeline({
    required String headerText,
    required List<TimelineEntry> entries,
    required List<double> rowHeights,
    required int totalSpanMinutes,
    required double? nuFraction,
    required int nowMinutes,
    required LessonTimelineItem? nextLesson,
    required int minCountdown,
    required Color ongoingAccent,
    required double maxHeight,
    bool showHeader = true,
    bool hasCardWrapper = true,
    bool isTomorrow = false,
  }) {
    final double dividerTotal = entries.length > 1 ? (entries.length - 1) * 1.0 : 0.0;
    double sumEntriesH = 0.0;
    for (final h in rowHeights) {
      sumEntriesH += h;
    }
    final totalTimelineH = sumEntriesH + dividerTotal;

    final timelineWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < entries.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 0.8,
                  color: memberColor.withValues(alpha: 0.15),
                ),
              SizedBox(
                height: rowHeights[i],
                child: _buildTimelineItemWidget(
                  entry: entries[i],
                  nowMinutes: nowMinutes,
                  nextLesson: nextLesson,
                  minCountdown: minCountdown,
                  ongoingAccent: ongoingAccent,
                  isTomorrow: isTomorrow,
                ),
              ),
            ],
          ],
        ),
        // Nu-linje (endast idag)
        if (nuFraction != null && !isTomorrow)
          Positioned(
            left: 0,
            right: 0,
            top: (totalTimelineH * nuFraction).clamp(0.0, totalTimelineH),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: ongoingAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 2,
                    color: ongoingAccent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: memberColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    headerText,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: memberColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: timelineWidget,
        ),
      ],
    );

    if (!hasCardWrapper) {
      return column;
    }

    return Container(
      decoration: BoxDecoration(
        color: displayPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: memberColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: isLowStimuli
            ? null
            : [
                BoxShadow(
                  color: displayPalette.isDark
                      ? Colors.black.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: column,
    );
  }

  /// Rendera ett enskilt element i schemat enligt FAS 6d.3:
  /// - Radinnehåll: tid HH:MM–HH:MM (20 px w600) · ämne (24 px w700) · sal (18 px dämpad, om finns)
  /// - Nu-linje, PÅGÅR, "om X" och tonade passerade rader
  /// - Inget under 18 px, ingen FittedBox
  Widget _buildTimelineItemWidget({
    required TimelineEntry entry,
    required int nowMinutes,
    required LessonTimelineItem? nextLesson,
    required int minCountdown,
    required Color ongoingAccent,
    bool isTomorrow = false,
  }) {
    if (entry is LessonEntryWrapper) {
      final item = entry.item;
      final isOngoing = !isTomorrow && (nowMinutes >= item.startMinutes && nowMinutes < item.endMinutes);
      final isPast = !isTomorrow && (nowMinutes >= item.endMinutes);
      final isNext = !isTomorrow && (item == nextLesson) && !isOngoing && !isPast;

      final timeDisplay = item.endHm.isNotEmpty ? '${item.startHm}–${item.endHm}' : item.startHm;

      final effectiveOpacity = isTomorrow ? 0.75 : (isPast ? 0.45 : 1.0);
      final textColor = (isPast || isTomorrow)
          ? displayPalette.textMuted.withValues(alpha: 0.6)
          : displayPalette.textPrimary;

      return Opacity(
        opacity: effectiveOpacity,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: isOngoing
                ? memberColor.withValues(alpha: 0.18)
                : memberColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: isOngoing
                ? Border.all(color: ongoingAccent, width: 2.0)
                : Border(left: BorderSide(color: memberColor.withValues(alpha: 0.6), width: 3.5)),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                timeDisplay,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isOngoing ? ongoingAccent : textColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '·',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: displayPalette.textMuted.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        item.expandedTitle,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: isOngoing ? ongoingAccent : textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.classCode != null && item.classCode!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        item.classCode!,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: displayPalette.textMuted,
                        ),
                      ),
                    ],
                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          item.subtitle!,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: displayPalette.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.location != null && item.location!.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  item.location!.toLowerCase().startsWith('sal')
                      ? item.location!
                      : 'Sal ${item.location!}',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: displayPalette.textMuted,
                  ),
                ),
              ],
              if (isOngoing) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ongoingAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'PÅGÅR',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ongoingAccent,
                    ),
                  ),
                ),
              ] else if (isNext && minCountdown > 0) ...[
                const SizedBox(width: 10),
                Text(
                  formatCountdownMinutes(minCountdown),
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: memberColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (entry is BreakEntryWrapper) {
      final b = entry.item;
      final isPast = !isTomorrow && (nowMinutes >= b.endMinutes);
      final effectiveOpacity = isTomorrow ? 0.75 : (isPast ? 0.5 : 1.0);

      // Lunch
      if (b.isLunch) {
        Widget lunchContent;
        if (b.isNudge || (b.lunchText != null && b.lunchText!.contains('Matsedel saknas'))) {
          // FAS 5.1b Nudge i lunchluckan
          lunchContent = Row(
            children: [
              Text(
                '${b.startHm}–${b.endHm}',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: displayPalette.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              const Text('· 🍽', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Matsedel saknas — ladda upp i appen',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: displayPalette.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        } else if (b.lunchText != null && b.lunchText!.isNotEmpty) {
          final hasVeg = hasDistinctVegetarian(b.lunchText, b.vegText);
          final text = (hasVeg && b.vegText != null && b.vegText!.isNotEmpty)
              ? '${b.lunchText!} · 🌱 ${b.vegText!}'
              : b.lunchText!;
          lunchContent = Row(
            children: [
              Text(
                '${b.startHm}–${b.endHm}',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: displayPalette.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              const Text('· 🍽', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: displayPalette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        } else {
          lunchContent = Row(
            children: [
              Text(
                '${b.startHm}–${b.endHm}',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: displayPalette.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· Lunch',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  color: displayPalette.textMuted,
                ),
              ),
            ],
          );
        }

        return Opacity(
          opacity: effectiveOpacity,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: lunchContent,
          ),
        );
      }

      // Ombyte: smal markör (14 min "Ombyte" i dämpad text 18 px)
      if (b.isOmbyte) {
        return Opacity(
          opacity: effectiveOpacity,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: displayPalette.textMuted.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Ombyte',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: displayPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Vanlig rast: luft + etikett (18 px kursiv dämpad)
      return Opacity(
        opacity: effectiveOpacity,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'Rast',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: displayPalette.textMuted.withValues(alpha: 0.8),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Kompakt lista fallback med `+N till` (FAS 6d.3).
  /// Typografi: allt >= 18 px.
  Widget _buildCompactListFallback({
    required String headerText,
    required List<LessonTimelineItem> items,
    required int nowMinutes,
    required LessonTimelineItem? nextLesson,
    required int minCountdown,
    required Color ongoingAccent,
    required double maxHeight,
    bool showHeader = true,
    bool hasCardWrapper = true,
    bool isTomorrow = false,
  }) {
    final double headerHeight = showHeader ? 44.0 : 0.0;
    final availableH = maxHeight.isFinite ? (maxHeight - headerHeight - 16.0) : (items.length * 44.0);
    const double rowHeight = 44.0;
    final safeAvailableH = (availableH.isFinite && availableH > 0) ? availableH : (items.length * rowHeight);
    final maxRows = (safeAvailableH / rowHeight).floor().clamp(1, items.length);

    int visibleCount = items.length;
    int hiddenCount = 0;

    if (visibleCount > maxRows && maxRows > 1) {
      visibleCount = maxRows - 1;
      hiddenCount = items.length - visibleCount;
    }

    final visibleItems = items.take(visibleCount).toList();

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: memberColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Text(
              headerText,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: memberColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in visibleItems) ...[
                Builder(
                  builder: (context) {
                    final isOngoing = !isTomorrow && (nowMinutes >= item.startMinutes && nowMinutes < item.endMinutes);
                    final isPast = !isTomorrow && (nowMinutes >= item.endMinutes);
                    final isNext = !isTomorrow && (item == nextLesson) && !isOngoing && !isPast;
                    final timeDisplay = item.endHm.isNotEmpty ? '${item.startHm}–${item.endHm}' : item.startHm;

                    final isBreak = item.semantic == ScheduleSemanticType.rast ||
                        item.semantic == ScheduleSemanticType.ombyte ||
                        item.semantic == ScheduleSemanticType.lunch;

                    final effectiveOpacity = isTomorrow ? 0.75 : (isPast ? 0.45 : 1.0);

                    return Opacity(
                      opacity: effectiveOpacity,
                      child: Container(
                        height: 38,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isOngoing
                              ? memberColor.withValues(alpha: 0.18)
                              : (isBreak ? Colors.transparent : memberColor.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(6),
                          border: isOngoing ? Border.all(color: ongoingAccent, width: 1.5) : null,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                timeDisplay,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 18,
                                  fontWeight: isOngoing ? FontWeight.w800 : FontWeight.w600,
                                  color: isOngoing ? ongoingAccent : displayPalette.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.expandedTitle,
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: isBreak ? 18 : 20,
                                        fontStyle: isBreak ? FontStyle.italic : FontStyle.normal,
                                        fontWeight: isBreak ? FontWeight.w600 : FontWeight.w700,
                                        color: isBreak ? displayPalette.textMuted : displayPalette.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (item.classCode != null && item.classCode!.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      item.classCode!,
                                      style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        color: displayPalette.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (item.location != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                item.location!,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 18,
                                  color: displayPalette.textMuted,
                                ),
                              ),
                            ],
                            if (isOngoing) ...[
                              const SizedBox(width: 8),
                              Text(
                                'PÅGÅR',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: ongoingAccent,
                                ),
                              ),
                            ] else if (isNext && minCountdown > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                formatCountdownMinutes(minCountdown),
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: memberColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (hiddenCount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    '+$hiddenCount till',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: displayPalette.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (!hasCardWrapper) {
      return column;
    }

    return Container(
      decoration: BoxDecoration(
        color: displayPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: memberColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: column,
    );
  }
}
