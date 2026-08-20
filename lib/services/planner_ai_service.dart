import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

sealed class PlannerAction {
  const PlannerAction();
}

class AssignChoreAction extends PlannerAction {
  final String choreId;
  final String assigneeUid;
  final String assigneeName;

  const AssignChoreAction({
    required this.choreId,
    required this.assigneeUid,
    required this.assigneeName,
  });
}

class RescheduleChoreAction extends PlannerAction {
  final String choreId;
  final String newDate;

  const RescheduleChoreAction({
    required this.choreId,
    required this.newDate,
  });
}

class CreateEventAction extends PlannerAction {
  final String title;
  final String date;
  final String? time;
  final List<String> personUids;

  const CreateEventAction({
    required this.title,
    required this.date,
    this.time,
    this.personUids = const [],
  });
}

class PlannerSuggestion {
  final String text;
  final String day;
  final PlannerAction? action;

  const PlannerSuggestion({
    required this.text,
    required this.day,
    this.action,
  });
}

PlannerAction? _parseAction(dynamic raw) {
  if (raw is! Map) return null;
  final m = Map<String, dynamic>.from(raw);
  final type = m['type'] as String?;
  switch (type) {
    case 'assign_chore':
      final choreId = (m['choreId'] as String?)?.trim() ?? '';
      final assigneeUid = (m['assigneeUid'] as String?)?.trim() ?? '';
      if (choreId.isEmpty || assigneeUid.isEmpty) return null;
      return AssignChoreAction(
        choreId: choreId,
        assigneeUid: assigneeUid,
        assigneeName: (m['assigneeName'] as String?)?.trim() ?? '',
      );
    case 'reschedule_chore':
      final choreId = (m['choreId'] as String?)?.trim() ?? '';
      final newDate = (m['newDate'] as String?)?.trim() ?? '';
      if (choreId.isEmpty || newDate.isEmpty) return null;
      return RescheduleChoreAction(choreId: choreId, newDate: newDate);
    case 'create_event':
      final title = (m['title'] as String?)?.trim() ?? '';
      final date = (m['date'] as String?)?.trim() ?? '';
      if (title.isEmpty || date.isEmpty) return null;
      final timeRaw = m['time'];
      final time = timeRaw is String && RegExp(r'^\d{2}:\d{2}$').hasMatch(timeRaw)
          ? timeRaw
          : null;
      final uids = (m['personUids'] as List?)
              ?.whereType<String>()
              .map((u) => u.trim())
              .where((u) => u.isNotEmpty)
              .toList() ??
          const <String>[];
      return CreateEventAction(
        title: title,
        date: date,
        time: time,
        personUids: uids,
      );
    default:
      return null;
  }
}

/// Klient för `askPlanner`-callablen (AI veckoplanering).
class PlannerAiService {
  static Future<List<PlannerSuggestion>> askPlanner({
    required String startDate,
    required String endDate,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('askPlanner')
          .call<Map<String, dynamic>>({
        'startDate': startDate,
        'endDate': endDate,
      });
      final raw = result.data['suggestions'] as List<dynamic>? ?? const [];
      return raw
          .map((e) {
            final m = e as Map<dynamic, dynamic>;
            return PlannerSuggestion(
              text: m['text'] as String? ?? '',
              day: m['day'] as String? ?? '',
              action: _parseAction(m['action']),
            );
          })
          .where((s) => s.text.isNotEmpty && s.day.isNotEmpty)
          .toList();
    } catch (e, stack) {
      developer.log('askPlanner misslyckades', error: e, stackTrace: stack);
      rethrow;
    }
  }
}
