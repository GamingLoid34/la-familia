import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/date_utils.dart';

/// Fri uppgift för familjens vuxna (`tasks/{id}`), separat från sysslor.
///
/// Speglar Android-appens `TaskModel`. Firestore-reglerna (`firestore.rules`,
/// `match /tasks`) kräver att varje skrivning innehåller alla nycklar i
/// [toFirestoreMap] — därför skrivs alltid hela dokumentet med `set`.
/// Bara förälder/admin får läsa och skriva; barn och ungdomar prenumererar
/// aldrig, men kan stå i [aboutUids] som personer uppgiften handlar om.
class TaskModel {
  static const statusOpen = 'open';
  static const statusDone = 'done';
  static const maxTitleLength = 500;
  static const maxAboutUids = 20;

  final String id;
  final String familyId;
  final String title;

  /// Deadline "Senast", `YYYY-MM-DD`.
  final String? dueDate;

  /// `HH:MM`, bara när [hasTime].
  final String? dueTime;
  final bool hasTime;

  /// Uppgiften ligger tyst på Hem före den här dagen.
  final String? showFromDate;

  /// Ansvarig vuxen. `null` = vem som helst.
  final String? assigneeUid;

  /// Familjemedlemmar som uppgiften handlar om.
  final List<String> aboutUids;
  final String status;
  final String? sourceNoteId;

  /// Koppling till en förekomst av en aktivitet (`planner_events`).
  /// Båda eller ingen — reglerna avvisar annars dokumentet.
  final String? eventId;
  final String? occurrenceDate;
  final String createdByUid;
  final DateTime? doneAt;

  const TaskModel({
    this.id = '',
    required this.familyId,
    required this.title,
    this.dueDate,
    this.dueTime,
    this.hasTime = false,
    this.showFromDate,
    this.assigneeUid,
    this.aboutUids = const [],
    this.status = statusOpen,
    this.sourceNoteId,
    this.eventId,
    this.occurrenceDate,
    this.createdByUid = '',
    this.doneAt,
  });

  bool get isDone => status == statusDone;

  /// Försenad: öppen och deadline före [today] (`YYYY-MM-DD`, strängjämförelse).
  bool isOverdue(String today) =>
      !isDone && dueDate != null && dueDate!.compareTo(today) < 0;

  static String? _blankToNull(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  factory TaskModel.fromMap(String id, Map<String, dynamic> d) {
    final status = _blankToNull(d['status']) ?? statusOpen;
    final done = d['doneAt'];
    return TaskModel(
      id: id,
      familyId: d['familyId'] as String? ?? '',
      title: d['title'] as String? ?? '',
      dueDate: _blankToNull(d['dueDate']),
      dueTime: _blankToNull(d['dueTime']),
      hasTime: d['hasTime'] == true,
      showFromDate: _blankToNull(d['showFromDate']),
      assigneeUid: _blankToNull(d['assigneeUid']),
      aboutUids: (d['aboutUids'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      status: status,
      sourceNoteId: _blankToNull(d['sourceNoteId']),
      eventId: _blankToNull(d['eventId']),
      occurrenceDate: _blankToNull(d['occurrenceDate']),
      createdByUid: d['createdByUid'] as String? ?? '',
      doneAt: done is Timestamp ? done.toDate() : null,
    );
  }

  /// Hela dokumentet som reglernas `validTask` kräver. `eventId` och
  /// `occurrenceDate` utelämnas helt när de saknas (inte `null`).
  Map<String, dynamic> toFirestoreMap() => {
        'familyId': familyId,
        'title': title,
        'dueDate': dueDate,
        'dueTime': hasTime ? dueTime : null,
        'hasTime': hasTime,
        'showFromDate': showFromDate,
        'assigneeUid': assigneeUid,
        'aboutUids': aboutUids,
        'status': status,
        'sourceNoteId': sourceNoteId,
        'createdByUid': createdByUid,
        'doneAt': doneAt == null ? null : Timestamp.fromDate(doneAt!),
        if (eventId != null && occurrenceDate != null) ...{
          'eventId': eventId,
          'occurrenceDate': occurrenceDate,
        },
      };

  TaskModel copyWith({
    String? status,
    DateTime? doneAt,
    bool clearDoneAt = false,
    String? dueDate,
  }) =>
      TaskModel(
        id: id,
        familyId: familyId,
        title: title,
        dueDate: dueDate ?? this.dueDate,
        dueTime: dueTime,
        hasTime: hasTime,
        showFromDate: showFromDate,
        assigneeUid: assigneeUid,
        aboutUids: aboutUids,
        status: status ?? this.status,
        sourceNoteId: sourceNoteId,
        eventId: eventId,
        occurrenceDate: occurrenceDate,
        createdByUid: createdByUid,
        doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
      );

  /// Öppna först efter deadline (utan deadline sist), sedan titel.
  static int compareOpen(TaskModel a, TaskModel b) {
    final c = (a.dueDate ?? '9999-99-99').compareTo(b.dueDate ?? '9999-99-99');
    return c != 0 ? c : a.title.compareTo(b.title);
  }

  /// Klara: senast klarmarkerade först.
  static int compareDone(TaskModel a, TaskModel b) {
    final ad = a.doneAt?.millisecondsSinceEpoch ?? 0;
    final bd = b.doneAt?.millisecondsSinceEpoch ?? 0;
    return bd.compareTo(ad);
  }
}

/// Formulärets innehåll för en uppgift (Androids `TaskDraft`).
class TaskDraft {
  static final _timePattern = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');

  final String title;
  final DateTime? dueDate;
  final String? dueTime;
  final DateTime? showFromDate;
  final String? assigneeUid;
  final List<String> aboutUids;

  const TaskDraft({
    this.title = '',
    this.dueDate,
    this.dueTime,
    this.showFromDate,
    this.assigneeUid,
    this.aboutUids = const [],
  });

  bool get hasTime => dueTime != null;

  /// Samma fall som Firestore-reglerna avvisar, med begripliga texter.
  String? validate() {
    if (title.trim().isEmpty) return 'Skriv vad som ska göras.';
    if (title.trim().length > TaskModel.maxTitleLength) {
      return 'Titeln får vara högst ${TaskModel.maxTitleLength} tecken.';
    }
    if (dueTime != null && dueDate == null) {
      return 'Välj ett datum för klockslaget.';
    }
    if (dueTime != null && !_timePattern.hasMatch(dueTime!)) {
      return 'Tiden ska skrivas som HH:MM.';
    }
    if (showFromDate != null &&
        dueDate != null &&
        _day(showFromDate!).isAfter(_day(dueDate!))) {
      return 'Uppgiften kan inte börja visas efter sin deadline.';
    }
    if (aboutUids.length > TaskModel.maxAboutUids) {
      return 'Högst ${TaskModel.maxAboutUids} personer per uppgift.';
    }
    return null;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Titeln på en rad, trimmad.
  static String singleLineTitle(String t) =>
      t.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();

  /// Bygger dokumentet. Vid redigering bevaras status, klartid, skapare
  /// och källkopplingar från [existing].
  TaskModel toTask({
    required String familyId,
    required String myUid,
    TaskModel? existing,
  }) {
    final existingCreator = existing?.createdByUid ?? '';
    return TaskModel(
      id: existing?.id ?? '',
      familyId: familyId,
      // Reglernas `title.matches('.*[^\\s].*')` avvisar radbrytningar, så de
      // blir mellanslag.
      title: singleLineTitle(title),
      dueDate: dueDate == null ? null : dateKey(dueDate!),
      dueTime: dueDate != null ? dueTime : null,
      hasTime: hasTime && dueDate != null,
      showFromDate: showFromDate == null ? null : dateKey(showFromDate!),
      assigneeUid: assigneeUid,
      aboutUids: aboutUids,
      status: existing?.status ?? TaskModel.statusOpen,
      sourceNoteId: existing?.sourceNoteId,
      eventId: existing?.eventId,
      occurrenceDate: existing?.occurrenceDate,
      createdByUid: existingCreator.trim().isNotEmpty ? existingCreator : myUid,
      doneAt: existing?.doneAt,
    );
  }

  factory TaskDraft.from(TaskModel t) => TaskDraft(
        title: t.title,
        dueDate: parseDate(t.dueDate),
        dueTime: t.hasTime ? t.dueTime : null,
        showFromDate: parseDate(t.showFromDate),
        assigneeUid: t.assigneeUid,
        aboutUids: t.aboutUids,
      );

  TaskDraft copyWith({
    String? title,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? dueTime,
    bool clearDueTime = false,
    DateTime? showFromDate,
    bool clearShowFromDate = false,
    String? assigneeUid,
    bool clearAssignee = false,
  }) =>
      TaskDraft(
        title: title ?? this.title,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
        showFromDate:
            clearShowFromDate ? null : (showFromDate ?? this.showFromDate),
        assigneeUid: clearAssignee ? null : (assigneeUid ?? this.assigneeUid),
        aboutUids: aboutUids,
      );
}
