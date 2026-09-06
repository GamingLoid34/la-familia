import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParsedScheduleEvent {
  String date; // YYYY-MM-DD
  String time; // HH:mm
  String? endTime; // HH:mm
  String title;
  String? location;
  bool selected;

  ParsedScheduleEvent({
    required this.date,
    required this.time,
    this.endTime,
    required this.title,
    this.location,
    this.selected = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'time': time,
      if (endTime != null && endTime!.isNotEmpty) 'endTime': endTime,
      'title': title,
      if (location != null && location!.isNotEmpty) 'location': location,
    };
  }

  factory ParsedScheduleEvent.fromMap(Map<dynamic, dynamic> m) {
    return ParsedScheduleEvent(
      date: m['date'] as String? ?? '',
      time: m['time'] as String? ?? '',
      endTime: m['endTime'] as String?,
      title: m['title'] as String? ?? '',
      location: m['location'] as String?,
      selected: true,
    );
  }
}

class ScheduleScanResult {
  final String scheduleTitle;
  final String? personHint;
  final List<ParsedScheduleEvent> events;

  const ScheduleScanResult({
    required this.scheduleTitle,
    this.personHint,
    required this.events,
  });
}

class ScheduleImportResult {
  final String importId;
  final int eventCount;

  const ScheduleImportResult({
    required this.importId,
    required this.eventCount,
  });
}

/// Klient för `parseScheduleImage` och `saveScheduleImport` (AI schemascanning).
class ScheduleScanService {
  static Future<ScheduleScanResult> parseScheduleImage({
    required String imageBase64,
    required String mediaType,
    required String weekStartHint,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('parseScheduleImage')
          .call<Map<String, dynamic>>({
        'imageBase64': imageBase64,
        'mediaType': mediaType,
        'weekStartHint': weekStartHint,
      });
      final data = result.data;
      final scheduleTitle =
          data['scheduleTitle'] as String? ?? 'Skannat schema';
      final personHint = data['personHint'] as String?;
      final rawEvents = data['events'] as List<dynamic>? ?? const [];
      final events = rawEvents
          .map((e) => ParsedScheduleEvent.fromMap(e as Map<dynamic, dynamic>))
          .where((e) =>
              e.date.isNotEmpty && e.time.isNotEmpty && e.title.isNotEmpty)
          .toList();

      return ScheduleScanResult(
        scheduleTitle: scheduleTitle,
        personHint: personHint,
        events: events,
      );
    } catch (e, stack) {
      developer.log('parseScheduleImage misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  static Future<ScheduleImportResult> saveScheduleImport({
    required String name,
    required String personName,
    required String personUid,
    required List<ParsedScheduleEvent> events,
    String schemaLabel = 'Skola',
    String? piktogram,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('saveScheduleImport')
          .call<Map<String, dynamic>>({
        'name': name,
        'personName': personName,
        'personUid': personUid,
        'events': events.map((e) => e.toMap()).toList(),
        'schemaLabel': schemaLabel,
        if (piktogram != null && piktogram.isNotEmpty) 'piktogram': piktogram,
      });
      final data = result.data;
      final importId = data['importId'] as String? ?? '';
      final eventCount = data['eventCount'] as int? ?? 0;
      return ScheduleImportResult(
        importId: importId,
        eventCount: eventCount,
      );
    } catch (e, stack) {
      developer.log('saveScheduleImport misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }
}
