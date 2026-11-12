import 'package:flutter/material.dart';
import 'quick_add_parser.dart';

/// Only explicit input replaces an existing field. Matches FormularTolkning on Android.
class CalendarInputPatch {
  final String title;
  final DateTime? date;
  final TimeOfDay? time;
  final List<String>? personNames;
  final String? recurrence;
  final String? pictogram;
  const CalendarInputPatch(
    this.title,
    this.date,
    this.time,
    this.personNames,
    this.recurrence,
    this.pictogram,
  );

  factory CalendarInputPatch.fromDraft(QuickAddDraft draft) {
    var title = draft.title;
    var time = draft.time;
    if (time.isEmpty && draft.hasExplicitDate) {
      final match = RegExp(r'^(.*\S)\s+(\d{1,2})$').firstMatch(title);
      final hour = int.tryParse(match?.group(2) ?? '');
      if (hour != null && hour >= 6 && hour <= 22) {
        title = match!.group(1)!;
        time = '${hour.toString().padLeft(2, '0')}:00';
      }
    }
    final parts = time.split(':');
    return CalendarInputPatch(
      title,
      draft.hasExplicitDate ? draft.date : null,
      time.isEmpty
          ? null
          : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      draft.persons.isEmpty ? null : draft.persons.map((m) => m.name).toList(),
      draft.recurrenceType.isEmpty ? null : draft.recurrenceType,
      draft.piktogram == '📅' ? null : draft.piktogram,
    );
  }
}
