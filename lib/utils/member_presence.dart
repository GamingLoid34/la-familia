import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
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

DateTime? _plannerLooseStart(Map<String, dynamic> d) {
  final base = parseYmdDate(d['date']);
  if (base == null) return null;
  final timeStr = d['time'] as String? ?? '';
  if (timeStr.isNotEmpty) {
    final tp = timeStr.split(':');
    if (tp.length >= 2) {
      return DateTime(
        base.year,
        base.month,
        base.day,
        int.tryParse(tp[0]) ?? 0,
        int.tryParse(tp[1]) ?? 0,
      );
    }
  }
  return base;
}

/// [memberTodayEvents] = dagens händelser där `persons` redan filtrerats till [member].
MemberPresence computeMemberPresence(
  UserModel member, {
  required List<QueryDocumentSnapshot> memberTodayEvents,
  required List<QueryDocumentSnapshot> familyShiftDocs,
  required List<QueryDocumentSnapshot> familyBusyDocs,
}) {
  final now = DateTime.now();

  for (final doc in familyBusyDocs) {
    final d = doc.data() as Map<String, dynamic>;
    final busyUid = d['userUid'] as String? ?? '';
    final matches = busyUid.isNotEmpty
        ? busyUid == member.uid
        : (d['userName'] as String? ?? '') == member.name;
    if (!matches) continue;
    if (busySessionIsActiveNow(d, now)) return MemberPresence.busy;
  }

  for (final doc in familyShiftDocs) {
    final d = doc.data() as Map<String, dynamic>;
    if (!assignedToPerson(d, uid: member.uid, name: member.name)) continue;
    if (workShiftIsActiveNow(d, now)) return MemberPresence.busy;
  }

  for (final doc in memberTodayEvents) {
    final d = doc.data() as Map<String, dynamic>;
    if (plannerTimedEventIsActiveNow(d, now)) {
      return MemberPresence.busy;
    }
  }

  for (final doc in memberTodayEvents) {
    final d = doc.data() as Map<String, dynamic>;
    final start = _plannerLooseStart(d);
    if (start == null) continue;
    final end = start.add(const Duration(hours: 1));
    if (start.isAfter(now) && start.difference(now).inMinutes <= 120) {
      return MemberPresence.canReply;
    }
    if (start.isBefore(now) && end.isAfter(now)) {
      return MemberPresence.canReply;
    }
  }

  return MemberPresence.free;
}
