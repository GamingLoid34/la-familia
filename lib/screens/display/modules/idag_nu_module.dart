import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../app_theme.dart';
import '../../../models/user_model.dart';
import '../../../providers/family_provider.dart';
import '../../../utils/day_events.dart';
import '../../../utils/person_match.dart';
import '../../../utils/schedule_display.dart';
import '../../../utils/schedule_time_utils.dart';
import '../display_chips.dart';
import '../display_formatters.dart';
import '../display_log.dart';
import '../display_module_registry.dart';

/// Modul: Idag & Nu ("idag_nu") (FAS 4).
/// Dagsöversikt för morgonvyn med hero-nedräkning till nästa familjehändelse,
/// kolumner för Familjen och varje medlem, närvarobadges och pågår-markering.
class IdagNuModule extends StatefulWidget {
  final DisplayModuleContext moduleContext;

  const IdagNuModule({super.key, required this.moduleContext});

  @override
  State<IdagNuModule> createState() => _IdagNuModuleState();
}

class _IdagNuModuleState extends State<IdagNuModule> {
  StreamSubscription? _shiftsSub;
  StreamSubscription? _busySub;

  List<QueryDocumentSnapshot> _shifts = [];
  List<QueryDocumentSnapshot> _busyDocs = [];
  String? _subscribedFamilyId;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fid = context.watch<FamilyProvider>().currentUser?.familyId ?? '';
    if (fid != _subscribedFamilyId) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _shiftsSub?.cancel();
    _busySub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _shiftsSub?.cancel();
    _busySub?.cancel();

    final provider = Provider.of<FamilyProvider>(context, listen: false);
    final fid = provider.currentUser?.familyId ?? '';
    _subscribedFamilyId = fid;

    if (fid.isEmpty) return;

    DisplayLog.instance.log(
      'prenumeration',
      'Startar skift- och närvaroprenumerationer för Idag-Nu-vyn',
    );

    _shiftsSub = FirebaseFirestore.instance
        .collection('work_shifts')
        .where('familyId', isEqualTo: fid)
        .snapshots()
        .listen(
      (snap) {
        if (mounted) setState(() => _shifts = snap.docs);
      },
      onError: (e) {
        DisplayLog.instance.log('strömfel', 'Fel vid hämtning av skift i Idag-Nu: $e');
      },
    );

    _busySub = FirebaseFirestore.instance
        .collection('families')
        .doc(fid)
        .collection('busy_sessions')
        .snapshots()
        .listen(
      (snap) {
        if (mounted) setState(() => _busyDocs = snap.docs);
      },
      onError: (e) {
        DisplayLog.instance.log('strömfel', 'Fel vid hämtning av busy_sessions i Idag-Nu: $e');
      },
    );
  }

  Color _memberColor(UserModel m, DayPalette palette) {
    try {
      if (m.color.isNotEmpty) return AppTheme.colorFromHex(m.color);
      return Color(m.colorValue);
    } catch (_) {
      return palette.base;
    }
  }

  String _presenceLabel(
    UserModel member,
    DateTime now,
    List<QueryDocumentSnapshot> memberEvents,
  ) {
    // 1. Arbetspass aktivt nu?
    for (final doc in _shifts) {
      final d = doc.data() as Map<String, dynamic>;
      if (!assignedToPerson(d, uid: member.uid, name: member.name)) continue;
      if (workShiftIsActiveNow(d, now)) return 'Arbetar';
    }

    // 2. Skola/schema aktivt nu?
    for (final doc in memberEvents) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') {
        if (plannerTimedEventIsActiveNow(d, now)) return 'Skola';
      }
    }

    // 3. Upptagen session eller aktiv aktivitet?
    for (final doc in _busyDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final busyUid = d['userUid'] as String? ?? '';
      final matches = busyUid.isNotEmpty
          ? busyUid == member.uid
          : (d['userName'] as String? ?? '') == member.name;
      if (matches && busySessionIsActiveNow(d, now)) return 'Upptagen';
    }

    for (final doc in memberEvents) {
      final d = doc.data() as Map<String, dynamic>;
      if (plannerTimedEventIsActiveNow(d, now)) return 'Upptagen';
    }

    return 'Hemma';
  }

  Widget _buildPresenceBadge(String label) {
    Color bg;
    Color border;
    Color text;

    switch (label) {
      case 'Arbetar':
        bg = const Color(0xFFE3F2FD);
        border = const Color(0xFF90CAF9);
        text = const Color(0xFF1565C0);
        break;
      case 'Skola':
        bg = const Color(0xFFF3E5F5);
        border = const Color(0xFFCE93D8);
        text = const Color(0xFF6A1B9A);
        break;
      case 'Upptagen':
        bg = const Color(0xFFFFEBEE);
        border = const Color(0xFFEF9A9A);
        text = const Color(0xFFC62828);
        break;
      default: // 'Hemma'
        bg = const Color(0xFFE8F5E9);
        border = const Color(0xFFA5D6A7);
        text = const Color(0xFF2E7D32);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final now = widget.moduleContext.now;
    final members = widget.moduleContext.members;
    final palette = AppTheme.dayPalette(now.weekday);
    final isLowStimuli = AppTheme.lowStimuli;

    final todayEvents = provider.todayEvents;

    // ─── 1. Hero: Hitta nästa familjehändelse ──────────────────────────────
    QueryDocumentSnapshot? nextUpcomingEvent;
    int minDiffMinutes = 999999;

    for (final doc in todayEvents) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') continue;
      final s = plannerTimedStart(d);
      if (s == null) continue;
      final diff = s.difference(now).inMinutes;
      if (diff >= 0 && diff < minDiffMinutes) {
        minDiffMinutes = diff;
        nextUpcomingEvent = doc;
      }
    }

    String heroText;
    if (nextUpcomingEvent != null) {
      final d = nextUpcomingEvent.data() as Map<String, dynamic>;
      final countdownStr = formatCountdownMinutes(minDiffMinutes);
      final piktogram = (d['piktogram'] as String? ?? '📅').trim();
      final title = (d['title'] as String? ?? '').trim();
      final time = (d['time'] as String? ?? '').trim();

      String who = '';
      if (eventIncludesAllMembers(d, members) || eventHasNoPersons(d)) {
        who = ' (Familjen)';
      } else {
        final matched = members
            .where((m) => eventIncludesPerson(d, uid: m.uid, name: m.name))
            .map((m) => m.name.split(' ').first)
            .toList();
        if (matched.isNotEmpty) {
          who = ' (${matched.join(', ')})';
        }
      }

      heroText = 'Ut genom dörren $countdownStr · $piktogram $title $time$who';
    } else {
      heroText = 'Inget mer planerat idag';
    }

    // Datumrubrik
    final rawDate = DateFormat('EEEE d MMMM', 'sv_SE').format(now);
    final dateStr = rawDate.isNotEmpty
        ? rawDate[0].toUpperCase() + rawDate.substring(1)
        : rawDate;

    // ─── 2. Uppdelning på Familjen och medlemmar ───────────────────────────
    final familyEvents = <QueryDocumentSnapshot>[];
    final memberEventMap = <String, List<QueryDocumentSnapshot>>{};
    for (final m in members) {
      memberEventMap[m.uid] = [];
    }

    for (final doc in todayEvents) {
      final d = doc.data() as Map<String, dynamic>;
      if (eventIncludesAllMembers(d, members) || eventHasNoPersons(d)) {
        familyEvents.add(doc);
      } else {
        for (final m in members) {
          if (eventIncludesPerson(d, uid: m.uid, name: m.name)) {
            memberEventMap[m.uid]!.add(doc);
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Topprad: Datum till vänster, Hero till höger
        SizedBox(
          height: 52,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: isLowStimuli ? null : palette.gradient,
                  color: isLowStimuli ? palette.base : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'IDAG',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                dateStr,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),
              // Hero Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.base.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: palette.base.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      nextUpcomingEvent != null
                          ? Icons.directions_walk_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 20,
                      color: palette.deep,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      heroText,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: palette.deep,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Kolumnvy: Familjen + medlemmar
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kolumn 1: Familjen
              Expanded(
                child: _buildColumnCard(
                  header: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: palette.base,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('👥', style: TextStyle(fontSize: 18)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Familjen',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  content: familyEvents.isEmpty
                      ? const Center(
                          child: Text(
                            'Inga familjehändelser idag',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 14,
                              color: Color(0xFF888888),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: familyEvents.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final doc = familyEvents[i];
                            final d = doc.data() as Map<String, dynamic>;
                            final isOngoing = plannerTimedEventIsActiveNow(d, now);
                            final end = plannerTimedEnd(d);
                            final isPast = end != null && end.isBefore(now);

                            return DisplayActivityCard(
                              data: d,
                              memberColor: palette.base,
                              isFolded: true,
                              isLowStimuli: isLowStimuli,
                              isOngoing: isOngoing,
                              isPast: isPast,
                              badgeText: isOngoing ? 'PÅGÅR' : null,
                            );
                          },
                        ),
                ),
              ),

              // Medlemskolumner
              for (final m in members) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMemberColumn(
                    member: m,
                    events: memberEventMap[m.uid] ?? const [],
                    palette: palette,
                    now: now,
                    isLowStimuli: isLowStimuli,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMemberColumn({
    required UserModel member,
    required List<QueryDocumentSnapshot> events,
    required DayPalette palette,
    required DateTime now,
    required bool isLowStimuli,
  }) {
    final memberColor = _memberColor(member, palette);
    final initial = member.name.trim().isNotEmpty
        ? member.name.trim()[0].toUpperCase()
        : '?';
    final firstName = member.name.split(' ').first;
    final presence = _presenceLabel(member, now, events);

    // Separera skift, skola/schema och aktiviteter
    final memberShifts = _shifts.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return assignedToPerson(d, uid: member.uid, name: member.name) &&
          shiftTouchesDay(d, now);
    }).toList();

    final scheduleDocs = <QueryDocumentSnapshot>[];
    final activityDocs = <QueryDocumentSnapshot>[];
    for (final doc in events) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') {
        scheduleDocs.add(doc);
      } else {
        activityDocs.add(doc);
      }
    }

    final items = <Widget>[];

    // 1. Arbetspass
    for (final doc in memberShifts) {
      final d = doc.data() as Map<String, dynamic>;
      final interval = shiftInterval(d);
      final isNight = isNightShift(d);

      String pik = '💼';
      String label = 'Jobb';
      String timeStr;

      if (interval != null) {
        final sHm = DateFormat('HH:mm').format(interval.start);
        final eHm = DateFormat('HH:mm').format(interval.end);
        if (isNight) {
          pik = '🌙';
          label = 'Natt';
          timeStr = sameCalendarDay(interval.start, now)
              ? formatCompactTime(sHm, eHm)
              : formatCompactTime('–$eHm');
        } else {
          timeStr = formatCompactTime(sHm, eHm);
        }
      } else {
        final startField = (d['startTime'] ?? d['start']) as String? ?? '';
        final endField = (d['endTime'] ?? d['end']) as String? ?? '';
        timeStr = formatCompactTime(startField, endField);
      }

      final displayText =
          timeStr.isNotEmpty ? '$pik · $label · $timeStr' : '$pik · $label';

      items.add(DisplayRamPlate(text: displayText, memberColor: memberColor));
    }

    // 2. Skola/schema klumpning
    for (final entry in buildScheduleDisplay(scheduleDocs, clumpSchool: true)) {
      if (entry is ScheduleClusterEntry) {
        final maps = entry.docs.map((d) => d.data() as Map<String, dynamic>);
        final pik = maps.isNotEmpty ? schemaPiktogramFor(maps.first) : '🏫';
        final label = maps.isNotEmpty ? schemaLabelFor(maps.first) : 'Skola';
        final span = scheduleTimeSpan(maps);
        final timeStr = formatCompactTime(span.minStart ?? '', span.maxEnd);

        final displayText =
            timeStr.isNotEmpty ? '$pik · $label · $timeStr' : '$pik · $label';

        items.add(DisplayRamPlate(text: displayText, memberColor: memberColor));
      }
    }

    // 3. Vanliga aktiviteter
    for (final doc in activityDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final isOngoing = plannerTimedEventIsActiveNow(d, now);
      final end = plannerTimedEnd(d);
      final isPast = end != null && end.isBefore(now);

      items.add(DisplayActivityCard(
        data: d,
        memberColor: memberColor,
        isLowStimuli: isLowStimuli,
        isOngoing: isOngoing,
        isPast: isPast,
        badgeText: isOngoing ? 'PÅGÅR' : null,
      ));
    }

    return _buildColumnCard(
      header: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: memberColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              firstName,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          _buildPresenceBadge(presence),
        ],
      ),
      content: items.isEmpty
          ? const Center(
              child: Text(
                'Inga händelser idag',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  color: Color(0xFF888888),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, i) => items[i],
            ),
    );
  }

  Widget _buildColumnCard({
    required Widget header,
    required Widget content,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E5EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFE2E5EE)),
          const SizedBox(height: 6),
          Expanded(child: content),
        ],
      ),
    );
  }
}
