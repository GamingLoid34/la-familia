import 'package:cloud_firestore/cloud_firestore.dart';
import 'date_utils.dart';
import 'recurrence.dart';

/// Delad per-dag-dataström och dedup-logik (FAS D2).
/// Används av både MemberDaySheet och MinDagPage.

/// Slår ihop och dedubblar dagsspecifika och återkommande händelser för ett givet datum.
List<QueryDocumentSnapshot> mergeAndDedupDayEvents({
  required List<QueryDocumentSnapshot> dateEvents,
  required List<QueryDocumentSnapshot> recurringEvents,
  required DateTime day,
}) {
  final target = DateTime(day.year, day.month, day.day);
  final seen = <String>{};
  final merged = <QueryDocumentSnapshot>[];

  for (final doc in dateEvents) {
    if (seen.add(doc.id)) {
      merged.add(doc);
    }
  }

  for (final doc in recurringEvents) {
    if (seen.contains(doc.id)) continue;
    final d = doc.data() as Map<String, dynamic>;
    if (recurringOccursOnDay(d, target)) {
      seen.add(doc.id);
      merged.add(doc);
    }
  }

  return merged;
}

/// Firestore-stream för specifika händelser på ett givet datum.
Stream<QuerySnapshot> dayEventsStream({
  required String familyId,
  required DateTime day,
}) {
  if (familyId.isEmpty) return const Stream.empty();
  final key = dateKey(DateTime(day.year, day.month, day.day));
  return FirebaseFirestore.instance
      .collection('planner_events')
      .where('familyId', isEqualTo: familyId)
      .where('date', isEqualTo: key)
      .snapshots();
}

/// Formaterar nedräkning i minuter till användarvänlig svensk text (FAS 4).
/// Ex: "om 1 min", "om 23 min", "om 1 timme", "om 2 timmar".
String formatCountdownMinutes(int diffMinutes) {
  if (diffMinutes <= 1) {
    return 'om 1 min';
  } else if (diffMinutes < 60) {
    return 'om $diffMinutes min';
  } else if (diffMinutes < 120) {
    return 'om 1 timme';
  } else {
    final hours = (diffMinutes / 60).round();
    return 'om $hours timmar';
  }
}
