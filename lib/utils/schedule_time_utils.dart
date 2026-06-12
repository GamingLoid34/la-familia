import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_utils.dart';

/// Delegerar till den centrala [parseDate] (utils/date_utils.dart).
DateTime? parseYmdDate(dynamic v) => parseDate(v);

DateTime? parseHmOnDate(String? hm, DateTime day) {
  if (hm == null || hm.isEmpty) return null;
  final p = hm.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0].trim());
  final m = int.tryParse(p[1].trim());
  if (h == null || m == null) return null;
  return DateTime(day.year, day.month, day.day, h, m);
}

bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Kräver att `time` är satt — undviker falska ”hela dagen”-block vid status.
DateTime? plannerTimedStart(Map<String, dynamic> d) {
  final day = parseYmdDate(d['date']);
  if (day == null) return null;
  final t = d['time'] as String?;
  if (t == null || t.trim().isEmpty) return null;
  return parseHmOnDate(t, day);
}

/// Slut: `endTime` (HH:mm) samma dag om satt, annars [defaultSpan] efter start.
DateTime? plannerTimedEnd(
  Map<String, dynamic> d, {
  Duration defaultSpan = const Duration(hours: 1),
}) {
  final start = plannerTimedStart(d);
  if (start == null) return null;
  final endStr = d['endTime'] as String?;
  if (endStr != null && endStr.isNotEmpty) {
    final day = DateTime(start.year, start.month, start.day);
    final e = parseHmOnDate(endStr, day);
    if (e != null && !e.isBefore(start)) return e;
  }
  return start.add(defaultSpan);
}

bool plannerTimedEventIsActiveNow(Map<String, dynamic> d, DateTime now) {
  final s = plannerTimedStart(d);
  final e = plannerTimedEnd(d);
  if (s == null || e == null) return false;
  return !now.isBefore(s) && now.isBefore(e);
}

bool workShiftIsActiveNow(Map<String, dynamic> d, DateTime now) {
  final day = parseYmdDate(d['date']);
  if (day == null || !sameCalendarDay(day, now)) return false;
  final st = parseHmOnDate(d['startTime'] as String?, day);
  final en = parseHmOnDate(d['endTime'] as String?, day);
  if (st == null || en == null) return false;
  return !now.isBefore(st) && now.isBefore(en);
}

bool busySessionIsActiveNow(Map<String, dynamic> d, DateTime now) {
  final start = (d['startAt'] as Timestamp?)?.toDate();
  final end = (d['endAt'] as Timestamp?)?.toDate();
  if (start == null || end == null) return false;
  return !now.isBefore(start) && now.isBefore(end);
}

String timeSortKey(Map<String, dynamic> d, {bool isWork = false}) {
  if (isWork) {
    return (d['startTime'] as String? ?? '00:00').padLeft(5, '0');
  }
  return (d['time'] as String? ?? '00:00').padLeft(5, '0');
}
