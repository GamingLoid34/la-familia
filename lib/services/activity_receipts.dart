import 'dart:convert';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Kvittensjournal, inte skrivkö. En nyckel per operation undviker samtidiga read-modify-write-förluster.
class ActivityReceipts {
  static const prefix = 'activity_receipt_';
  static final messages = ValueNotifier<List<String>>([]);
  static String? _family;
  static final Set<String> _visibleKeys = {};
  static Future<T> track<T>({required String family, required String title,
    required List<String> ids, String date = '', String kind = 'upsert', required Future<T> Function(String writeId) operation}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Logga in igen.');
    final id = const Uuid().v4();
    final prefs = await SharedPreferences.getInstance();
    final data = {'uid': uid, 'family': family, 'title': title, 'ids': ids,
      'kind': kind, 'date': date, 'at': DateTime.now().millisecondsSinceEpoch, 'status': 'pending'};
    if (!await prefs.setString('$prefix$id', jsonEncode(data))) throw StateError('Kunde inte spara lokal kvittens.');
    try {
      final result = await operation(id);
      await prefs.remove('$prefix$id');
      return result;
    } catch (e) {
      await prefs.setString('$prefix$id', jsonEncode({...data, 'status': e is FirebaseException && e.code == 'permission-denied' ? 'rejected' : 'pending'}));
      if (_family == family) await refresh(family);
      rethrow;
    }
  }
  static Future<void> refresh(String? family) async {
    _family = family;
    messages.value = [];
    _visibleKeys.clear();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || family == null) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = <String>[];
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      final data = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      if (data['uid'] != uid || data['family'] != family) continue;
      var confirmed = false;
      if (data['status'] == 'pending' && DateTime.now().millisecondsSinceEpoch - (data['at'] as num) < 7 * 86400000) {
        try {
          final db = FirebaseFirestore.instance;
          await db.waitForPendingWrites().timeout(const Duration(seconds: 3));
          final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final ids = (data['ids'] as List).cast<String>();
          for (var i = 0; i < ids.length; i += 10) {
            docs.addAll((await db.collection('planner_events').where('familyId', isEqualTo: family)
              .where(FieldPath.documentId, whereIn: ids.skip(i).take(10).toList())
              .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 3))).docs);
          }
          if (ids.isNotEmpty && docs.every((d) => !d.metadata.hasPendingWrites)) {
            confirmed = data['kind'] == 'delete' ? docs.isEmpty : docs.any((d) => d.data()['writeId'] == key.substring(prefix.length));
          }
        } catch (e, stack) { developer.log('Kvittensen kunde ännu inte verifieras', error: e, stackTrace: stack); }
      }
      if (FirebaseAuth.instance.currentUser?.uid != uid || _family != family) return;
      if (confirmed) { await prefs.remove(key); } else {
        _visibleKeys.add(key);
        pending.add('${data['title']} ${data['date'] ?? ''}: ${data['status'] == 'rejected' ? 'ändringen nekades' : 'tidigare ändring är ännu obekräftad'}. Kontrollera kalendern; skapa inte en dubblett.');
      }
    }
    if (FirebaseAuth.instance.currentUser?.uid == uid && _family == family) messages.value = pending;
  }
  static Future<void> acknowledge() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    for (final key in _visibleKeys.toList()) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final data = jsonDecode(raw) as Map;
      if (data['uid'] == uid && data['family'] == _family) await prefs.remove(key);
    }
    messages.value = [];
  }
}
