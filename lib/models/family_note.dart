import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyNote {
  final String id;
  final String familyId;
  final String fromUid;
  final String fromName;
  final String fromColor;
  final String date; // YYYY-MM-DD
  final DateTime createdAt;
  final String text;

  const FamilyNote({
    required this.id,
    required this.familyId,
    required this.fromUid,
    required this.fromName,
    required this.fromColor,
    required this.date,
    required this.createdAt,
    required this.text,
  });

  factory FamilyNote.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FamilyNote(
      id: doc.id,
      familyId: d['familyId'] ?? '',
      fromUid: d['fromUid'] ?? '',
      fromName: d['fromName'] ?? '',
      fromColor: d['fromColor'] ?? '',
      date: d['date'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      text: d['text'] ?? '',
    );
  }
}
