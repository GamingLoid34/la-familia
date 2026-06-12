import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'person_match.dart';
import 'recurrence.dart';
import 'schedule_time_utils.dart';

/// Konfliktdetektering (ROADMAP Etapp 9.2): hittar tidsfönster där MER ÄN EN
/// vuxen är upptagen samtidigt — då kan ingen hämta/lämna/vara hemma.

class ScheduleConflict {
  final DateTime day;
  final DateTime start;
  final DateTime end;
  final List<UserModel> adults;

  const ScheduleConflict({
    required this.day,
    required this.start,
    required this.end,
    required this.adults,
  });
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
    // För återkommande ligger 'date' på startdagen — bygg tider mot [day].
    final t = (d['time'] as String?)?.trim() ?? '';
    if (t.isEmpty) continue; // heldags/odaterat räknas inte som blockerande
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
    final date = parseYmdDate(d['date']);
    if (date == null || !sameCalendarDay(date, day)) continue;
    if (!assignedToPerson(d, uid: adult.uid, name: adult.name)) continue;
    final st = parseHmOnDate(d['startTime'] as String?, day);
    final en = parseHmOnDate(d['endTime'] as String?, day);
    if (st == null || en == null || !en.isAfter(st)) continue;
    out.add(_Interval(st, en, adult));
  }

  return out;
}

/// Alla konflikter inom [weekStart] .. [weekStart]+6 dagar, sorterade på tid.
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

    // Parvis överlapp mellan OLIKA vuxna; slå ihop per (start,end)-fönster.
    for (var a = 0; a < all.length; a++) {
      for (var b = a + 1; b < all.length; b++) {
        final x = all[a];
        final y = all[b];
        if (x.adult.uid == y.adult.uid) continue;
        final start = x.start.isAfter(y.start) ? x.start : y.start;
        final end = x.end.isBefore(y.end) ? x.end : y.end;
        if (!end.isAfter(start)) continue;

        // Finns redan en konflikt med samma fönster? Lägg till vuxna i den.
        final existing = conflicts.where((c) =>
            c.start == start && c.end == end).toList();
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
