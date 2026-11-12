import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Inkorgens anteckning (`notes/{id}`), speglar Android-appens `NoteModel`.
///
/// Inte samma sak som `family_notes` (Hem-lapparna) — blanda inte ihop dem.
/// Originaltexten är oföränderlig: en ändring skapar en ny anteckning och
/// mjukraderar den gamla (se `NoteService.editNote`). Klienten skriver bara
/// `status: 'saved'`; servern (`functions/note_inbox.js`) äger tolkningen.
class NoteModel {
  static const visibilityPrivate = 'private';
  static const visibilityFamily = 'family';

  static const statusSaved = 'saved';
  static const statusInterpreting = 'interpreting';
  static const statusNeedsReview = 'needs_review';
  static const statusFailed = 'failed';
  static const statusConfirmed = 'confirmed';
  static const statusDismissed = 'dismissed';

  /// En tolkning som stått på `interpreting` längre än så räknas som fast.
  static const stuckAfter = Duration(minutes: 5);

  final String id;
  final String familyId;
  final String ownerUid;
  final String visibility;
  final String text;
  final String? contentHash;
  final String status;
  final String? requestId;
  final List<String> aboutUids;
  final List<NoteLink> linkedIds;
  final NoteInterpretation? interpretation;
  final String? validFrom;
  final String? validTo;
  final DateTime? deletedAt;
  final String createdByUid;
  final DateTime? createdAt;
  final String? interpretationError;
  final DateTime? interpretingSince;
  final DateTime? confirmedAt;

  const NoteModel({
    this.id = '',
    this.familyId = '',
    this.ownerUid = '',
    this.visibility = visibilityFamily,
    this.text = '',
    this.contentHash,
    this.status = statusSaved,
    this.requestId,
    this.aboutUids = const [],
    this.linkedIds = const [],
    this.interpretation,
    this.validFrom,
    this.validTo,
    this.deletedAt,
    this.createdByUid = '',
    this.createdAt,
    this.interpretationError,
    this.interpretingSince,
    this.confirmedAt,
  });

  bool get isPrivate => visibility == visibilityPrivate;
  bool get isDeleted => deletedAt != null;
  bool get needsReview => status == statusNeedsReview && !isDeleted;
  bool get failed => status == statusFailed && !isDeleted;
  bool get isBusy => status == statusInterpreting;

  bool isStuck([DateTime? now]) {
    if (status != statusInterpreting) return false;
    final since = interpretingSince;
    if (since == null) return false;
    return (now ?? DateTime.now()).difference(since) > stuckAfter;
  }

  bool isReadableBy(String uid) => !isPrivate || ownerUid == uid;

  /// Gäller anteckningen dagen [day] (`YYYY-MM-DD`)?
  bool coversDay(String day) {
    if (isDeleted) return false;
    if (validFrom != null && day.compareTo(validFrom!) < 0) return false;
    if (validTo != null && day.compareTo(validTo!) > 0) return false;
    return true;
  }

  /// Första raden, högst [max] tecken — rubrik i listor.
  String firstLine({int max = 80, String fallback = 'Anteckning'}) {
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t.length > max ? t.substring(0, max) : t;
    }
    return fallback;
  }

  static String? _blank(Object? v) {
    if (v is! String) return null;
    return v.trim().isEmpty ? null : v;
  }

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  factory NoteModel.fromMap(String id, Map<String, dynamic> d) {
    final links = <NoteLink>[];
    for (final raw in (d['linkedIds'] as List? ?? const [])) {
      final l = NoteLink.fromAny(raw);
      if (l != null) links.add(l);
    }
    final interp = d['interpretation'];
    return NoteModel(
      id: id,
      familyId: d['familyId'] as String? ?? '',
      ownerUid: d['ownerUid'] as String? ?? '',
      visibility: _blank(d['visibility']) ?? visibilityFamily,
      text: d['text'] as String? ?? '',
      contentHash: _blank(d['contentHash']),
      status: _blank(d['status']) ?? statusSaved,
      requestId: _blank(d['requestId']),
      aboutUids: (d['aboutUids'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      linkedIds: links,
      interpretation: interp is Map
          ? NoteInterpretation.fromMap(Map<String, dynamic>.from(interp))
          : null,
      validFrom: _blank(d['validFrom']),
      validTo: _blank(d['validTo']),
      deletedAt: _date(d['deletedAt']),
      createdByUid: d['createdByUid'] as String? ?? '',
      createdAt: _date(d['createdAt']),
      interpretationError: _blank(d['interpretationError']),
      interpretingSince: _date(d['interpretingSince']),
      confirmedAt: _date(d['confirmedAt']),
    );
  }

  factory NoteModel.fromDoc(DocumentSnapshot doc) => NoteModel.fromMap(
      doc.id, (doc.data() as Map<String, dynamic>?) ?? const {});
}

class NoteInterpretation {
  final int revision;
  final List<NoteAction> actions;
  final String? question;
  final String? model;
  final DateTime? interpretedAt;

  const NoteInterpretation({
    this.revision = 0,
    this.actions = const [],
    this.question,
    this.model,
    this.interpretedAt,
  });

  List<NoteAction> get pendingActions =>
      actions.where((a) => a.isPending).toList();

  factory NoteInterpretation.fromMap(Map<String, dynamic> d) {
    final actions = <NoteAction>[];
    for (final raw in (d['actions'] as List? ?? const [])) {
      if (raw is Map) {
        final a = NoteAction.fromMap(Map<String, dynamic>.from(raw));
        if (a != null) actions.add(a);
      }
    }
    final rev = d['revision'];
    final q = d['question'];
    final at = d['interpretedAt'];
    return NoteInterpretation(
      revision: rev is num ? rev.toInt() : 0,
      actions: actions,
      question: q is String && q.trim().isNotEmpty ? q : null,
      model: d['model'] as String?,
      interpretedAt: at is Timestamp ? at.toDate() : null,
    );
  }
}

/// Ett förslag ur tolkningen. Id:t är stabilt mellan omtolkningar av samma
/// förslag, så servern känner igen redan sparade (`alreadyDone`).
class NoteAction {
  static const typeCreateEvent = 'create_event';
  static const typeAddChecklistItem = 'add_checklist_item';
  static const typeAddException = 'add_exception';
  static const typeCreateTask = 'create_task';
  static const typeInfo = 'info';

  final String id;
  final String type;
  final String title;
  final String? summary;
  final Map<String, dynamic> payload;
  final String status;
  final String? blockedReason;

  const NoteAction({
    required this.id,
    required this.type,
    this.title = '',
    this.summary,
    this.payload = const {},
    this.status = 'pending',
    this.blockedReason,
  });

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isBlocked => blockedReason != null;

  static NoteAction? fromMap(Map<String, dynamic> d) {
    final id = d['id'];
    final type = d['type'];
    if (id is! String || id.isEmpty || type is! String || type.isEmpty) {
      return null;
    }
    final p = d['payload'];
    final s = d['summary'];
    final b = d['blockedReason'];
    return NoteAction(
      id: id,
      type: type,
      title: d['title'] as String? ?? '',
      summary: s is String && s.trim().isNotEmpty ? s : null,
      payload: p is Map ? Map<String, dynamic>.from(p) : const {},
      status: (d['status'] as String?)?.trim().isNotEmpty == true
          ? d['status'] as String
          : 'pending',
      blockedReason: b is String && b.trim().isNotEmpty ? b : null,
    );
  }

  /// Symbol per typ, som i Androids ReviewCard.
  String get typeIcon {
    switch (type) {
      case typeCreateEvent:
        return '📅';
      case typeCreateTask:
        return '📌';
      case typeAddChecklistItem:
        return '☐';
      case typeAddException:
        return '🚫';
      case typeInfo:
        return '💬';
      default:
        return '•';
    }
  }
}

/// Vad servern skapade ur anteckningen (`linkedIds`).
class NoteLink {
  final String actionId;
  final String type;
  final String targetId;
  final String? rowId;
  final String? occurrenceDate;

  const NoteLink({
    required this.actionId,
    required this.type,
    required this.targetId,
    this.rowId,
    this.occurrenceDate,
  });

  static NoteLink? fromAny(Object? raw) {
    if (raw is! Map) return null;
    final target = raw['targetId'];
    if (target is! String || target.isEmpty) return null;
    return NoteLink(
      actionId: raw['actionId'] as String? ?? '',
      type: raw['type'] as String? ?? '',
      targetId: target,
      rowId: raw['rowId'] as String?,
      occurrenceDate: raw['occurrenceDate'] as String?,
    );
  }
}

/// Statusövergångar (Androids `NoteStatusMachine`).
class NoteStatusMachine {
  NoteStatusMachine._();

  static bool canRequestInterpretation(NoteModel note, [DateTime? now]) =>
      !note.isDeleted &&
      (note.status != NoteModel.statusInterpreting || note.isStuck(now));

  static String? requestBlockedReason(NoteModel note, [DateTime? now]) {
    if (note.isDeleted) return 'Anteckningen är borttagen.';
    if (note.status == NoteModel.statusInterpreting && !note.isStuck(now)) {
      return 'Tolkningen pågår redan.';
    }
    return null;
  }

  static bool isCurrentRevision(NoteModel note, int confirmedRevision) =>
      note.interpretation?.revision == confirmedRevision;
}

/// Dubblettnyckel: SHA-256 av normaliserad text (Androids `NoteContentHash`).
///
/// Måste ge exakt samma hash som Android-appen, annars känns en text som
/// klistrats in i den andra appen inte igen. Kotlins `trim()` tar bort tecken
/// där `Char.isWhitespace()` är sant, medan `Regex("\\s+")` på JVM bara
/// matchar ASCII-blanktecken — båda återskapas exakt nedan.
class NoteContentHash {
  NoteContentHash._();

  static final _asciiWhitespace = RegExp(r'[ \t\n\x0B\f\r]+');

  /// Kotlins `Char.isWhitespace()`: Unicode Zs/Zl/Zp samt \t–\r och 0x1C–0x1F.
  static bool _kotlinWhitespace(int c) =>
      (c >= 0x09 && c <= 0x0D) ||
      (c >= 0x1C && c <= 0x20) ||
      c == 0xA0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200A) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202F ||
      c == 0x205F ||
      c == 0x3000;

  static String _kotlinTrim(String s) {
    var start = 0;
    var end = s.length;
    while (start < end && _kotlinWhitespace(s.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _kotlinWhitespace(s.codeUnitAt(end - 1))) {
      end--;
    }
    return s.substring(start, end);
  }

  static String normalize(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => _kotlinTrim(line).replaceAll(_asciiWhitespace, ' '))
      .join('\n')
      .split('\n')
      .where((l) => l.isNotEmpty)
      .join('\n')
      .toLowerCase();

  /// Gemena hexadecimaler. Tom text ger null.
  static String? of(String text) {
    final n = normalize(text);
    if (n.isEmpty) return null;
    return sha256.convert(utf8.encode(n)).toString();
  }
}

/// Androids `NoteEdit`: en oförändrad anteckning ska inte skapa en ny kopia.
class NoteEdit {
  NoteEdit._();

  static bool isUnchanged(
    NoteModel note, {
    required String text,
    required bool isPrivate,
    required List<String> aboutUids,
  }) =>
      text.trim() == note.text.trim() &&
      isPrivate == note.isPrivate &&
      aboutUids.toSet().length == note.aboutUids.toSet().length &&
      aboutUids.toSet().containsAll(note.aboutUids);
}

/// Svar från `confirmNoteActions`.
class ConfirmResult {
  final List<({String actionId, String? targetId, bool alreadyDone})> applied;
  final List<({String actionId, String reason})> skipped;

  const ConfirmResult({this.applied = const [], this.skipped = const []});

  factory ConfirmResult.fromResponse(Object? data) {
    if (data is! Map) return const ConfirmResult();
    final applied = <({String actionId, String? targetId, bool alreadyDone})>[];
    for (final r in (data['applied'] as List? ?? const [])) {
      if (r is! Map) continue;
      final id = r['actionId'];
      if (id is! String) continue;
      applied.add((
        actionId: id,
        targetId: r['targetId'] as String?,
        alreadyDone: r['alreadyDone'] == true,
      ));
    }
    final skipped = <({String actionId, String reason})>[];
    for (final r in (data['skipped'] as List? ?? const [])) {
      if (r is! Map) continue;
      final id = r['actionId'];
      if (id is! String) continue;
      final reason = r['reason'];
      skipped.add((
        actionId: id,
        reason: reason is String && reason.isNotEmpty
            ? reason
            : 'Förslaget kunde inte sparas.',
      ));
    }
    return ConfirmResult(applied: applied, skipped: skipped);
  }

  /// Meddelandet efter bekräftelse, exakt som Androids InboxViewModel.
  /// `isError` när ingenting kunde sparas.
  ({String message, bool isError}) summary() {
    final parts = <String>[];
    final done = applied.where((a) => !a.alreadyDone).length;
    if (done > 0) parts.add('$done sparade.');
    final already = applied.where((a) => a.alreadyDone).length;
    if (already > 0) parts.add('$already fanns redan.');
    if (skipped.isNotEmpty) parts.add(skipped.first.reason);
    final message = parts.join(' ');
    if (applied.isEmpty) {
      return (
        message: message.isEmpty ? 'Inget kunde sparas.' : message,
        isError: true,
      );
    }
    return (message: message, isError: false);
  }
}

/// Status på en rad i Inkorgen (Androids `noteStatusText`).
String noteStatusText(NoteModel note, [DateTime? now]) {
  if (note.failed || note.isStuck(now)) return 'Tolkningen gick inte igenom.';
  if (note.isBusy) return 'Tolkas just nu…';
  if (note.needsReview) return 'Väntar på att du går igenom förslagen.';
  final n = note.linkedIds.length;
  if (n == 1) return 'Behandlad. 1 sak skapades.';
  if (n > 1) return 'Behandlad. $n saker skapades.';
  return 'Behandlad.';
}
