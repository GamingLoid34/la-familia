import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/display_photo_model.dart';

/// Tjänst för uppladdning, hämtning och radering av storskärmsfoton (FAS 4.5).
class DisplayPhotoService {
  DisplayPhotoService._();
  static final DisplayPhotoService instance = DisplayPhotoService._();

  static const int maxPhotosPerFamily = 50;
  static const double maxImageDimension = 1920.0;
  static const int jpegQuality = 80;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  /// Realtidsström av familjens storskärmsfoton, sorterade efter skapandedatum.
  Stream<List<DisplayPhotoModel>> streamPhotos(String familyId) {
    if (familyId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('families')
        .doc(familyId)
        .collection('display_photos')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DisplayPhotoModel.fromFirestore(doc))
            .where((p) => p.url.isNotEmpty)
            .toList());
  }

  /// Hämtar aktuellt antal uppladdade foton för familjen.
  Future<int> getPhotoCount(String familyId) async {
    if (familyId.isEmpty) return 0;
    final snap = await _firestore
        .collection('families')
        .doc(familyId)
        .collection('display_photos')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Väljer flera bilder från galleriet med inbyggd komprimering
  /// (max 1920 px längsta sida, JPEG-kvalitet ~80).
  Future<List<XFile>> pickPhotos() async {
    try {
      final selected = await _picker.pickMultiImage(
        maxWidth: maxImageDimension,
        maxHeight: maxImageDimension,
        imageQuality: jpegQuality,
      );
      return selected;
    } catch (e, stack) {
      developer.log(
        'Fel vid val av bilder via ImagePicker',
        name: 'DisplayPhotoService',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// Laddar upp en enskild bild med progressrapportering (0.0 till 1.0).
  ///
  /// Skapar bildfil i Storage och metadatadokument i Firestore.
  Future<DisplayPhotoModel> uploadPhoto({
    required String familyId,
    required XFile file,
    void Function(double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Användaren är inte inloggad');
    }

    final docRef = _firestore
        .collection('families')
        .doc(familyId)
        .collection('display_photos')
        .doc();
    final photoId = docRef.id;
    final storagePath = 'families/$familyId/display_photos/$photoId.jpg';
    final storageRef = _storage.ref().child(storagePath);

    final bytes = await file.readAsBytes();
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {
        'familyId': familyId,
        'uploadedBy': user.uid,
      },
    );

    final uploadTask = storageRef.putData(bytes, metadata);

    StreamSubscription<TaskSnapshot>? sub;
    if (onProgress != null) {
      sub = uploadTask.snapshotEvents.listen((event) {
        if (event.totalBytes > 0) {
          final progress = event.bytesTransferred / event.totalBytes;
          onProgress(progress.clamp(0.0, 1.0));
        }
      });
    }

    try {
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await docRef.set({
        'url': downloadUrl,
        'storagePath': storagePath,
        'createdAt': FieldValue.serverTimestamp(),
        'uploadedBy': user.uid,
      });

      return DisplayPhotoModel(
        id: photoId,
        url: downloadUrl,
        storagePath: storagePath,
        createdAt: DateTime.now(),
        uploadedBy: user.uid,
      );
    } finally {
      await sub?.cancel();
    }
  }

  /// Raderar ett foto: tar bort metadatadokumentet först, därefter Storage-objektet.
  /// Fel vid Storage-borttagning loggas men avbryter inte operationen.
  Future<void> deletePhoto({
    required String familyId,
    required String docId,
    required String storagePath,
  }) async {
    // 1. Ta bort Firestore-metadata först så att UI/skärm omedelbart uppdateras
    await _firestore
        .collection('families')
        .doc(familyId)
        .collection('display_photos')
        .doc(docId)
        .delete();

    // 2. Ta bort Storage-objektet (föräldralösa filer accepteras hellre än spöklänkar)
    if (storagePath.isNotEmpty) {
      try {
        await _storage.ref(storagePath).delete();
      } catch (e, stack) {
        developer.log(
          'Kunde inte ta bort Storage-objekt: $storagePath (accepteras)',
          name: 'DisplayPhotoService',
          error: e,
          stackTrace: stack,
        );
      }
    }
  }
}
