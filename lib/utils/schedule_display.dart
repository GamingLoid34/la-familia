import 'package:cloud_firestore/cloud_firestore.dart';

import 'schedule_time_utils.dart';

/// Visningsval för schema-lektioner: klumpa eller visa var och en.
///
/// - Dag-vy: [clumpSchool] = false (alla lektioner med tid)
/// - Vecka / Månad / Agenda: [clumpSchool] = true
List<ScheduleDisplayEntry> buildScheduleDisplay(
  Iterable<QueryDocumentSnapshot> scheduleDocs, {
  required bool clumpSchool,
  String? title,
  String? piktogram,
}) {
  final docs = scheduleDocs.toList();
  if (docs.isEmpty) return const [];

  docs.sort((a, b) {
    final ta = (a.data() as Map)['time'] as String? ?? '99:99';
    final tb = (b.data() as Map)['time'] as String? ?? '99:99';
    return ta.compareTo(tb);
  });

  if (clumpSchool) {
    final maps = docs.map((d) => d.data() as Map<String, dynamic>);
    final span = scheduleTimeSpan(maps);
    return [
      ScheduleClusterEntry(
        docs: docs,
        label: scheduleBlockLabel(maps, title: title, piktogram: piktogram),
        sortKey: span.minStart ?? '00:00',
      ),
    ];
  }

  return [
    for (final doc in docs)
      ScheduleLessonEntry(
        doc: doc,
        sortKey: ((doc.data() as Map)['time'] as String? ?? '00:00'),
      ),
  ];
}

sealed class ScheduleDisplayEntry {
  String get sortKey;
}

class ScheduleClusterEntry extends ScheduleDisplayEntry {
  final List<QueryDocumentSnapshot> docs;
  final String label;
  @override
  final String sortKey;

  ScheduleClusterEntry({
    required this.docs,
    required this.label,
    required this.sortKey,
  });
}

class ScheduleLessonEntry extends ScheduleDisplayEntry {
  final QueryDocumentSnapshot doc;
  @override
  final String sortKey;

  ScheduleLessonEntry({required this.doc, required this.sortKey});
}
