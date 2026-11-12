import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'date_utils.dart';
import 'recurrence.dart';

String movedOccurrenceId(String seriesId, DateTime original) =>
    'moved_${sha256.convert(utf8.encode('$seriesId|${dateKey(original)}'))}';

bool validMoveTime(String time) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time);
String? validateMove(String day, String time, String end) {
  final parsed = DateTime.tryParse(day);
  if (parsed == null || dateKey(parsed) != day ||
      (time.isNotEmpty && !validMoveTime(time)) ||
      (end.isNotEmpty && (!validMoveTime(end) || time.isEmpty || end.compareTo(time) <= 0))) {
    return 'Ange datum ÅÅÅÅ-MM-DD och tid HH:mm. Sluttiden måste vara senare samma dag.';
  }
  return null;
}

Map<String, dynamic> detachedOccurrence(Map<String, dynamic> source,
    String seriesId, DateTime original, String day, String time, String end, String uid) {
  if (validateMove(day, time, end) != null || uid.isEmpty) throw StateError('Ogiltig flytt');
  if (source['source'] == 'calendar') throw StateError('Ändra importerade tider i källkalendern.');
  if (!recurringOccursOnDay(source, original)) throw StateError('Tillfället har redan ändrats. Öppna kalendern igen.');
  final data = Map<String, dynamic>.from(source);
  for (final key in ['recurrence', 'detachedOccurrences', 'endTime', 'timeMode', 'reactions', 'completedDates']) { data.remove(key); }
  data.addAll({'isRecurring': false, 'date': day, 'time': time, 'source': 'manual',
    'createdByUid': uid, 'createdBy': uid, 'originalSeriesId': seriesId,
    'originalOccurrenceDate': dateKey(original)});
  if (end.isNotEmpty) data['endTime'] = end;
  if (time.isEmpty) data['timeMode'] = source['timeMode'] ?? 'undecided';
  if (source['lessonPrep'] is Map) {
    final prep = source['lessonPrep'] as Map;
    data['lessonPrep'] = {'text': prep['text'], 'doneDates':
      (prep['doneDates'] as List? ?? []).contains(dateKey(original)) ? [day] : <String>[]};
  }
  return data;
}
