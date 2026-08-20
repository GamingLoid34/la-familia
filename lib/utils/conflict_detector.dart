import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import 'person_match.dart';
import 'recurrence.dart';
import 'schedule_time_utils.dart';

/// Konfliktdetektering: vuxna som krockar + barn utan ledig förälder.

class ScheduleConflict {
  final DateTime day;
  final DateTime start;
  final DateTime end;
  final List<UserModel> adults;

  /// Barnhämtning: text för chip ("🚗 ons 17:00 — vem tar Liam?").
  final String? pickupLabel;
  final UserModel? child;
  final String? eventTitle;

  const ScheduleConflict({
    required this.day,
    required this.start,
    required this.end,
    required this.adults,
    this.pickupLabel,
    this.child,
    this.eventTitle,
  });

  bool get isPickup => pickupLabel != null;
}

class _Interval {
  final DateTime start;
  final DateTime end;
  final UserModel adult;
  _Interval(this.start, this.end, this.adult);
}

/// Upptagna intervall för [adult] på [day] från events + arbetspass.
List<_Interval> _busyIntervalsFor(
  UserModel adult,
  DateTime day,
  List<QueryDocumentSnapshot> events,
  List<QueryDocumentSnapshot> shifts,
) {
  final out = <_Interval>[];

  for (final doc in events) {
    final d = doc.data() as Map<String, dynamic>;
    if (!eventOccursOnDay(d, day)) continue;
    if (eventHasNoPersons(d)) continue;
    if (!eventIncludesPerson(d, uid: adult.uid, name: adult.name)) continue;
    final t = (d['time'] as String?)?.trim() ?? '';
    if (t.isEmpty) continue;
    final start = parseHmOnDate(t, day);
    if (start == null) continue;
    final endStr = (d['endTime'] as String?)?.trim() ?? '';
    final end = endStr.isNotEmpty
        ? (parseHmOnDate(endStr, day) ?? start.add(const Duration(hours: 1)))
        : start.add(const Duration(hours: 1));
    if (!end.isAfter(start)) continue;
    out.add(_Interval(start, end, adult));
  }

  for (final doc in shifts) {
    final d = doc.data() as Map<String, dynamic>;
    if (!assignedToPerson(d, uid: adult.uid, name: adult.name)) continue;
    if (!shiftTouchesDay(d, day)) continue;
    final interval = shiftInterval(d);
    if (interval == null) continue;
    // Klipp till dagens dygn så parvis-jämförelse fungerar.
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final st =
        interval.start.isBefore(dayStart) ? dayStart : interval.start;
    final en = interval.end.isAfter(dayEnd) ? dayEnd : interval.end;
    if (!en.isAfter(st)) continue;
    out.add(_Interval(st, en, adult));
  }

  return out;
}

bool _adultBusyDuring(
  UserModel adult,
  DateTime start,
  DateTime end,
  List<_Interval> busy,
) {
  for (final b in busy) {
    if (b.adult.uid != adult.uid) continue;
    final s = b.start.isAfter(start) ? b.start : start;
    final e = b.end.isBefore(end) ? b.end : end;
    if (e.isAfter(s)) return true;
  }
  return false;
}

/// Alla vuxen-krockar inom [weekStart] .. [weekStart]+6 dagar.
List<ScheduleConflict> detectAdultConflicts({
  required List<UserModel> members,
  required List<QueryDocumentSnapshot> events,
  required List<QueryDocumentSnapshot> shifts,
  required DateTime weekStart,
}) {
  final adults = members.where((m) => m.isParent).toList();
  if (adults.length < 2) return const [];

  final conflicts = <ScheduleConflict>[];

  for (var i = 0; i < 7; i++) {
    final day = DateTime(weekStart.year, weekStart.month, weekStart.day + i);

    final all = <_Interval>[];
    for (final adult in adults) {
      all.addAll(_busyIntervalsFor(adult, day, events, shifts));
    }
    if (all.length < 2) continue;

    for (var a = 0; a < all.length; a++) {
      for (var b = a + 1; b < all.length; b++) {
        final x = all[a];
        final y = all[b];
        if (x.adult.uid == y.adult.uid) continue;
        final start = x.start.isAfter(y.start) ? x.start : y.start;
        final end = x.end.isBefore(y.end) ? x.end : y.end;
        if (!end.isAfter(start)) continue;

        final existing = conflicts
            .where((c) =>
                !c.isPickup && c.start == start && c.end == end)
            .toList();
        if (existing.isNotEmpty) {
          final c = existing.first;
          for (final ad in [x.adult, y.adult]) {
            if (!c.adults.any((m) => m.uid == ad.uid)) c.adults.add(ad);
          }
        } else {
          conflicts.add(ScheduleConflict(
            day: day,
            start: start,
            end: end,
            adults: [x.adult, y.adult],
          ));
        }
      }
    }
  }

  conflicts.sort((a, b) => a.start.compareTo(b.start));
  return conflicts;
}

/// Barn-event där ALLA föräldrar är upptagna i intervallet → hämtningschip.
List<ScheduleConflict> detectPickupConflicts({
  required List<UserModel> members,
  required List<QueryDocumentSnapshot> events,
  required List<QueryDocumentSnapshot> shifts,
  required DateTime weekStart, // eller vald dag — 7 dagar från start
  int dayCount = 7,
}) {
  final adults = members.where((m) => m.isParent).toList();
  final children =
      members.where((m) => !m.isParent).toList();
  if (adults.isEmpty || children.isEmpty) return const [];

  final out = <ScheduleConflict>[];
  final seenHour = <String>{};

  for (var i = 0; i < dayCount; i++) {
    final day = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
    final busyByAdult = <String, List<_Interval>>{};
    for (final adult in adults) {
      busyByAdult[adult.uid] =
          _busyIntervalsFor(adult, day, events, shifts);
    }
    final allBusy = busyByAdult.values.expand((e) => e).toList();

    for (final doc in events) {
      final d = doc.data() as Map<String, dynamic>;
      if (!eventOccursOnDay(d, day)) continue;
      if (eventHasNoPersons(d)) continue;
      // Schema-import räknas inte som hämtning.
      if ((d['source'] as String?) == 'calendar' &&
          (d['planningImportKind'] as String? ?? 'schedule') == 'schedule') {
        continue;
      }
      final t = (d['time'] as String?)?.trim() ?? '';
      if (t.isEmpty) continue;
      final start = parseHmOnDate(t, day);
      if (start == null) continue;
      final endStr = (d['endTime'] as String?)?.trim() ?? '';
      final end = endStr.isNotEmpty
          ? (parseHmOnDate(endStr, day) ??
              start.add(const Duration(hours: 1)))
          : start.add(const Duration(hours: 1));
      if (!end.isAfter(start)) continue;

      UserModel? child;
      for (final c in children) {
        if (eventIncludesPerson(d, uid: c.uid, name: c.name)) {
          child = c;
          break;
        }
      }
      if (child == null) continue;

      final allParentsBusy = adults.every(
        (a) => _adultBusyDuring(a, start, end, allBusy),
      );
      if (!allParentsBusy) continue;

      final hourKey =
          '${dateKeyLike(day)}_${start.hour}_${child.uid}';
      if (!seenHour.add(hourKey)) continue;

      final dayName = DateFormat('EEE', 'sv').format(day);
      final hm = DateFormat('HH:mm').format(start);
      final first = child.name.split(' ').first;
      final title = (d['title'] as String? ?? '').trim();
      final label = title.isEmpty
          ? '🚗 $dayName $hm — vem tar $first?'
          : '🚗 $dayName $hm — vem tar $first till $title?';

      out.add(ScheduleConflict(
        day: day,
        start: start,
        end: end,
        adults: List<UserModel>.from(adults),
        pickupLabel: label,
        child: child,
        eventTitle: title.isEmpty ? null : title,
      ));
    }
  }

  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

String dateKeyLike(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Vuxen-krockar + hämtningskonflikter, dedupeade och sorterade.
List<ScheduleConflict> detectAllConflicts({
  required List<UserModel> members,
  required List<QueryDocumentSnapshot> events,
  required List<QueryDocumentSnapshot> shifts,
  required DateTime weekStart,
  int dayCount = 7,
}) {
  final adult = detectAdultConflicts(
    members: members,
    events: events,
    shifts: shifts,
    weekStart: weekStart,
  );
  final pickup = detectPickupConflicts(
    members: members,
    events: events,
    shifts: shifts,
    weekStart: weekStart,
    dayCount: dayCount,
  );
  final all = [...adult, ...pickup]..sort((a, b) => a.start.compareTo(b.start));
  return all;
}
