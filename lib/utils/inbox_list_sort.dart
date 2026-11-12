import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _noteDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

/// The publication date keeps an older RSS letter in its original week even
/// when it was fetched today. Manual notes use the date they were added.
DateTime? inboxListDate(Map<String, dynamic> data) =>
    _noteDate(data['publishedAt']) ?? _noteDate(data['createdAt']);

enum InboxListSection {
  review('ATT GRANSKA'),
  failed('MISSLYCKADES'),
  unread('EJ TOLKADE'),
  other('ÖVRIGA');

  const InboxListSection(this.label);
  final String label;
}

bool inboxInterpretationStuck(Map<String, dynamic> data, DateTime now) {
  final since = _noteDate(data['interpretingSince']);
  return data['status'] == 'interpreting' &&
      since != null &&
      now.difference(since) > const Duration(minutes: 5);
}

InboxListSection inboxListSection(Map<String, dynamic> data, DateTime now) {
  if (data['status'] == 'failed' || inboxInterpretationStuck(data, now)) {
    return InboxListSection.failed;
  }
  if (data['status'] == 'needs_review') return InboxListSection.review;
  if (data['status'] == 'saved' &&
      (data['requestId']?.toString().trim().isEmpty ?? true)) {
    return InboxListSection.unread;
  }
  return InboxListSection.other;
}
