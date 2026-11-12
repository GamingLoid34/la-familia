import '../utils/date_utils.dart';

/// Editable fields only. Source, completion and linked activity remain untouched on edit.
class TaskDraft {
  const TaskDraft({
    required this.title,
    this.dueDate,
    this.dueTime,
    this.showFromDate,
    this.assigneeUid,
    this.aboutUids = const [],
  });
  final String title;
  final DateTime? dueDate;
  final String? dueTime;
  final DateTime? showFromDate;
  final String? assigneeUid;
  final List<String> aboutUids;

  String? validate() {
    if (title.trim().isEmpty) return 'Skriv vad som ska göras.';
    if (title.trim().length > 500) return 'Titeln får vara högst 500 tecken.';
    if (dueTime != null && dueDate == null) {
      return 'Välj ett datum för klockslaget.';
    }
    if (dueTime != null &&
        !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(dueTime!)) {
      return 'Tiden ska skrivas som HH:MM.';
    }
    if (showFromDate != null &&
        dueDate != null &&
        dateKey(showFromDate!).compareTo(dateKey(dueDate!)) > 0) {
      return 'Uppgiften kan inte börja visas efter sin deadline.';
    }
    if (aboutUids.length > 20) return 'Högst 20 personer per uppgift.';
    return null;
  }

  Map<String, dynamic> editableFields() => {
    'title': title.trim(),
    'dueDate': dueDate == null ? null : dateKey(dueDate!),
    'dueTime': dueTime,
    'hasTime': dueTime != null,
    'showFromDate': showFromDate == null ? null : dateKey(showFromDate!),
    'assigneeUid': assigneeUid,
    'aboutUids': aboutUids,
  };

  Map<String, dynamic> newFields(String familyId, String uid) => {
    ...editableFields(),
    'familyId': familyId,
    'createdByUid': uid,
    'status': 'open',
    'sourceNoteId': null,
    'doneAt': null,
  };
}
