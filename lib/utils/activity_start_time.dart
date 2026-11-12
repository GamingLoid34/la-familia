import 'package:flutter/material.dart';

/// Starttiden i AddEventSheet, med läget "ingen tid".
///
/// En aktivitet utan klockslag (`time: ""`) fick förut det klockslag som råkade
/// vara när formuläret öppnades, eftersom starttiden började som
/// `TimeOfDay.now()` och alltid sparades. Nu förblir den tidlös tills någon
/// själv väljer en starttid. Samma regler som Android-appen (bygge 1, beslut
/// 2026-09-23): utan tid sparas `time: ""` och ingen `endTime`; `timeMode`
/// (heldag / tid inte bestämd, skrivs av Android) lämnas orört. När ett
/// klockslag väljs tas `timeMode` bort.
@immutable
class ActivityStartTime {
  /// Sant när aktiviteten inte har något klockslag.
  final bool untimed;

  /// Starttiden. Används bara när [untimed] är falskt.
  final TimeOfDay start;

  const ActivityStartTime({required this.untimed, required this.start});

  /// Ny aktivitet: ett klockslag, som förut.
  const ActivityStartTime.timed(this.start) : untimed = false;

  /// Befintligt dokument: tidlöst om `time` är tomt. [fallback] är tiden
  /// väljaren öppnas med om någon väljer ett klockslag.
  factory ActivityStartTime.fromDoc(
    Map<String, dynamic> doc, {
    required TimeOfDay fallback,
  }) {
    final parts = ((doc['time'] as String?) ?? '').trim().split(':');
    if (parts.length < 2) {
      return ActivityStartTime(untimed: true, start: fallback);
    }
    return ActivityStartTime(
      untimed: false,
      start: TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 0,
        minute: int.tryParse(parts[1]) ?? 0,
      ),
    );
  }

  /// Någon valde ett klockslag i väljaren.
  ActivityStartTime picked(TimeOfDay t) =>
      ActivityStartTime(untimed: false, start: t);

  /// Texten på starttidsknappen. Visar aldrig ett klockslag som inte sparas.
  String label(String Function(TimeOfDay) format) =>
      untimed ? 'Starttid: Ingen tid' : 'Starttid: ${format(start)}';
}

/// Tidsfälten som sparas. [removals] görs om till `FieldValue.delete()` av
/// anroparen, så att den här filen går att testa utan Firestore.
@immutable
class ActivityTimeFields {
  final Map<String, String> fields;
  final Set<String> removals;
  const ActivityTimeFields(this.fields, this.removals);
}

String _hm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `time`, `endTime` och `timeMode` för en sparning från AddEventSheet.
ActivityTimeFields activityTimeFields({
  required ActivityStartTime start,
  required TimeOfDay? end,
  required bool editing,
}) {
  final fields = <String, String>{};
  final removals = <String>{};

  if (start.untimed) {
    fields['time'] = '';
    // Ingen sluttid utan starttid. Fältet tas bort, som när sluttiden rensas.
    if (editing) removals.add('endTime');
    // timeMode rörs inte: update() behåller det.
  } else {
    fields['time'] = _hm(start.start);
    if (end != null) {
      fields['endTime'] = _hm(end);
    } else if (editing) {
      removals.add('endTime');
    }
    // Ett klockslag gäller före heldag / tid inte bestämd.
    if (editing) removals.add('timeMode');
  }
  return ActivityTimeFields(fields, removals);
}
