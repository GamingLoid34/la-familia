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

/// Absolut tidsintervall för ett arbetspass (nattpass → end nästa dygn).
({DateTime start, DateTime end})? shiftInterval(Map<String, dynamic> shift) {
  final day = parseYmdDate(shift['date']);
  if (day == null) return null;
  final startField = (shift['startTime'] ?? shift['start']) as String?;
  final endField = (shift['endTime'] ?? shift['end']) as String?;
  final st = parseHmOnDate(startField, day);
  if (st == null) return null;
  var en = parseHmOnDate(endField, day);
  if (en == null) return null;
  if (!en.isAfter(st)) {
    en = en.add(const Duration(days: 1));
  }
  return (start: st, end: en);
}

/// True om arbetspasset spänner över midnatt (startar ett dygn och slutar nästa).
bool isNightShift(Map<String, dynamic> shift) {
  final interval = shiftInterval(shift);
  if (interval == null) return false;
  return interval.end.day != interval.start.day;
}

/// True om passet overlappar [day]s kalenderdygn (inkl. nattpass fre→lör).
bool shiftTouchesDay(Map<String, dynamic> shift, DateTime day) {
  final interval = shiftInterval(shift);
  if (interval == null) return false;
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  return interval.start.isBefore(dayEnd) && interval.end.isAfter(dayStart);
}

bool workShiftIsActiveNow(Map<String, dynamic> d, DateTime now) {
  final interval = shiftInterval(d);
  if (interval == null) return false;
  return !now.isBefore(interval.start) && now.isBefore(interval.end);
}

/// Min start–max slut för schema-lektioner (samma logik som veckogrid).
({String? minStart, String? maxEnd}) scheduleTimeSpan(
  Iterable<Map<String, dynamic>> docs,
) {
  String? minStart;
  String? maxEnd;
  for (final d in docs) {
    final t = (d['time'] as String? ?? '').trim();
    if (t.isEmpty) continue;
    final endRaw = (d['endTime'] as String? ?? '').trim();
    final end = endRaw.isNotEmpty ? endRaw : t;
    if (minStart == null || t.compareTo(minStart) < 0) minStart = t;
    if (maxEnd == null || end.compareTo(maxEnd) > 0) maxEnd = end;
  }
  return (minStart: minStart, maxEnd: maxEnd);
}

/// Härleder schemaetikett ('Skola', 'Rehab', 'Jobb', 'Schema') från ett dokument eller en map.
String schemaLabelFor(dynamic docOrMap) {
  Map<String, dynamic> d;
  if (docOrMap is DocumentSnapshot) {
    d = (docOrMap.data() as Map<String, dynamic>?) ?? const {};
  } else if (docOrMap is Map<String, dynamic>) {
    d = docOrMap;
  } else if (docOrMap is Map) {
    d = Map<String, dynamic>.from(docOrMap);
  } else {
    return 'Schema';
  }

  final explicitLabel = (d['schemaLabel'] as String?)?.trim();
  if (explicitLabel != null && explicitLabel.isNotEmpty) {
    return explicitLabel;
  }

  final pik = (d['piktogram'] as String?)?.trim();
  if (pik == '🏥') return 'Rehab';
  if (pik == '💼') return 'Jobb';
  if (pik == '🏫') return 'Skola';
  if (pik == '📋') return 'Schema';

  final calName = ((d['calendarName'] ?? d['title'] ?? '') as String).toLowerCase();
  if (calName.contains('rehab') || calName.contains('klinik')) return 'Rehab';

  return 'Skola';
}

/// Härleder schemapiktogram ('🏫', '🏥', '💼', '📋') från ett dokument eller en map.
String schemaPiktogramFor(dynamic docOrMap) {
  Map<String, dynamic> d;
  if (docOrMap is DocumentSnapshot) {
    d = (docOrMap.data() as Map<String, dynamic>?) ?? const {};
  } else if (docOrMap is Map<String, dynamic>) {
    d = docOrMap;
  } else if (docOrMap is Map) {
    d = Map<String, dynamic>.from(docOrMap);
  } else {
    return '🏫';
  }

  final explicitPik = (d['piktogram'] as String?)?.trim();
  if (explicitPik != null && explicitPik.isNotEmpty) {
    return explicitPik;
  }

  final label = (d['schemaLabel'] as String?)?.trim().toLowerCase();
  if (label == 'rehab') return '🏥';
  if (label == 'jobb') return '💼';
  if (label == 'skola') return '🏫';
  if (label == 'schema' || label == 'annat') return '📋';

  final calName = ((d['calendarName'] ?? d['title'] ?? '') as String).toLowerCase();
  if (calName.contains('rehab') || calName.contains('klinik')) return '🏥';

  return '🏫';
}

/// Etikett t.ex. `🏥 Rehab 08:45–14:00` eller `🏫 Skola · Céline 08:45–14:00`.
String scheduleBlockLabel(
  Iterable<Map<String, dynamic>> docs, {
  String? title,
  String? piktogram,
}) {
  final docsList = docs.toList();
  final first = docsList.isNotEmpty ? docsList.first : const <String, dynamic>{};
  final pik = piktogram ?? (docsList.isNotEmpty ? schemaPiktogramFor(first) : '🏫');
  final resolvedTitle = title ?? (docsList.isNotEmpty ? schemaLabelFor(first) : 'Skola');

  final span = scheduleTimeSpan(docs);
  if (span.minStart != null && span.maxEnd != null) {
    return '$pik $resolvedTitle ${span.minStart}–${span.maxEnd}';
  }
  return '$pik $resolvedTitle';
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

/// Reservregel för blockscheman: fyller i saknad `endTime` med nästa händelses
/// `time` samma dag (dagens sista lämnas orörd, befintliga endTime rörs
/// aldrig). Muterar mapparna i [events] (nycklar: 'date', 'time', 'endTime').
/// Returnerar antalet ifyllda sluttider.
int inferBlockEndTimes(List<Map<String, dynamic>> events) {
  int count = 0;
  final byDate = <String, List<Map<String, dynamic>>>{};
  for (final ev in events) {
    final date = ev['date'] as String?;
    if (date != null && date.isNotEmpty) {
      byDate.putIfAbsent(date, () => []).add(ev);
    }
  }
  for (final dayEvents in byDate.values) {
    dayEvents.sort((a, b) {
      final ta = (a['time'] as String? ?? '');
      final tb = (b['time'] as String? ?? '');
      return ta.compareTo(tb);
    });
    for (int i = 0; i < dayEvents.length - 1; i++) {
      final cur = dayEvents[i];
      final next = dayEvents[i + 1];
      final curEnd = cur['endTime'] as String?;
      final curTime = (cur['time'] as String? ?? '').trim();
      final nextTime = (next['time'] as String? ?? '').trim();
      if ((curEnd == null || curEnd.trim().isEmpty) &&
          nextTime.compareTo(curTime) > 0) {
        cur['endTime'] = nextTime;
        count++;
      }
    }
  }
  return count;
}

/// Läsbar längd mellan två 'HH:mm' samma dag: '2 t 30 min', '45 min', '2 t'.
/// Tom sträng om ogiltig input eller om slutet inte är efter starten.
String durationLabelHm(String startHm, String endHm) {
  final baseDay = DateTime(2000, 1, 1);
  final start = parseHmOnDate(startHm, baseDay);
  final end = parseHmOnDate(endHm, baseDay);
  if (start == null || end == null) return '';
  if (!end.isAfter(start)) return '';

  final diff = end.difference(start);
  final totalMinutes = diff.inMinutes;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;

  if (h > 0 && m > 0) return '$h t $m min';
  if (h > 0) return '$h t';
  if (m > 0) return '$m min';
  return '';
}
