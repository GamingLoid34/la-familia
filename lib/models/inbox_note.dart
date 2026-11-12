import 'dart:convert';
import 'package:crypto/crypto.dart';

String normalizeNoteText(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((line) => line.isNotEmpty)
    .join('\n')
    .toLowerCase();

String? noteContentHash(String text) {
  final normalized = normalizeNoteText(text);
  return normalized.isEmpty
      ? null
      : sha256.convert(utf8.encode(normalized)).toString();
}

Map<String, dynamic> newInboxNote({
  required String familyId,
  required String uid,
  required String text,
  required bool isPrivate,
  required List<String> aboutUids,
  required String requestId,
  required Object createdAt,
}) => {
  'familyId': familyId,
  'ownerUid': uid,
  'createdByUid': uid,
  'visibility': isPrivate ? 'private' : 'family',
  'text': text.trim(),
  'contentHash': noteContentHash(text),
  'aboutUids': aboutUids,
  'status': 'saved',
  'requestId': requestId,
  'linkedIds': <Object>[],
  'createdAt': createdAt,
};

List<Map<String, dynamic>> pendingNoteActions(Map<String, dynamic> note) {
  final interpretation = note['interpretation'];
  if (interpretation is! Map) return [];
  final actions = interpretation['actions'];
  if (actions is! List) return [];
  final linked = (note['linkedIds'] as List? ?? [])
      .whereType<Map>()
      .map((row) => row['actionId'])
      .whereType<String>()
      .toSet();
  return actions
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .where(
        (action) =>
            action['id'] is String &&
            action['id'].toString().isNotEmpty &&
            !linked.contains(action['id']) &&
            (action['status'] == null || action['status'] == 'pending'),
      )
      .toList();
}
