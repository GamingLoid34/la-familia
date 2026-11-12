import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'date_utils.dart';
import 'person_match.dart';
import 'recurrence.dart';
import 'schedule_time_utils.dart';

/// Resultatet av veckans bucketing — gemensam sanning för WeekGrid, WeekList
/// och Storskärmens Veckotavla.
class WeekBucketingResult {
  /// Veckans 7 dagar (måndag till söndag).
  final List<DateTime> days;

  /// uid → (dateKey → händelser sorterade efter tid)
  final Map<String, Map<String, List<QueryDocumentSnapshot>>> byMember;

  /// dateKey → familjegemensamma händelser (utan angivna personer)
  final Map<String, List<QueryDocumentSnapshot>> familyByDay;

  /// uid → (dateKey → arbetspass som rör dagen)
  final Map<String, Map<String, List<QueryDocumentSnapshot>>> shiftsByMember;

  const WeekBucketingResult({
    required this.days,
    required this.byMember,
    required this.familyByDay,
    required this.shiftsByMember,
  });

  List<QueryDocumentSnapshot> eventsFor(UserModel m, DateTime day) =>
      eventsForUid(m.uid, day);

  List<QueryDocumentSnapshot> eventsForUid(String uid, DateTime day) =>
      byMember[uid]?[dateKey(day)] ?? const [];

  List<QueryDocumentSnapshot> shiftsFor(UserModel m, DateTime day) =>
      shiftsForUid(m.uid, day);

  List<QueryDocumentSnapshot> shiftsForUid(String uid, DateTime day) =>
      shiftsByMember[uid]?[dateKey(day)] ?? const [];

  List<QueryDocumentSnapshot> familyFor(DateTime day) =>
      familyByDay[dateKey(day)] ?? const [];

  bool get hasFamilyEvents =>
      familyByDay.values.any((list) => list.isNotEmpty);
}

/// Beräknar vilka dagar under veckan en händelse inträffar.
List<DateTime> occurrenceDaysForEvent(
  QueryDocumentSnapshot doc,
  Map<String, dynamic> d,
  List<DateTime> days, {
  DateTime? weekStart,
  Map<String, List<DateTime>>? recurrenceCache,
}) {
  final weekKey = dateKey(weekStart ?? days.first);
  final cacheKey = '${doc.id}_$weekKey';
  if (recurrenceCache != null) {
    final cached = recurrenceCache[cacheKey];
    if (cached != null) return cached;
  }

  final out = <DateTime>[];
  if (d['recurrence'] != null) {
    for (final day in days) {
      if (recurringOccursOnDay(d, day)) out.add(day);
    }
  } else {
    for (final day in days) {
      if (eventOccursOnDay(d, day)) out.add(day);
    }
  }

  if (recurrenceCache != null) {
    recurrenceCache[cacheKey] = out;
  }
  return out;
}

/// Genererar veckans 7 dagar med start från måndagen [weekStart].
List<DateTime> getWeekDays(DateTime weekStart) {
  return List.generate(
    7,
    (i) => DateTime(weekStart.year, weekStart.month, weekStart.day + i),
  );
}

/// Central bucketing-funktion: fördelar händelser och arbetspass per medlem och dag.
WeekBucketingResult bucketWeekData({
  required List<UserModel> members,
  required List<QueryDocumentSnapshot> events,
  required List<QueryDocumentSnapshot> shifts,
  required DateTime weekStart,
  Map<String, List<DateTime>>? recurrenceCache,
}) {
  final days = getWeekDays(weekStart);
  final map = <String, Map<String, List<QueryDocumentSnapshot>>>{};
  final shiftMap = <String, Map<String, List<QueryDocumentSnapshot>>>{};

  for (final m in members) {
    map[m.uid] = {
      for (final day in days) dateKey(day): <QueryDocumentSnapshot>[]
    };
    shiftMap[m.uid] = {
      for (final day in days) dateKey(day): <QueryDocumentSnapshot>[]
    };
  }
  final family = {
    for (final day in days) dateKey(day): <QueryDocumentSnapshot>[]
  };

  for (final doc in events) {
    final d = doc.data() as Map<String, dynamic>;
    final occ = occurrenceDaysForEvent(
      doc,
      d,
      days,
      weekStart: weekStart,
      recurrenceCache: recurrenceCache,
    );
    if (occ.isEmpty) continue;

    if (eventHasNoPersons(d)) {
      for (final day in occ) {
        family[dateKey(day)]?.add(doc);
      }
      continue;
    }

    for (final m in members) {
      if (!eventIncludesPerson(d, uid: m.uid, name: m.name)) continue;
      final byDay = map[m.uid];
      if (byDay != null) {
        for (final day in occ) {
          byDay[dateKey(day)]?.add(doc);
        }
      }
    }
  }

  for (final doc in shifts) {
    final d = doc.data() as Map<String, dynamic>;
    for (final m in members) {
      if (!assignedToPerson(d, uid: m.uid, name: m.name)) continue;
      final byDay = shiftMap[m.uid];
      if (byDay != null) {
        for (final day in days) {
          if (shiftTouchesDay(d, day)) {
            byDay[dateKey(day)]?.add(doc);
          }
        }
      }
    }
  }

  // Sortera kronologiskt på tid
  for (final byDay in map.values) {
    for (final list in byDay.values) {
      list.sort((a, b) {
        final ta = ((a.data() as Map)['time'] as String? ?? '99:99').trim();
        final tb = ((b.data() as Map)['time'] as String? ?? '99:99').trim();
        return ta.compareTo(tb);
      });
    }
  }
  for (final list in family.values) {
    list.sort((a, b) {
      final ta = ((a.data() as Map)['time'] as String? ?? '99:99').trim();
      final tb = ((b.data() as Map)['time'] as String? ?? '99:99').trim();
      return ta.compareTo(tb);
    });
  }

  return WeekBucketingResult(
    days: days,
    byMember: map,
    familyByDay: family,
    shiftsByMember: shiftMap,
  );
}
