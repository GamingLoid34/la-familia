import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import 'member_avatar.dart';

/// Veckogrid (ROADMAP Etapp 9.1): medlemmar som rader, dagar som kolumner.
/// Fast vänsterkolumn med avatarer; dagarna scrollas horisontellt.
/// Tap på en cell öppnar dagens detaljer för den medlemmen.
class WeekGrid extends StatelessWidget {
  final List<UserModel> members;
  final List<QueryDocumentSnapshot> events;
  final DateTime weekStart;
  final void Function(UserModel member, DateTime day,
      List<QueryDocumentSnapshot> dayEvents) onCellTap;

  const WeekGrid({
    super.key,
    required this.members,
    required this.events,
    required this.weekStart,
    required this.onCellTap,
  });

  static const double _cellW = 96;
  static const double _cellH = 72;
  static const double _headerH = 40;

  List<QueryDocumentSnapshot> _eventsFor(UserModel m, DateTime day) {
    final list = events.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!eventOccursOnDay(d, day)) return false;
      if (eventHasNoPersons(d)) return false;
      return eventIncludesPerson(d, uid: m.uid, name: m.name);
    }).toList();
    list.sort((a, b) {
      final ta = ((a.data() as Map)['time'] as String? ?? '99:99');
      final tb = ((b.data() as Map)['time'] as String? ?? '99:99');
      return ta.compareTo(tb);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette();
    final today = DateTime.now();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fast kolumn: avatarer
        Column(
          children: [
            const SizedBox(height: _headerH),
            for (final m in members)
              SizedBox(
                height: _cellH,
                width: 56,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FamilyMemberAvatar(member: m, size: 34),
                      const SizedBox(height: 2),
                      Text(
                        m.name.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // Scrollbara dagkolumner
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(7, (i) {
                final day = DateTime(
                    weekStart.year, weekStart.month, weekStart.day + i);
                final isToday = day.year == today.year &&
                    day.month == today.month &&
                    day.day == today.day;
                final dayName =
                    DateFormat('E d/M', 'sv').format(day);

                return SizedBox(
                  width: _cellW,
                  child: Column(
                    children: [
                      // Dagheader
                      SizedBox(
                        height: _headerH,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppTheme.dayPalette(day.weekday).base
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              dayName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isToday
                                    ? AppTheme.getNpfTextColor(day.weekday)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final m in members)
                        _buildCell(context, m, day, palette, isToday),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, UserModel m, DateTime day,
      DayPalette palette, bool isToday) {
    final dayEvents = _eventsFor(m, day);
    return InkWell(
      onTap: () => onCellTap(m, day, dayEvents),
      child: Container(
        height: _cellH,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday
                ? palette.base.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.05),
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: dayEvents.isEmpty
            ? const SizedBox.expand()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final doc in dayEvents.take(2))
                    _miniEvent(doc.data() as Map<String, dynamic>),
                  if (dayEvents.length > 2)
                    Text(
                      '+${dayEvents.length - 2} till',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: palette.deep,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _miniEvent(Map<String, dynamic> d) {
    final t = (d['time'] as String? ?? '').trim();
    final pik = d['piktogram'] as String? ?? '📅';
    final title = d['title'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(pik, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              t.isEmpty ? title : '$t $title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
