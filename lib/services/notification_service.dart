import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../utils/date_utils.dart';
import '../utils/recurrence.dart';

/// Lokala påminnelser för aktiviteter och sysslor (Android/iOS — inte web).
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const MethodChannel _systemChannel = MethodChannel('la_familia/system');

  static bool? _exactAllowedCache;
  static DateTime _exactCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Exakta larm om tillåtet, annars inexakt (försenad notis > ingen notis).
  /// Cacheas 60 s eftersom den anropas i loopar vid omschemaläggning.
  static Future<AndroidScheduleMode> _scheduleMode() async {
    final now = DateTime.now();
    if (_exactAllowedCache == null ||
        now.difference(_exactCacheAt) > const Duration(seconds: 60)) {
      _exactAllowedCache = await canScheduleExactNotifications();
      _exactCacheAt = now;
    }
    return _exactAllowedCache == true
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static Future<void> initialize() async {
    if (kIsWeb) {
      developer.log('Notiser inaktiva på web (Fas 0)');
      return;
    }

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Stockholm'));
    } catch (e, stack) {
      developer.log('NotificationService timezone fallback',
          error: e, stackTrace: stack);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _plugin.initialize(settings: settings);

    // Skapa Android-notiskanaler explicit
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'family_channel',
          'Familjehändelser',
          description: 'Notiser från familjen: tavlan, reaktioner, sysslor',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'activity_channel',
          'Aktiviteter',
          description: 'Påminnelser för aktiviteter',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'transition_channel',
          'Övergångar',
          description: 'Förvarning inför byte av aktivitet (10 min innan)',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'chore_channel',
          'Sysslor',
          description: 'Påminnelser om sysslor',
          importance: Importance.defaultImportance,
        ),
      );
      // Larm-kanal för fokustimern. Nytt id ('timer_alarm_channel') eftersom
      // kanalinställningar är oföränderliga när kanalen väl skapats på enheten.
      await androidPlugin.deleteNotificationChannel(channelId: 'timer_channel');
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'timer_alarm_channel',
          'Fokustimer (larm)',
          description: 'Larmljud när fokustimern är klar — hörs även i tyst läge',
          importance: Importance.max,
          playSound: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
    }
  }

  /// Deterministiskt positivt notis-ID — FNV-1a över codeUnits
  /// (stabilt mellan Dart-versioner, till skillnad från String.hashCode).
  static int idForDoc(String docId) {
    var hash = 0x811c9dc5;
    for (final c in docId.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  static const int _timerNotifId = 0x7E1E1001;

  /// Hur långt fram vi schemalägger instanser av återkommande aktiviteter.
  /// Schemaläggs om vid varje spara/redigering; resten täcks vid nästa ändring.
  static const int recurringScheduleDays = 14;

  static String _instanceDocId(String docId, DateTime day) =>
      '${docId}_${dateKey(day)}';

  /// Schemalägger påminnelser för en aktivitet utifrån dess data:
  /// en notis för engångsaktiviteter, en per instans (14 dagar framåt)
  /// för återkommande. [data] får inte innehålla FieldValue-sentinels.
  static Future<void> scheduleActivityReminders({
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    if (kIsWeb) return;
    final title = data['title'] as String? ?? '';
    final piktogram = (data['piktogram'] as String? ?? '').trim();
    final timeStr = (data['time'] as String?)?.trim() ?? '';
    final tp = timeStr.split(':');
    if (tp.length < 2) return;
    final h = int.tryParse(tp[0]) ?? 0;
    final m = int.tryParse(tp[1]) ?? 0;

    if (data['recurrence'] != null) {
      final now = DateTime.now();
      final days = expandRecurrence(
          data, now, now.add(const Duration(days: recurringScheduleDays)));
      for (final day in days) {
        await scheduleActivityReminder(
          docId: _instanceDocId(docId, day),
          title: title,
          piktogram: piktogram,
          startTime: DateTime(day.year, day.month, day.day, h, m),
        );
      }
    } else {
      final day = parseDate(data['date']);
      if (day == null) return;
      await scheduleActivityReminder(
        docId: docId,
        title: title,
        piktogram: piktogram,
        startTime: DateTime(day.year, day.month, day.day, h, m),
      );
    }
  }

  /// Avbokar aktivitetens påminnelser — både bas-ID:t och eventuella
  /// instans-ID:n om [data] är återkommande.
  static Future<void> cancelActivityReminders(
    String docId,
    Map<String, dynamic>? data,
  ) async {
    if (kIsWeb) return;
    await cancel(docId);
    if (data != null && data['recurrence'] is Map) {
      final now = DateTime.now();
      final days = expandRecurrence(
          data, now, now.add(const Duration(days: recurringScheduleDays)));
      for (final day in days) {
        await cancel(_instanceDocId(docId, day));
      }
    }
  }

  /// Avbokar en enskild instans av en återkommande aktivitet.
  static Future<void> cancelActivityInstance(String docId, DateTime day) =>
      cancel(_instanceDocId(docId, day));

  /// Aktivitet — påminnelse 15 min innan start, valbar
  /// övergångsvarning 10 min innan (NPF), samt valbar startpåminnelse vid starttid.
  static Future<void> scheduleActivityReminder({
    required String docId,
    required String title,
    required DateTime startTime,
    String? piktogram,
  }) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      if (prefs.getBool('notifActivity') ?? true) {
        final scheduled = startTime.subtract(const Duration(minutes: 15));
        if (scheduled.isAfter(now)) {
          await _plugin.zonedSchedule(
            id: idForDoc(docId),
            scheduledDate: tz.TZDateTime.from(scheduled, tz.local),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'activity_channel',
                'Aktiviteter',
                channelDescription: 'Påminnelser för aktiviteter',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            title: 'Aktivitet börjar snart ⏰',
            body: '$title börjar om 15 minuter.',
            payload: 'activity',
          );
        }
      }

      // Övergångsvarning — hjälper vid aktivitetsbyten.
      if (prefs.getBool('notifTransition') ?? true) {
        final transAt = startTime.subtract(const Duration(minutes: 10));
        if (transAt.isAfter(now)) {
          await _plugin.zonedSchedule(
            id: idForDoc('${docId}_t'),
            scheduledDate: tz.TZDateTime.from(transAt, tz.local),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'transition_channel',
                'Övergångar',
                channelDescription:
                    'Förvarning inför byte av aktivitet (10 min innan)',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            title: 'Snart dags att byta 🔄',
            body: 'Om 10 min: $title. Börja runda av det du gör.',
            payload: 'transition',
          );
        }
      }

      // Påminnelse vid start — exakt när aktiviteten börjar.
      if (prefs.getBool('notifStart') ?? false) {
        if (startTime.isAfter(now)) {
          final pikStr = (piktogram != null && piktogram.isNotEmpty) ? ' $piktogram' : '';
          final timeStr = DateFormat('HH:mm').format(startTime);
          await _plugin.zonedSchedule(
            id: idForDoc('${docId}_start'),
            scheduledDate: tz.TZDateTime.from(startTime, tz.local),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'activity_channel',
                'Aktiviteter',
                channelDescription: 'Påminnelser för aktiviteter',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            title: 'Nu börjar: $title$pikStr',
            body: 'Klockan är $timeStr',
            payload: 'activity_start',
          );
        }
      }
    } catch (e, stack) {
      developer.log('scheduleActivityReminder failed',
          error: e, stackTrace: stack);
    }
  }

  /// Avbokar alla väntande notiser med någon av [payloads]
  /// ('activity' | 'transition' | 'chore'). Används av togglarna i
  /// Inställningar så att en typ kan stängas av utan att andra ryker.
  static Future<void> cancelByPayloads(Set<String> payloads) async {
    if (kIsWeb) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final req in pending) {
        if (payloads.contains(req.payload)) {
          await _plugin.cancel(id: req.id);
        }
      }
    } catch (e, stack) {
      developer.log('cancelByPayloads failed', error: e, stackTrace: stack);
    }
  }

  /// Syssla — påminnelse på angiven tid (kräver dueDate/dueTime eller recurrence + dueTime).
  static Future<void> scheduleChoreReminder({
    required String docId,
    required String title,
    required DateTime dueAt,
  }) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('notifChore') ?? true)) return;
      if (dueAt.isBefore(DateTime.now())) return;

      await _plugin.zonedSchedule(
        id: idForDoc(docId),
        scheduledDate: tz.TZDateTime.from(dueAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'chore_channel',
            'Sysslor',
            channelDescription: 'Påminnelser om sysslor',
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: await _scheduleMode(),
        title: 'Syssla att göra ✅',
        body: title,
        payload: 'chore',
      );
    } catch (e, stack) {
      developer.log('scheduleChoreReminder failed', error: e, stackTrace: stack);
    }
  }

  /// Engångs eller återkommande (14 dagar) sysslopåminnelser.
  static Future<void> scheduleChoreReminders({
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    if (kIsWeb) return;
    final title = (data['chore'] as String? ?? data['title'] as String? ?? '')
        .trim();
    if (title.isEmpty) return;
    final timeStr = (data['dueTime'] as String?)?.trim() ?? '';
    final tp = timeStr.split(':');
    if (tp.length < 2) return;
    final h = int.tryParse(tp[0]) ?? 0;
    final m = int.tryParse(tp[1]) ?? 0;

    if (data['isRecurring'] == true && data['recurrence'] is Map) {
      final now = DateTime.now();
      final days = expandRecurrence(
        data,
        now,
        now.add(const Duration(days: recurringScheduleDays)),
      );
      for (final day in days) {
        await scheduleChoreReminder(
          docId: _instanceDocId(docId, day),
          title: title,
          dueAt: DateTime(day.year, day.month, day.day, h, m),
        );
      }
    } else {
      final due = choreDueDateTime(data);
      if (due == null) return;
      await scheduleChoreReminder(docId: docId, title: title, dueAt: due);
    }
  }

  static Future<void> cancelChoreReminders(
    String docId,
    Map<String, dynamic>? data,
  ) async {
    if (kIsWeb) return;
    await cancel(docId);
    if (data != null && data['recurrence'] is Map) {
      final now = DateTime.now();
      final days = expandRecurrence(
        data,
        now,
        now.add(const Duration(days: recurringScheduleDays)),
      );
      for (final day in days) {
        await cancel(_instanceDocId(docId, day));
      }
    }
  }

  /// Avbokar en enskild instans av återkommande syssla.
  static Future<void> cancelChoreInstance(String docId, DateTime day) =>
      cancel(_instanceDocId(docId, day));

  static Future<void> cancel(String docId) async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: idForDoc(docId));
      // Eventuell övergångsvarning för samma aktivitet.
      await _plugin.cancel(id: idForDoc('${docId}_t'));
      // Eventuell startpåminnelse för samma aktivitet.
      await _plugin.cancel(id: idForDoc('${docId}_start'));
    } catch (e, stack) {
      developer.log('cancel notification failed', error: e, stackTrace: stack);
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
    } catch (e, stack) {
      developer.log('cancelAll failed', error: e, stackTrace: stack);
    }
  }

  /// Avboka allt och schemalägg om events (14 dagar + recurrence) och
  /// sysslor med dueTime (inkl. återkommande instanser). Respekterar prefs-togglar.
  static Future<void> rescheduleAllForFamily(String familyId) async {
    if (kIsWeb) return;
    if (familyId.isEmpty) return;
    try {
      await cancelAll();
      final now = DateTime.now();
      final from = dateKey(now);
      final to = dateKey(now.add(const Duration(days: recurringScheduleDays)));
      final db = FirebaseFirestore.instance;

      final datedSnap = await db
          .collection('planner_events')
          .where('familyId', isEqualTo: familyId)
          .where('date', isGreaterThanOrEqualTo: from)
          .where('date', isLessThanOrEqualTo: to)
          .get();
      final recurringSnap = await db
          .collection('planner_events')
          .where('familyId', isEqualTo: familyId)
          .where('isRecurring', isEqualTo: true)
          .get();
      final choresSnap = await db
          .collection('chores')
          .where('familyId', isEqualTo: familyId)
          .get();

      final seen = <String>{};
      for (final doc in [...datedSnap.docs, ...recurringSnap.docs]) {
        if (!seen.add(doc.id)) continue;
        await scheduleActivityReminders(docId: doc.id, data: doc.data());
      }

      for (final doc in choresSnap.docs) {
        final d = doc.data();
        final timeStr = (d['dueTime'] as String?)?.trim() ?? '';
        if (timeStr.isEmpty) continue;
        await scheduleChoreReminders(docId: doc.id, data: d);
      }
    } catch (e, stack) {
      developer.log('rescheduleAllForFamily failed',
          error: e, stackTrace: stack);
    }
  }

  /// Schemalägger en engångs-notis när fokustimern når noll (även i bakgrund).
  static Future<void> scheduleTimerDone({required DateTime at}) async {
    if (kIsWeb) return;
    try {
      await cancelTimerDone();
      if (!at.isAfter(DateTime.now())) {
        await showTimerDoneNow();
        return;
      }
      await _plugin.zonedSchedule(
        id: _timerNotifId,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'timer_alarm_channel',
            'Fokustimer (larm)',
            channelDescription:
                'Larmljud när fokustimern är klar — hörs även i tyst läge',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: await _scheduleMode(),
        title: 'Fokustimer klar ⏱️',
        body: 'Tiden är ute — bra jobbat!',
        payload: 'timer',
      );
    } catch (e, stack) {
      developer.log('scheduleTimerDone failed', error: e, stackTrace: stack);
    }
  }

  static Future<void> cancelTimerDone() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: _timerNotifId);
    } catch (e, stack) {
      developer.log('cancelTimerDone failed', error: e, stackTrace: stack);
    }
  }

  /// Omedelbar notis (förgrund eller om schemaläggning missades).
  static Future<void> showTimerDoneNow() async {
    if (kIsWeb) return;
    try {
      await _plugin.show(
        id: _timerNotifId,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'timer_alarm_channel',
            'Fokustimer (larm)',
            channelDescription:
                'Larmljud när fokustimern är klar — hörs även i tyst läge',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        title: 'Fokustimer klar ⏱️',
        body: 'Tiden är ute — bra jobbat!',
        payload: 'timer',
      );
    } catch (e, stack) {
      developer.log('showTimerDoneNow failed', error: e, stackTrace: stack);
    }
  }

  /// Be om notis-tillstånd (Android 13+).
  static Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (e, stack) {
      developer.log('requestPermissions failed', error: e, stackTrace: stack);
      return false;
    }
  }

  /// Kontrollera om notiser är tillåtna i systemet (Android/iOS).
  static Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? true;
      }
      return true;
    } catch (e, stack) {
      developer.log('areNotificationsEnabled failed', error: e, stackTrace: stack);
      return false;
    }
  }

  /// Kontrollera om exakta larm är tillåtna (Android 12+).
  static Future<bool> canScheduleExactNotifications() async {
    if (kIsWeb) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.canScheduleExactNotifications() ?? true;
      }
      return true;
    } catch (e, stack) {
      developer.log('canScheduleExactNotifications failed',
          error: e, stackTrace: stack);
      return false;
    }
  }

  /// Öppnar systemdialogen för exakta larm (Android 12+). Returnerar nya statusen.
  static Future<bool> requestExactAlarmsPermission() async {
    if (kIsWeb) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
      _exactAllowedCache = null; // tvinga omkontroll
      return await canScheduleExactNotifications();
    } catch (e, stack) {
      developer.log('requestExactAlarmsPermission failed',
          error: e, stackTrace: stack);
      return false;
    }
  }

  /// Hämtar alla för tillfället schemalagda lokala påminnelser.
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (kIsWeb) return const [];
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (e, stack) {
      developer.log('getPendingNotifications failed',
          error: e, stackTrace: stack);
      return const [];
    }
  }

  /// Schemalägger en test-notis om exakt 1 minut (för diagnostik med låst skärm).
  static Future<void> scheduleTestReminderIn1Min() async {
    if (kIsWeb) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      final scheduled = now.add(const Duration(minutes: 1));
      await _plugin.zonedSchedule(
        id: 0x7E570001,
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'activity_channel',
            'Aktiviteter',
            channelDescription: 'Påminnelser för aktiviteter',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: await _scheduleMode(),
        title: 'Testpåminnelse ⏰',
        body: 'Den lokala påminnelsen fungerar! (1 min test)',
        payload: 'test_1min',
      );
    } catch (e, stack) {
      developer.log('scheduleTestReminderIn1Min failed',
          error: e, stackTrace: stack);
    }
  }

  /// Parsar sysslans dueDate + dueTime till [DateTime], eller null.
  static DateTime? choreDueDateTime(Map<String, dynamic> data) {
    final rawDate = data['dueDate'];
    final timeStr = (data['dueTime'] as String?)?.trim() ?? '';
    if (rawDate == null || timeStr.isEmpty) return null;

    DateTime? day;
    if (rawDate is String && rawDate.isNotEmpty) {
      final p = rawDate.split('-');
      if (p.length >= 3) {
        day = DateTime(
          int.tryParse(p[0]) ?? 0,
          int.tryParse(p[1]) ?? 0,
          int.tryParse(p[2]) ?? 0,
        );
      }
    }
    if (day == null) return null;

    final tp = timeStr.split(':');
    if (tp.length < 2) return null;
    final h = int.tryParse(tp[0]) ?? 0;
    final m = int.tryParse(tp[1]) ?? 0;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  /// Är appen undantagen från batterioptimering? (Android)
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    try {
      return await _systemChannel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return true; // okänt läge — larma inte i onödan
    }
  }

  /// Öppnar systemsidan där användaren kan undanta appen från batterioptimering.
  static Future<void> openBatteryOptimizationSettings() async {
    if (kIsWeb) return;
    try {
      await _systemChannel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e, stack) {
      developer.log('openBatteryOptimizationSettings failed',
          error: e, stackTrace: stack);
    }
  }
}
