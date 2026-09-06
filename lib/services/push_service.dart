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

  /// VAPID-nyckel för web push (Firebase Console → Cloud Messaging →
  /// Web Push certificates). Används ENDAST på webben.
  static const String _vapidKey =
      'BEJGwN_ajOztktQ119Sy1uLxHc6RJ5w2eU02nBHGwE3yGEYnXO9ex0fflkmM3vICreK0v5_KSUpk2_wsERzKD8w';

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final messaging = FirebaseMessaging.instance;

      if (kIsWeb) {
        // Webb (iPhone-PWA m.fl.): fråga ALDRIG om tillstånd här — iOS kräver
        // en knapptryckning (enableWebPush). Men om tillstånd redan finns
        // (t.ex. efter omstart av appen) hämtas token så den hålls färsk.
        try {
          final settings = await messaging.getNotificationSettings();
          if (settings.authorizationStatus == AuthorizationStatus.authorized) {
            final token = await messaging.getToken(vapidKey: _vapidKey);
            if (token != null) await _saveToken(token);
          }
        } catch (e, stack) {
          developer.log('PushService web-init token', error: e, stackTrace: stack);
        }
        messaging.onTokenRefresh.listen(_saveToken);
        // Förgrund på webben: användaren tittar redan på appen — ingen
        // systemnotis behövs (och flutter_local_notifications stöds inte här).
        return;
      }

      // Android 13+ behörigheten delas med lokala notiser; ofarligt att fråga igen.
      await messaging.requestPermission();

      // Skapa Android-notiskanalen 'family_channel' explicit med high importance
      final androidPlugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'family_channel',
          'Familjehändelser',
          description: 'Notiser från familjen: tavlan, reaktioner, sysslor',
          importance: Importance.high,
        ),
      );

      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
      messaging.onTokenRefresh.listen(_saveToken);

      // Förgrund: FCM visar inget själv — visa som lokal notis på family_channel.
      // Servern har redan gjort filtreringen.
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        try {
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
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
          );
        } catch (e, stack) {
          developer.log('PushService.onMessage local show misslyckades',
              error: e, stackTrace: stack);
        }
      });
    } catch (e, stack) {
      developer.log('PushService.init misslyckades', error: e, stackTrace: stack);
    }
  }

  /// Webben: begär notistillstånd (MÅSTE anropas från en knapptryckning på iOS)
  /// och registrerar enhetens token. Returnerar true om tillstånd beviljades.
  /// Kastar inte — fel loggas och ger false.
  static Future<bool> enableWebPush() async {
    if (!kIsWeb) return false;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      final token = await messaging.getToken(vapidKey: _vapidKey);
      if (token == null) return false;
      await _saveToken(token);
      return true;
    } catch (e, stack) {
      // Vanligaste felet på iPhone: appen körs i Safari-flik i stället för
      // från hemskärmsikonen ("unsupported-browser").
      developer.log('enableWebPush misslyckades', error: e, stackTrace: stack);
      return false;
    }
  }

  /// Hämtar denna enhets FCM token om tillgänglig.
  static Future<String?> getDeviceToken() async {
    try {
      return await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
    } catch (e, stack) {
      developer.log('PushService.getDeviceToken misslyckades',
          error: e, stackTrace: stack);
      return null;
    }
  }

  static Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final update = <String, dynamic>{
        'fcmTokens': FieldValue.arrayUnion([token]),
      };
      if (kIsWeb) {
        update['fcmTokensWeb'] = FieldValue.arrayUnion([token]);
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update(update);
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
