import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM-pushar mellan familjemedlemmar (ROADMAP Etapp 11).
///
/// Klientens ansvar: hålla enhetens token uppdaterad på users-dokumentet
/// (`fcmTokens`, array — en användare kan ha flera enheter) och visa
/// förgrundsmeddelanden som lokala notiser. Servern (functions/index.js)
/// bestämmer VEM som får push och respekterar Upptagen/låg energi/toggle.
class PushService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;
    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ behörigheten delas med lokala notiser; ofarligt att fråga igen.
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
      messaging.onTokenRefresh.listen(_saveToken);

      // Förgrund: FCM visar inget själv — visa som lokal notis.
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        final n = msg.notification;
        if (n == null) return;
        _local.show(
          id: msg.hashCode & 0x7FFFFFFF,
          title: n.title,
          body: n.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'family_channel',
              'Familjehändelser',
              channelDescription:
                  'Notiser från familjen: tavlan, reaktioner, sysslor',
              importance: Importance.defaultImportance,
            ),
          ),
        );
      });
    } catch (e, stack) {
      developer.log('PushService.init misslyckades', error: e, stackTrace: stack);
    }
  }

  static Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    } catch (e, stack) {
      developer.log('PushService token-spara misslyckades',
          error: e, stackTrace: stack);
    }
  }

  /// Slå på/av familjehändelse-pushar för den här användaren.
  /// Servern läser fältet innan den skickar.
  static Future<void> setFamilyPushEnabled(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'pushFamilyEvents': enabled,
      });
    } catch (e, stack) {
      developer.log('setFamilyPushEnabled misslyckades',
          error: e, stackTrace: stack);
    }
  }
}
