import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;

Future<void> reportPilotClient(String family) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('pilot_installation') ?? const Uuid().v4();
    if (!await prefs.setString('pilot_installation', id)) return;
    final info = await PackageInfo.fromPlatform();
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'calendarClients.$id': {
      'protocol': 2, 'version': info.version, 'platform': kIsWeb ? 'pwa' : 'flutter',
      'familyId': family, 'seenAt': FieldValue.serverTimestamp(),
    }});
  } catch (e, stack) { developer.log('Kunde inte rapportera klientversion', error: e, stackTrace: stack); }
}
