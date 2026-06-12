import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../utils/date_utils.dart';
import '../utils/recurrence.dart';

/// Lokala påminnelser för aktiviteter och sysslor (Android/iOS — inte web).
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb) return;

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
  }

  /// Deterministiskt positivt notis-ID från Firestore docId.
  static int idForDoc(String docId) => docId.hashCode & 0x7FFFFFFF;

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
          startTime: DateTime(day.year, day.month, day.day, h, m),
        );
      }
    } else {
      final day = parseDate(data['date']);
      if (day == null) return;
      await scheduleActivityReminder(
        docId: docId,
        title: title,
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

  /// Aktivitet — påminnelse 15 min innan start, plus valbar
  /// övergångsvarning 10 min innan (NPF: det är bytet som är svårt).
  static Future<void> scheduleActivityReminder({
    required String docId,
    required String title,
    required DateTime startTime,
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
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            title: 'Snart dags att byta 🔄',
            body: 'Om 10 min: $title. Börja runda av det du gör.',
            payload: 'transition',
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

  /// Syssla — påminnelse på angiven tid (kräver dueDate + dueTime).
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'Syssla att göra ✅',
        body: title,
        payload: 'chore',
      );
    } catch (e, stack) {
      developer.log('scheduleChoreReminder failed', error: e, stackTrace: stack);
    }
  }

  static Future<void> cancel(String docId) async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: idForDoc(docId));
      // Eventuell övergångsvarning för samma aktivitet.
      await _plugin.cancel(id: idForDoc('${docId}_t'));
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
}
