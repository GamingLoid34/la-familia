import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Centrala datum-helpers för La Familia.
///
/// Konvention (ROADMAP Etapp 2): datum lagras som zero-paddade strängar
/// `YYYY-MM-DD` och tider som `HH:mm`. All NY kod ska skriva via [dateKey]
/// och [timeKey]. Läsning via [parseDate]/[parseDateTime] tål både paddade
/// och historiska opaddade värden (`2026-5-3`) samt [Timestamp].

/// Zero-paddad datumnyckel, t.ex. `2026-06-11`.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Zero-paddad tidsnyckel, t.ex. `08:05`.
String timeKey(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// Tolkar `YYYY-M-D`/`YYYY-MM-DD`-sträng eller [Timestamp] till [DateTime].
/// Returnerar null (och loggar) vid ogiltig input.
DateTime? parseDate(dynamic v) {
  try {
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final p = v.split('-');
      if (p.length >= 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    }
  } catch (e, stack) {
    developer.log('parseDate: ogiltigt datum "$v"',
        error: e, stackTrace: stack);
  }
  return null;
}

/// Tolkar ett Firestore-dokuments `date` + ev. `time` (`HH:mm`) till [DateTime].
DateTime? parseDateTime(Map<String, dynamic> d) {
  try {
    final base = parseDate(d['date']);
    if (base == null) return null;
    final timeStr = d['time'] as String? ?? '';
    if (timeStr.isNotEmpty) {
      final tp = timeStr.split(':');
      if (tp.length >= 2) {
        return DateTime(
          base.year,
          base.month,
          base.day,
          int.parse(tp[0]),
          int.parse(tp[1]),
        );
      }
    }
    return base;
  } catch (e, stack) {
    developer.log('parseDateTime: ogiltig tid i $d',
        error: e, stackTrace: stack);
  }
  return null;
}

/// ISO 8601-veckonummer (1–53). Måndag = veckans första dag;
/// vecka 1 är den som innehåller årets första torsdag.
int isoWeekNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  // Torsdagen i samma ISO-vecka bestämmer år/vecka.
  final thursday = d.add(Duration(days: DateTime.thursday - d.weekday));
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  final dayOfYear = thursday.difference(jan1).inDays + 1;
  return ((dayOfYear - 1) ~/ 7) + 1;
}

/// ISO-veckoår för [date] (kan skilja sig från kalenderåret vid årsskifte).
int isoWeekYear(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final thursday = d.add(Duration(days: DateTime.thursday - d.weekday));
  return thursday.year;
}

/// "om 45 min" istället för bara klockslag — NPF: hur länge till, inte när.
String untilLabel(Duration left) {
  if (left.inMinutes < 1) return 'nu!';
  if (left.inMinutes < 60) return 'om ${left.inMinutes} min';
  final h = left.inHours;
  final m = left.inMinutes % 60;
  return m == 0 ? 'om $h h' : 'om $h h $m min';
}
