import 'package:cloud_firestore/cloud_firestore.dart';

/// Datamodell för storskärmsfoton (FAS 4.5 Beslut 1).
class DisplayPhotoModel {
  final String id;
  final String url;
  final String storagePath;
  final DateTime createdAt;
  final String uploadedBy;

  const DisplayPhotoModel({
    required this.id,
    required this.url,
    required this.storagePath,
    required this.createdAt,
    required this.uploadedBy,
  });

  factory DisplayPhotoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawCreatedAt = data['createdAt'];
    DateTime created;
    if (rawCreatedAt is Timestamp) {
      created = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
      created = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    return DisplayPhotoModel(
      id: doc.id,
      url: data['url'] as String? ?? '',
      storagePath: data['storagePath'] as String? ?? '',
      createdAt: created,
      uploadedBy: data['uploadedBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'url': url,
      'storagePath': storagePath,
      'createdAt': FieldValue.serverTimestamp(),
      'uploadedBy': uploadedBy,
    };
  }
}
