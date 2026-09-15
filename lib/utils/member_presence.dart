import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'date_utils.dart';
import 'person_match.dart';
import 'schedule_time_utils.dart';

/// Samma logik som Familjestatus — används även på Hem-raden.
enum MemberPresence { free, canReply, busy }

extension MemberPresenceColors on MemberPresence {
  Color get ringColor {
    switch (this) {
      case MemberPresence.free:
        return const Color(0xFF6BAE75);
      case MemberPresence.canReply:
        return const Color(0xFFEDD87A);
      case MemberPresence.busy:
        return const Color(0xFFD95F4B);
    }
  }

  String get statusLabel {
    switch (this) {
      case MemberPresence.free:
        return 'Ledig';
      case MemberPresence.canReply:
        return 'Kan svara';
      case MemberPresence.busy:
        return 'Upptagen';
    }
  }
}

DateTime? _plannerLooseStart(Map<String, dynamic> d, [DateTime? onDay]) =>
    parseDateTime(d, onDay);

/// [memberTodayEvents] = dagens händelser där `persons` redan filtrerats till [member].
MemberPresence computeMemberPresence(
  UserModel member, {
  required List<QueryDocumentSnapshot> memberTodayEvents,
  required List<QueryDocumentSnapshot> familyShiftDocs,
  required List<QueryDocumentSnapshot> familyBusyDocs,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();

  for (final doc in familyBusyDocs) {
    final d = doc.data() as Map<String, dynamic>;
    final busyUid = d['userUid'] as String? ?? '';
    final matches = busyUid.isNotEmpty
        ? busyUid == member.uid
        : (d['userName'] as String? ?? '') == member.name;
    if (!matches) continue;
    if (busySessionIsActiveNow(d, current)) return MemberPresence.busy;
  }

  for (final doc in familyShiftDocs) {
    final d = doc.data() as Map<String, dynamic>;
    if (!assignedToPerson(d, uid: member.uid, name: member.name)) continue;
    if (workShiftIsActiveNow(d, current)) return MemberPresence.busy;
  }

  for (final doc in memberTodayEvents) {
    final d = doc.data() as Map<String, dynamic>;
    if (plannerTimedEventIsActiveNow(d, current)) {
      return MemberPresence.busy;
    }
  }

  for (final doc in memberTodayEvents) {
    final d = doc.data() as Map<String, dynamic>;
    final start = _plannerLooseStart(d, current);
    if (start == null) continue;
    final end = start.add(const Duration(hours: 1));
    if (start.isAfter(current) && start.difference(current).inMinutes <= 120) {
      return MemberPresence.canReply;
    }
    if (start.isBefore(current) && end.isAfter(current)) {
      return MemberPresence.canReply;
    }
  }

  return MemberPresence.free;
}

/// Beräknar textuell närvaroetikett för en medlem (FAS 5.7).
/// Delas mellan mobilens Hem och storskärmens moduler:
/// 1. Arbetspass aktivt nu -> 'Arbetar'
/// 2. Schemaimport aktiv nu (`planningImportKind == 'schedule'`) -> [schemaLabelFor] (Noomi -> 'Rehab', skola -> 'Skola')
/// 3. Busy session eller aktiv händelse nu -> 'Upptagen'
/// 4. Annars -> 'Hemma'
String computeMemberPresenceLabel(
  UserModel member, {
  required List<QueryDocumentSnapshot> memberTodayEvents,
  required List<QueryDocumentSnapshot> familyShiftDocs,
  required List<QueryDocumentSnapshot> familyBusyDocs,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();

  // 1. Arbetspass aktivt nu?
  for (final doc in familyShiftDocs) {
    final d = doc.data() as Map<String, dynamic>;
    if (!assignedToPerson(d, uid: member.uid, name: member.name)) continue;
    if (workShiftIsActiveNow(d, current)) return 'Arbetar';
  }

  // 2. Skola / Rehab / Schema aktivt nu via schemaLabelFor
  for (final doc in memberTodayEvents) {
    final d = doc.data() as Map<String, dynamic>;
    if (d['planningImportKind'] == 'schedule') {
      if (plannerTimedEventIsActiveNow(d, current)) {
        return schemaLabelFor(d);
      }
    }
  }

  // 3. Upptagen session eller aktiv aktivitet?
  for (final doc in familyBusyDocs) {
    final d = doc.data() as Map<String, dynamic>;
    final busyUid = d['userUid'] as String? ?? '';
    final matches = busyUid.isNotEmpty
        ? busyUid == member.uid
        : (d['userName'] as String? ?? '') == member.name;
    if (matches && busySessionIsActiveNow(d, current)) return 'Upptagen';
  }

  for (final doc in memberTodayEvents) {
    final d = doc.data() as Map<String, dynamic>;
    if (plannerTimedEventIsActiveNow(d, current)) return 'Upptagen';
  }

  return 'Hemma';
}
