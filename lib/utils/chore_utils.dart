import 'date_utils.dart';
import 'person_match.dart';
import 'recurrence.dart';

/// Om sysslan är återkommande (har recurrence-block).
bool choreIsRecurring(Map<String, dynamic> d) =>
    d['isRecurring'] == true && d['recurrence'] is Map;

/// Infaller sysslan på [day]?
///
/// Återkommande → [recurringOccursOnDay].
/// Engångs med `dueDate` → den dagen.
/// Engångs utan `dueDate` → varje dag (befintligt beteende).
bool choreOccursOnDay(Map<String, dynamic> d, DateTime day) {
  if (choreIsRecurring(d)) return recurringOccursOnDay(d, day);
  final raw = d['dueDate'];
  if (raw == null) return true;
  if (raw is String && raw.isEmpty) return true;
  if (raw is String) {
    final parsed = parseDate(raw);
    if (parsed == null) return true;
    return parsed.year == day.year &&
        parsed.month == day.month &&
        parsed.day == day.day;
  }
  return true;
}

/// Är sysslan avklarad på [day]?
///
/// Återkommande → `doneDates` innehåller dateKey(day).
/// Engångs → `isDone == true`.
bool choreDoneOnDay(Map<String, dynamic> d, DateTime day) {
  if (choreIsRecurring(d)) {
    final done = (d['doneDates'] as List?)?.cast<String>() ?? const [];
    return done.contains(dateKey(day));
  }
  return d['isDone'] == true;
}

/// Antal förekomster från recurrence-start t.o.m. [day] (inklusive),
/// eller 0 om dagen inte är en förekomst.
int choreOccurrenceIndex(Map<String, dynamic> d, DateTime day) {
  if (!choreIsRecurring(d)) return 0;
  final rec = d['recurrence'] as Map<String, dynamic>;
  final start = parseDate(rec['startDate'] ?? d['dueDate'] ?? d['date']);
  if (start == null) return 0;
  if (!choreOccursOnDay(d, day)) return 0;
  final days = expandRecurrence(d, start, day);
  return days.isEmpty ? 0 : days.length - 1;
}

/// Dagens ansvariga uid — rotation eller fast `whoUid`.
String? assigneeForDay(Map<String, dynamic> d, DateTime day) {
  final rotation = (d['rotationUids'] as List?)
          ?.whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList() ??
      const <String>[];
  if (rotation.isEmpty) {
    final who = d['whoUid'] as String?;
    if (who != null && who.isNotEmpty) return who;
    return null;
  }
  final idx = choreOccurrenceIndex(d, day);
  return rotation[idx % rotation.length];
}

/// Nästa förekomsts ansvariga uid (efter [day]), eller null.
String? nextAssigneeAfter(Map<String, dynamic> d, DateTime day) {
  final rotation = (d['rotationUids'] as List?)
          ?.whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList() ??
      const <String>[];
  if (rotation.length < 2) return null;
  if (!choreIsRecurring(d)) return null;
  final from = DateTime(day.year, day.month, day.day + 1);
  final to = from.add(const Duration(days: 400));
  final days = expandRecurrence(d, from, to);
  if (days.isEmpty) return null;
  return assigneeForDay(d, days.first);
}

/// Matchar personfilter mot dagens assignee (rotation) eller klassisk tilldelning.
bool choreAssignedToOnDay(
  Map<String, dynamic> d,
  DateTime day, {
  required String uid,
  required String name,
}) {
  final assignee = assigneeForDay(d, day);
  if (assignee != null && assignee.isNotEmpty) {
    return assignee == uid;
  }
  return assignedToPerson(d, uid: uid, name: name);
}

/// Öppen på [day] = infaller och inte avklarad.
bool choreOpenOnDay(Map<String, dynamic> d, DateTime day) =>
    choreOccursOnDay(d, day) && !choreDoneOnDay(d, day);

/// Nästa förekomst för en återkommande syssla efter [fromDay], max [maxDaysAhead] dagar framåt (default 14).
DateTime? nextChoreOccurrence(
  Map<String, dynamic> d,
  DateTime fromDay, {
  int maxDaysAhead = 14,
}) {
  if (!choreIsRecurring(d)) return null;
  final start = DateTime(fromDay.year, fromDay.month, fromDay.day + 1);
  final end = DateTime(fromDay.year, fromDay.month, fromDay.day + maxDaysAhead);
  final days = expandRecurrence(d, start, end);
  return days.isNotEmpty ? days.first : null;
}

/// Formaterar nästa förekomst som `nästa: <veckodag d/M>`, t.ex. "nästa: lördag 12/9".
String formatNextOccurrence(DateTime dt) {
  const days = [
    '',
    'måndag',
    'tisdag',
    'onsdag',
    'torsdag',
    'fredag',
    'lördag',
    'söndag',
  ];
  final dayName = days[dt.weekday];
  return 'nästa: $dayName ${dt.day}/${dt.month}';
}

/// Närmaste kommande lördag efter [from] (strikt efter [from], minst 1 dag framåt).
DateTime nextSaturdayAfter(DateTime from) {
  final d = DateTime(from.year, from.month, from.day);
  var diff = (DateTime.saturday - d.weekday + 7) % 7;
  if (diff == 0) diff = 7;
  return d.add(Duration(days: diff));
}
