import 'date_utils.dart';

/// Återkommande aktiviteter (ROADMAP Etapp 4).
///
/// Ett återkommande event sparas EN gång i `planner_events` med:
/// ```
/// isRecurring: true            // för Firestore-queries
/// date: 'YYYY-MM-DD'           // första förekomsten (= startDate)
/// recurrence: {
///   type: 'weekly' | 'biweekly' | 'monthly',
///   startDate: 'YYYY-MM-DD',
///   endDate: 'YYYY-MM-DD' | null,   // null = tills vidare
///   exceptions: ['YYYY-MM-DD', ...] // dagar som hoppats över/redigerats
/// }
/// ```
/// Veckodag (weekly/biweekly) respektive dag-i-månad (monthly) härleds ur
/// startDate. Läsvyer expanderar i klienten via [eventOccursOnDay].

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Heldagars-diff som inte påverkas av sommartid.
int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

/// Infaller det ÅTERKOMMANDE eventet [d] på [day]?
bool recurringOccursOnDay(Map<String, dynamic> d, DateTime day) {
  final rec = d['recurrence'] as Map<String, dynamic>?;
  if (rec == null) return false;
  final start = parseDate(rec['startDate'] ?? d['date']);
  if (start == null) return false;

  final d0 = _dayOnly(day);
  final s0 = _dayOnly(start);
  if (d0.isBefore(s0)) return false;

  final endRaw = rec['endDate'];
  if (endRaw is String && endRaw.isNotEmpty) {
    final end = parseDate(endRaw);
    if (end != null && d0.isAfter(_dayOnly(end))) return false;
  }

  final exceptions = (rec['exceptions'] as List? ?? []).cast<String>();
  if (exceptions.contains(dateKey(d0))) return false;

  switch (rec['type'] as String? ?? '') {
    case 'weekly':
      return d0.weekday == s0.weekday;
    case 'biweekly':
      return d0.weekday == s0.weekday && _daysBetween(s0, d0) % 14 == 0;
    case 'monthly':
      return d0.day == s0.day;
    default:
      return false;
  }
}

/// Infaller eventet [d] (engångs ELLER återkommande) på [day]?
/// Ersätter `date == day`-jämförelser i läsvyerna.
bool eventOccursOnDay(Map<String, dynamic> d, DateTime day) {
  if (d['recurrence'] != null) return recurringOccursOnDay(d, day);
  final date = parseDate(d['date']);
  if (date == null) return false;
  return date.year == day.year &&
      date.month == day.month &&
      date.day == day.day;
}

/// Alla datum i [rangeStart]..[rangeEnd] (inklusive) där det återkommande
/// eventet infaller. Används för notis-schemaläggning.
List<DateTime> expandRecurrence(
  Map<String, dynamic> d,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final out = <DateTime>[];
  var cur = _dayOnly(rangeStart);
  final end = _dayOnly(rangeEnd);
  while (!cur.isAfter(end)) {
    if (recurringOccursOnDay(d, cur)) out.add(cur);
    cur = DateTime(cur.year, cur.month, cur.day + 1);
  }
  return out;
}

/// Kort beskrivning för UI, t.ex. "Varje tisdag" / "Varannan vecka (ons)".
String recurrenceLabel(Map<String, dynamic> d) {
  final rec = d['recurrence'] as Map<String, dynamic>?;
  if (rec == null) return '';
  final start = parseDate(rec['startDate'] ?? d['date']);
  const days = ['', 'måndag', 'tisdag', 'onsdag', 'torsdag',
      'fredag', 'lördag', 'söndag'];
  final dayName = start != null ? days[start.weekday] : '';
  switch (rec['type'] as String? ?? '') {
    case 'weekly':
      return 'Varje $dayName';
    case 'biweekly':
      return 'Varannan $dayName';
    case 'monthly':
      return start != null ? 'Den ${start.day}:e varje månad' : 'Varje månad';
    default:
      return '';
  }
}
