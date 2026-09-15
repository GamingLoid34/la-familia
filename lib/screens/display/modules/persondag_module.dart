import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app_theme.dart';
import '../../../models/user_model.dart';
import '../../../providers/family_provider.dart';
import '../../../utils/chore_utils.dart';
import '../../../utils/recurrence.dart';
import '../../../utils/day_events.dart' show formatCountdownMinutes;
import '../../../utils/member_presence.dart';
import '../../../utils/person_match.dart';
import '../../../utils/schedule_display.dart';
import '../../../utils/schedule_time_utils.dart';
import '../../../utils/svenska_dagar.dart';
import '../../../widgets/member_avatar.dart';
import '../display_chips.dart';
import '../display_formatters.dart';
import '../display_log.dart';
import '../display_module_registry.dart';
import '../display_palette.dart';
import '../display_scene_models.dart';
import '../display_school_menu_data.dart';
import '../display_theme.dart';
import 'persondag_schema.dart';

/// Modul: Persondag ("persondag") (FAS 5.2).
/// Fullskärmsvy för en enskild familjemedlem, vald via spotlightIndex (Stream Deck / Shift+1..8).
class PersondagModule extends StatefulWidget {
  final DisplayModuleContext moduleContext;
  final bool forceClumped;

  const PersondagModule({
    super.key,
    required this.moduleContext,
    this.forceClumped = false,
  });

  @override
  State<PersondagModule> createState() => _PersondagModuleState();
}

class _PersondagModuleState extends State<PersondagModule> {
  StreamSubscription? _shiftsSub;
  StreamSubscription? _busySub;
  String _subscribedFamilyId = '';
  List<QueryDocumentSnapshot> _shifts = [];
  List<QueryDocumentSnapshot> _busyDocs = [];
  int? _lastLoggedInvalidIndex;

  @override
  void initState() {
    super.initState();
    DisplaySchoolMenuData.instance.addListener(_onMenuChanged);
    _subscribe();
  }

  void _onMenuChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final fid = context.watch<FamilyProvider>().currentUser?.familyId ?? '';
      if (fid != _subscribedFamilyId) {
        _subscribe();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    DisplaySchoolMenuData.instance.removeListener(_onMenuChanged);
    _shiftsSub?.cancel();
    _busySub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _shiftsSub?.cancel();
    _busySub?.cancel();

    try {
      final provider = Provider.of<FamilyProvider>(context, listen: false);
      final fid = provider.currentUser?.familyId ?? '';
      _subscribedFamilyId = fid;

      if (fid.isEmpty) return;

      DisplayLog.instance.log(
        'prenumeration',
        'Startar skift- och närvaroprenumerationer för Persondag-vyn',
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
          DisplayLog.instance.log(
            'strömfel',
            'Fel vid hämtning av skift i Persondag: $e',
          );
        },
      );

      _busySub = FirebaseFirestore.instance
          .collection('busy_sessions')
          .where('familyId', isEqualTo: fid)
          .snapshots()
          .listen(
        (snap) {
          if (mounted) setState(() => _busyDocs = snap.docs);
        },
        onError: (e) {
          DisplayLog.instance.log(
            'strömfel',
            'Fel vid hämtning av busy_sessions i Persondag: $e',
          );
        },
      );
    } catch (e) {
      DisplayLog.instance.log(
        'strömfel',
        'Kunde inte starta Firestore-prenumeration i Persondag: $e',
      );
    }
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
    return computeMemberPresenceLabel(
      member,
      memberTodayEvents: memberEvents,
      familyShiftDocs: _shifts,
      familyBusyDocs: _busyDocs,
      now: now,
    );
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
      case 'Upptagen':
        bg = const Color(0xFFFFEBEE);
        border = const Color(0xFFEF9A9A);
        text = const Color(0xFFC62828);
        break;
      case 'Hemma':
        bg = const Color(0xFFE8F5E9);
        border = const Color(0xFFA5D6A7);
        text = const Color(0xFF2E7D32);
        break;
      case 'Skola':
      case 'Rehab':
      case 'Jobb':
      case 'Schema':
      default:
        // Schemaimporter (Skola, Rehab, Jobb etc.)
        bg = const Color(0xFFF3E5F5);
        border = const Color(0xFFCE93D8);
        text = const Color(0xFF6A1B9A);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: text,
        ),
      ),
    );
  }

  int _parseTimeToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return 1440;
    final clean = timeStr.trim().replaceAll('–', '-').split('-').first.trim();
    final parts = clean.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return h * 60 + m;
    }
    return 1440;
  }

  String _buildTomorrowText({
    required UserModel member,
    required DateTime now,
    required List<QueryDocumentSnapshot> tomorrowEvents,
    required List<QueryDocumentSnapshot> allShifts,
  }) {
    final tomorrow = now.add(const Duration(days: 1));

    // 1. Morgondagens ramplatta för personen (arbetspass eller skola/schema)
    String? firstRamText;

    // Kolla skift imorgon
    for (final doc in allShifts) {
      final d = doc.data() as Map<String, dynamic>;
      if (!assignedToPerson(d, uid: member.uid, name: member.name)) continue;
      if (shiftTouchesDay(d, tomorrow)) {
        final interval = shiftInterval(d);
        final isNight = isNightShift(d);
        final pik = isNight ? '🌙' : '💼';
        final label = isNight ? 'Natt' : 'Jobb';
        String timeStr = '';
        if (interval != null) {
          final sHm = DateFormat('HH:mm').format(interval.start);
          timeStr = formatWallTime(sHm);
        } else {
          final raw = (d['startTime'] ?? d['start']) as String? ?? '';
          timeStr = formatWallTime(raw);
        }
        firstRamText =
            timeStr.isNotEmpty ? '$pik $label $timeStr' : '$pik $label';
        break;
      }
    }

    // Kolla skola imorgon om inget skift hittades
    final tomorrowScheduleDocs = <QueryDocumentSnapshot>[];
    final tomorrowActivityDocs = <QueryDocumentSnapshot>[];

    for (final doc in tomorrowEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final isForMember =
          eventIncludesPerson(d, uid: member.uid, name: member.name) ||
              eventIncludesAllMembers(d, widget.moduleContext.members) ||
              eventHasNoPersons(d);
      if (!isForMember) continue;

      if (d['planningImportKind'] == 'schedule') {
        tomorrowScheduleDocs.add(doc);
      } else {
        tomorrowActivityDocs.add(doc);
      }
    }

    if (firstRamText == null && tomorrowScheduleDocs.isNotEmpty) {
      final clusters =
          buildScheduleDisplay(tomorrowScheduleDocs, clumpSchool: true);
      for (final entry in clusters) {
        if (entry is ScheduleClusterEntry) {
          final maps = entry.docs.map((d) => d.data() as Map<String, dynamic>);
          final pik = maps.isNotEmpty ? schemaPiktogramFor(maps.first) : '🏫';
          final label = maps.isNotEmpty ? schemaLabelFor(maps.first) : 'Skola';
          final span = scheduleTimeSpan(maps);
          final t = formatWallTime(span.minStart ?? '');
          firstRamText = t.isNotEmpty ? '$pik $label $t' : '$pik $label';
          break;
        }
      }
    }

    // 2. Morgondagens första aktivitet
    String? firstActText;
    if (tomorrowActivityDocs.isNotEmpty) {
      tomorrowActivityDocs.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;
        final ta = (da['time'] as String? ?? '').trim();
        final tb = (db['time'] as String? ?? '').trim();
        return ta.compareTo(tb);
      });
      final d = tomorrowActivityDocs.first.data() as Map<String, dynamic>;
      final pik = (d['piktogram'] as String? ?? '📅').trim();
      final title = (d['title'] as String? ?? '').trim();
      final timeRaw = (d['time'] as String? ?? '').trim();
      final time = formatWallTime(timeRaw);
      firstActText = time.isNotEmpty ? '$pik $title $time' : '$pik $title';
    }

    final parts = <String>[];
    if (firstRamText != null && firstRamText.isNotEmpty) parts.add(firstRamText);
    if (firstActText != null && firstActText.isNotEmpty) parts.add(firstActText);

    if (parts.isEmpty) {
      return 'Imorgon: ledig dag';
    }
    return 'Imorgon: ${parts.join(' · ')}';
  }

  Widget _buildPlaceholder(
    BuildContext context,
    int? spotlightIndex,
    List<UserModel> members,
  ) {
    final palette = DisplayPalette.of(context);

    if (spotlightIndex != _lastLoggedInvalidIndex) {
      _lastLoggedInvalidIndex = spotlightIndex;
      DisplayLog.instance.log(
        'scen',
        'Persondag: Ogiltigt eller saknat person-index: $spotlightIndex (antal medlemmar: ${members.length})',
      );
    }

    return Container(
      color: palette.background,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.cardBorder),
            boxShadow: [
              BoxShadow(
                color: palette.isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_rounded,
                size: 52,
                color: palette.textMuted,
              ),
              const SizedBox(height: 14),
              Text(
                'Välj en person: Shift + 1..N (eller person:<nr> i fjärrkontroll)',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Tillgängliga personer: ${members.asMap().entries.map((e) => '${e.key + 1}: ${e.value.name.split(' ').first}').join(', ')}',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spotlightIndex = widget.moduleContext.spotlightIndex;
    final members = widget.moduleContext.members;

    if (spotlightIndex == null ||
        spotlightIndex < 1 ||
        spotlightIndex > members.length) {
      return _buildPlaceholder(context, spotlightIndex, members);
    }

    final member = members[spotlightIndex - 1];
    final provider = context.watch<FamilyProvider>();
    final now = widget.moduleContext.now;
    final palette = AppTheme.dayPalette(now.weekday);
    final isLowStimuli = AppTheme.lowStimuli;
    final memberColor = _memberColor(member, palette);
    final displayPalette = DisplayPalette.of(context);

    final todayEvents = provider.todayEvents.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return eventOccursOnDay(d, now);
    }).toList();
    final tomorrowDate = now.add(const Duration(days: 1));
    final tomorrowEvents = provider.tomorrowEvents.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return eventOccursOnDay(d, tomorrowDate);
    }).toList();

    // Sortera ut personens händelser idag
    final memberShifts = _shifts.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return assignedToPerson(d, uid: member.uid, name: member.name) &&
          shiftTouchesDay(d, now);
    }).toList();

    final scheduleDocs = <QueryDocumentSnapshot>[];
    final activityDocs = <QueryDocumentSnapshot>[];

    for (final doc in todayEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final isForMember =
          eventIncludesPerson(d, uid: member.uid, name: member.name);
      final isFamily =
          eventIncludesAllMembers(d, members) || eventHasNoPersons(d);

      if (!isForMember && !isFamily) continue;

      if (d['planningImportKind'] == 'schedule') {
        scheduleDocs.add(doc);
      } else {
        activityDocs.add(doc);
      }
    }

    final presence = _presenceLabel(member, now, [
      ...scheduleDocs,
      ...activityDocs,
    ]);

    // Hitta nästa kommande aktivitet
    QueryDocumentSnapshot? nextUpcomingDoc;
    int minDiffMinutes = 999999;
    for (final doc in activityDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final s = plannerTimedStart(d, now);
      if (s == null) continue;
      final diff = s.difference(now).inMinutes;
      if (diff >= 0 && diff < minDiffMinutes) {
        minDiffMinutes = diff;
        nextUpcomingDoc = doc;
      }
    }

    // Bygg listan av dagens element
    final items = <_PersondagItem>[];

    // 1. Arbetspass
    for (final doc in memberShifts) {
      final d = doc.data() as Map<String, dynamic>;
      final interval = shiftInterval(d);
      final isNight = isNightShift(d);
      final isOngoing = workShiftIsActiveNow(d, now);

      String pik = '💼';
      String label = 'Jobb';
      String timeStr;
      int sortM = 0;

      if (interval != null) {
        final sHm = DateFormat('HH:mm').format(interval.start);
        final eHm = DateFormat('HH:mm').format(interval.end);
        sortM = interval.start.hour * 60 + interval.start.minute;
        if (isNight) {
          pik = '🌙';
          label = 'Natt';
          timeStr = sameCalendarDay(interval.start, now)
              ? formatWallRange(sHm, eHm)
              : formatWallRange('–$eHm');
        } else {
          timeStr = formatWallRange(sHm, eHm);
        }
      } else {
        final startField = (d['startTime'] ?? d['start']) as String? ?? '';
        final endField = (d['endTime'] ?? d['end']) as String? ?? '';
        timeStr = formatWallRange(startField, endField);
        sortM = _parseTimeToMinutes(startField);
      }

      final displayText =
          timeStr.isNotEmpty ? '$pik · $label · $timeStr' : '$pik · $label';

      final plate = DisplayRamPlate(
        piktogram: pik,
        label: label,
        time: timeStr,
        text: displayText,
        memberColor: memberColor,
        isLarge: true,
        isOngoing: isOngoing,
      );

      items.add(_PersondagItem(
        sortMinutes: sortM,
        isRam: true,
        widget: plate,
      ));
    }

    // 2. Skola/schema — lektionsschema (FAS 6d) eller fallback-klump
    bool persondagLunchShown = false;

    // Hämta lunchinfo för lucka-visning
    final lunchInfoForGap = DisplaySchoolMenuData.instance.lunchFor(
      member.uid,
      now,
      widget.moduleContext.skolmatConfig ?? const DisplaySkolmatConfig(),
    );

    final scheduleEntries =
        buildScheduleDisplay(scheduleDocs, clumpSchool: false);
    final timedEntries = scheduleEntries
        .whereType<ScheduleLessonEntry>()
        .where((e) {
          final d = e.doc.data() as Map<String, dynamic>;
          return (d['time'] as String? ?? '').isNotEmpty;
        })
        .toList();

    if (!widget.forceClumped && timedEntries.isNotEmpty) {
      // ── Lektionsschema-väg (FAS 6d) ───────────────────────────────────
      final span = scheduleTimeSpan(
          timedEntries.map((e) => e.doc.data() as Map<String, dynamic>));
      final sortBase = _parseTimeToMinutes(span.minStart);
      persondagLunchShown = true;

      items.add(_PersondagItem(
        sortMinutes: sortBase,
        isRam: false,
        isSchema: true,
        widget: PersondagSchemaView(
          scheduleDocs: timedEntries.map((e) => e.doc).toList(),
          memberColor: memberColor,
          now: now,
          isLowStimuli: isLowStimuli,
          lunchInfo: lunchInfoForGap,
          displayPalette: displayPalette,
        ),
      ));
    } else {
      // ── Fallback: klumpat block (Oscar / inga tidsatta lektioner) ───────
      for (final entry in buildScheduleDisplay(scheduleDocs,
          clumpSchool: true)) {
        if (entry is ScheduleClusterEntry) {
          final maps =
              entry.docs.map((d) => d.data() as Map<String, dynamic>);
          final pik =
              maps.isNotEmpty ? schemaPiktogramFor(maps.first) : '🏫';
          final label =
              maps.isNotEmpty ? schemaLabelFor(maps.first) : 'Skola';
          final span = scheduleTimeSpan(maps);
          final timeStr =
              formatWallRange(span.minStart ?? '', span.maxEnd);
          final sortM = _parseTimeToMinutes(span.minStart);

          final sDt = parseHmOnDate(span.minStart, now);
          final eDt = parseHmOnDate(span.maxEnd, now);
          final isOngoing = sDt != null &&
              eDt != null &&
              !now.isBefore(sDt) &&
              now.isBefore(eDt);

          final displayText =
              timeStr.isNotEmpty ? '$pik · $label · $timeStr' : '$pik · $label';

          final plate = DisplayRamPlate(
            piktogram: pik,
            label: label,
            time: timeStr,
            text: displayText,
            memberColor: memberColor,
            isLarge: true,
            isOngoing: isOngoing,
          );

          Widget plateWidget = plate;
          final lunchInfo = DisplaySchoolMenuData.instance.lunchFor(
            member.uid,
            now,
            widget.moduleContext.skolmatConfig ??
                const DisplaySkolmatConfig(),
          );
          if (lunchInfo != null &&
              lunchInfo.lunch != null &&
              lunchInfo.lunch!.isNotEmpty) {
            persondagLunchShown = true;
            if (lunchInfo.isNudge) {
              plateWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  plate,
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '🍽 ${lunchInfo.lunch!}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF888899),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              final cleanLunch = cleanDishTitle(lunchInfo.lunch!);
              final hasVeg = hasDistinctVegetarian(cleanLunch, lunchInfo.vegetarian);
              final cleanVeg = hasVeg ? cleanDishTitle(lunchInfo.vegetarian!) : null;
              final text = (cleanVeg != null && cleanVeg.isNotEmpty)
                  ? '$cleanLunch · 🌱 $cleanVeg'
                  : cleanLunch;
              plateWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  plate,
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '🍽 $text',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              );
            }
          }

          items.add(_PersondagItem(
            sortMinutes: sortM,
            isRam: true,
            widget: plateWidget,
          ));
        }
      }
    }

    // 3. Vanliga aktiviteter
    for (final doc in activityDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final isOngoing = plannerTimedEventIsActiveNow(d, now);
      final end = plannerTimedEnd(d, onDay: now);
      final isPast = end != null && end.isBefore(now);
      final isNextUpcoming = doc == nextUpcomingDoc && !isOngoing && !isPast;
      final isFamily =
          eventIncludesAllMembers(d, members) || eventHasNoPersons(d);

      final startDt = plannerTimedStart(d, now);
      final sortM = startDt != null
          ? startDt.hour * 60 + startDt.minute
          : _parseTimeToMinutes(d['time'] as String?);

      String? badgeText;
      if (isOngoing) {
        badgeText = isFamily ? 'PÅGÅR · Hela familjen' : 'PÅGÅR';
      } else if (isNextUpcoming && minDiffMinutes >= 0) {
        final countdown = formatCountdownMinutes(minDiffMinutes);
        badgeText = isFamily ? '$countdown · Hela familjen' : countdown;
      } else if (isFamily) {
        badgeText = '👨👩👧👦 Hela familjen';
      }

      final card = DisplayActivityCard(
        data: d,
        memberColor: memberColor,
        isFolded: isFamily,
        isLowStimuli: isLowStimuli,
        isOngoing: isOngoing,
        isPast: isPast,
        badgeText: badgeText,
        isLarge: true,
      );

      items.add(_PersondagItem(
        sortMinutes: sortM,
        isRam: false,
        widget: card,
      ));
    }

    // FAS 5.1b: Om personen saknar schemakluster idag (t.ex. söndag >= 16:00 eller ledig dag),
    // men en väggnudge för manuell matsedel är aktiv: visa den i personvyn
    if (!persondagLunchShown) {
      final nudgeInfo = DisplaySchoolMenuData.instance.lunchFor(
        member.uid,
        now,
        widget.moduleContext.skolmatConfig ?? const DisplaySkolmatConfig(),
      );
      if (nudgeInfo != null && nudgeInfo.isNudge && nudgeInfo.lunch != null) {
        items.add(_PersondagItem(
          sortMinutes: 720,
          isRam: false,
          widget: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E5EE)),
            ),
            child: Row(
              children: [
                const Text('🍽', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nudgeInfo.lunch!,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF888899),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
      }
    }

    // Sortera kronologiskt
    items.sort((a, b) => a.sortMinutes.compareTo(b.sortMinutes));

    // Sysslor för medlemmen idag
    final memberChores = provider.chores.where((c) {
      final d = c.data() as Map<String, dynamic>;
      return choreOccursOnDay(d, now) &&
          choreAssignedToOnDay(d, now, uid: member.uid, name: member.name);
    }).map((c) => c.data() as Map<String, dynamic>).toList();

    // Morgondagens rad
    final tomorrowText = _buildTomorrowText(
      member: member,
      now: now,
      tomorrowEvents: tomorrowEvents,
      allShifts: _shifts,
    );

    // Sortera ut morgondagens poster för högerkolumnen i tvåkolumnsläget
    final tomorrowScheduleDocs = <QueryDocumentSnapshot>[];
    final tomorrowActivityDocs = <QueryDocumentSnapshot>[];

    for (final doc in tomorrowEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final isForMember =
          eventIncludesPerson(d, uid: member.uid, name: member.name);
      final isFamily =
          eventIncludesAllMembers(d, members) || eventHasNoPersons(d);
      if (!isForMember && !isFamily) continue;

      if (d['planningImportKind'] == 'schedule') {
        tomorrowScheduleDocs.add(doc);
      } else {
        tomorrowActivityDocs.add(doc);
      }
    }

    final tomorrowShifts = _shifts.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return assignedToPerson(d, uid: member.uid, name: member.name) &&
          shiftTouchesDay(d, now.add(const Duration(days: 1)));
    }).toList();

    return Container(
      color: displayPalette.background,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTwoColumn = constraints.maxWidth >= 1400;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header
              _buildHeader(member, memberColor, presence, now, displayPalette),
              const SizedBox(height: 18),

              // 2. Huvudyta
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bodyConstraints) {
                    return isTwoColumn
                        ? _buildTwoColumnLayout(
                            context: context,
                            constraints: bodyConstraints,
                            member: member,
                            memberColor: memberColor,
                            now: now,
                            displayPalette: displayPalette,
                            isLowStimuli: isLowStimuli,
                            items: items,
                            scheduleDocs: scheduleDocs,
                            activityDocs: activityDocs,
                            tomorrowScheduleDocs: tomorrowScheduleDocs,
                            tomorrowActivityDocs: tomorrowActivityDocs,
                            tomorrowShifts: tomorrowShifts,
                            memberChores: memberChores,
                            todayMeals: provider.todayMeals,
                            nextUpcomingDoc: nextUpcomingDoc,
                            minDiffMinutes: minDiffMinutes,
                            members: members,
                          )
                        : _buildSingleColumnLayout(
                            context: context,
                            constraints: bodyConstraints,
                            items: items,
                            isLowStimuli: isLowStimuli,
                            displayPalette: displayPalette,
                          );
                  },
                ),
              ),

              // 3. Bottenrader endast vid enkolumn (< 1400 lp)
              if (!isTwoColumn) ...[
                const SizedBox(height: 14),
                _buildChoresRow(memberChores, now, displayPalette),
                const SizedBox(height: 8),
                _buildTomorrowRow(tomorrowText, displayPalette),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Sektionskort för högerkolumnen i tvåkolumnsläget (FAS 6d.3).
  Widget _buildSectionCard({
    required DisplayPalette palette,
    required String title,
    required IconData icon,
    required Widget content,
    Color? accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (accentColor ?? palette.cardBorder).withValues(alpha: accentColor != null ? 0.35 : 1.0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: (accentColor ?? palette.cardBorder).withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: accentColor ?? palette.textPrimary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accentColor ?? palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: content,
          ),
        ],
      ),
    );
  }

  /// Tvåkolumnslayout vid bredd >= 1400 lp (FAS 6d.3).
  Widget _buildTwoColumnLayout({
    required BuildContext context,
    required BoxConstraints constraints,
    required UserModel member,
    required Color memberColor,
    required DateTime now,
    required DisplayPalette displayPalette,
    required bool isLowStimuli,
    required List<_PersondagItem> items,
    required List<QueryDocumentSnapshot> scheduleDocs,
    required List<QueryDocumentSnapshot> activityDocs,
    required List<QueryDocumentSnapshot> tomorrowScheduleDocs,
    required List<QueryDocumentSnapshot> tomorrowActivityDocs,
    required List<QueryDocumentSnapshot> tomorrowShifts,
    required List<Map<String, dynamic>> memberChores,
    required List<QueryDocumentSnapshot> todayMeals,
    required QueryDocumentSnapshot? nextUpcomingDoc,
    required int minDiffMinutes,
    required List<UserModel> members,
  }) {
    // Vänsterkolumn (~58 %): "Idag"
    Widget leftContent;
    final hasSchema = items.any((it) => it.isSchema);
    if (hasSchema) {
      final schemaItem = items.firstWhere((it) => it.isSchema);
      leftContent = schemaItem.widget;
    } else if (items.isNotEmpty) {
      leftContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            items[i].widget,
          ],
        ],
      );
    } else {
      leftContent = Center(
        child: Text(
          isLowStimuli
              ? 'Inga planer inlagda för idag'
              : 'Inga planer idag — lediiigt! 🎉',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: displayPalette.textMuted,
          ),
        ),
      );
    }

    // Högerkolumn (~42 %): Staplade kort (döljs om tomma)
    final rightCards = <Widget>[];

    // 1. Imorgon
    final tomorrowTimedEntries = buildScheduleDisplay(tomorrowScheduleDocs, clumpSchool: false)
        .whereType<ScheduleLessonEntry>()
        .where((e) {
          final d = e.doc.data() as Map<String, dynamic>;
          return (d['time'] as String? ?? '').isNotEmpty;
        })
        .toList();

    if (tomorrowTimedEntries.isNotEmpty) {
      final tomorrowLunchInfo = DisplaySchoolMenuData.instance.lunchFor(
        member.uid,
        now.add(const Duration(days: 1)),
        widget.moduleContext.skolmatConfig ?? const DisplaySkolmatConfig(),
      );
      rightCards.add(_buildSectionCard(
        palette: displayPalette,
        title: 'Imorgon',
        icon: Icons.calendar_today_rounded,
        accentColor: memberColor,
        content: PersondagSchemaView(
          scheduleDocs: tomorrowTimedEntries.map((e) => e.doc).toList(),
          memberColor: memberColor,
          now: now.add(const Duration(days: 1)),
          isLowStimuli: isLowStimuli,
          lunchInfo: tomorrowLunchInfo,
          displayPalette: displayPalette,
          isTomorrow: true,
          showHeader: false,
          hasCardWrapper: false,
        ),
      ));
    } else if (tomorrowShifts.isNotEmpty || tomorrowActivityDocs.isNotEmpty || tomorrowScheduleDocs.isNotEmpty) {
      final tomorrowCards = <Widget>[];
      for (final doc in tomorrowShifts) {
        final d = doc.data() as Map<String, dynamic>;
        final interval = shiftInterval(d);
        final isNight = isNightShift(d);
        final pik = isNight ? '🌙' : '💼';
        final label = isNight ? 'Natt' : 'Jobb';
        String timeStr = '';
        if (interval != null) {
          final sHm = DateFormat('HH:mm').format(interval.start);
          final eHm = DateFormat('HH:mm').format(interval.end);
          timeStr = formatWallRange(sHm, eHm);
        } else {
          final startField = (d['startTime'] ?? d['start']) as String? ?? '';
          final endField = (d['endTime'] ?? d['end']) as String? ?? '';
          timeStr = formatWallRange(startField, endField);
        }
        final displayText = timeStr.isNotEmpty ? '$pik · $label · $timeStr' : '$pik · $label';
        tomorrowCards.add(DisplayRamPlate(
          piktogram: pik,
          label: label,
          time: timeStr,
          text: displayText,
          memberColor: memberColor,
          isLarge: false,
          isOngoing: false,
        ));
      }
      for (final doc in tomorrowActivityDocs) {
        final d = doc.data() as Map<String, dynamic>;
        tomorrowCards.add(DisplayActivityCard(
          data: d,
          memberColor: memberColor,
          isFolded: false,
          isLowStimuli: isLowStimuli,
          isOngoing: false,
          isPast: false,
          isLarge: false,
        ));
      }
      if (tomorrowCards.isNotEmpty) {
        rightCards.add(_buildSectionCard(
          palette: displayPalette,
          title: 'Imorgon',
          icon: Icons.calendar_today_rounded,
          accentColor: memberColor,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < tomorrowCards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                tomorrowCards[i],
              ],
            ],
          ),
        ));
      }
    }

    // 2. Aktiviteter (dagens aktivitetskort om personen har schema)
    if (hasSchema && activityDocs.isNotEmpty) {
      final actWidgets = <Widget>[];
      for (final doc in activityDocs) {
        final d = doc.data() as Map<String, dynamic>;
        final isOngoing = plannerTimedEventIsActiveNow(d, now);
        final end = plannerTimedEnd(d, onDay: now);
        final isPast = end != null && end.isBefore(now);
        final isNextUpcoming = doc == nextUpcomingDoc && !isOngoing && !isPast;
        final isFamily = eventIncludesAllMembers(d, members) || eventHasNoPersons(d);

        String? badgeText;
        if (isOngoing) {
          badgeText = isFamily ? 'PÅGÅR · Hela familjen' : 'PÅGÅR';
        } else if (isNextUpcoming && minDiffMinutes >= 0) {
          final countdown = formatCountdownMinutes(minDiffMinutes);
          badgeText = isFamily ? '$countdown · Hela familjen' : countdown;
        } else if (isFamily) {
          badgeText = '👨👩👧👦 Hela familjen';
        }

        actWidgets.add(DisplayActivityCard(
          data: d,
          memberColor: memberColor,
          isFolded: isFamily,
          isLowStimuli: isLowStimuli,
          isOngoing: isOngoing,
          isPast: isPast,
          badgeText: badgeText,
          isLarge: false,
        ));
      }

      if (actWidgets.isNotEmpty) {
        rightCards.add(_buildSectionCard(
          palette: displayPalette,
          title: 'Aktiviteter',
          icon: Icons.event_rounded,
          accentColor: memberColor,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < actWidgets.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                actWidgets[i],
              ],
            ],
          ),
        ));
      }
    }

    // 3. Sysslor idag
    if (memberChores.isNotEmpty) {
      rightCards.add(_buildSectionCard(
        palette: displayPalette,
        title: 'Sysslor idag',
        icon: Icons.checklist_rounded,
        accentColor: memberColor,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in memberChores) ...[
              Builder(
                builder: (context) {
                  final done = choreDoneOnDay(d, now);
                  final title = (d['title'] as String? ?? '').trim();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: 24,
                          color: done ? memberColor : displayPalette.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              decoration: done ? TextDecoration.lineThrough : null,
                              color: done ? displayPalette.textMuted : displayPalette.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ));
    }

    // 4. Middag ikväll
    if (todayMeals.isNotEmpty) {
      final firstMeal = todayMeals.first.data() as Map<String, dynamic>;
      final mealTitle = (firstMeal['title'] as String? ?? '').trim();
      final rawEmoji = (firstMeal['emoji'] as String? ?? '').trim();
      final mealEmoji = rawEmoji.isNotEmpty ? '$rawEmoji ' : '🍽 ';

      if (mealTitle.isNotEmpty) {
        rightCards.add(_buildSectionCard(
          palette: displayPalette,
          title: 'Middag ikväll',
          icon: Icons.restaurant_rounded,
          accentColor: memberColor,
          content: Row(
            children: [
              Text(
                mealEmoji,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mealTitle,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: displayPalette.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ));
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vänster (~58 %)
        Expanded(
          flex: 58,
          child: leftContent,
        ),
        if (rightCards.isNotEmpty) ...[
          const SizedBox(width: 24),
          // Höger (~42 %)
          Expanded(
            flex: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < rightCards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  rightCards[i],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Enkolumnslayout vid smalare skärmar (< 1400 lp, t.ex. 1280x720).
  Widget _buildSingleColumnLayout({
    required BuildContext context,
    required BoxConstraints constraints,
    required List<_PersondagItem> items,
    required bool isLowStimuli,
    required DisplayPalette displayPalette,
  }) {
    final h = constraints.maxHeight;
    if (items.isEmpty) {
      return Center(
        child: Text(
          isLowStimuli
              ? 'Inga planer inlagda för idag'
              : 'Inga planer idag — lediiigt! 🎉',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: displayPalette.textMuted,
          ),
        ),
      );
    }

    final hasSchema = items.any((it) => it.isSchema);
    if (hasSchema) {
      final schemaItem = items.firstWhere((it) => it.isSchema);
      final nonSchemaItems = items.where((it) => !it.isSchema).toList();

      var othersH = 0.0;
      var shownOthers = 0;
      const double minSchemaH = 220.0;
      final availableForOthers = (h - minSchemaH - 16.0).clamp(0.0, h);

      for (var i = 0; i < nonSchemaItems.length; i++) {
        final itemH = (nonSchemaItems[i].isRam ? 52.0 : 76.0) + 8.0;
        final isLast = i == nonSchemaItems.length - 1;
        final needed = isLast ? itemH : itemH + 36.0;
        if (othersH + needed <= availableForOthers) {
          othersH += itemH;
          shownOthers++;
        } else {
          break;
        }
      }

      final visibleOthers = nonSchemaItems.take(shownOthers).toList();
      final remainingOthers = nonSchemaItems.length - shownOthers;

      final schemaAllocatedH = (h - othersH - (remainingOthers > 0 ? 42.0 : 0.0) - (visibleOthers.isNotEmpty ? 16.0 : 0.0)).clamp(200.0, h);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: schemaAllocatedH,
            child: schemaItem.widget,
          ),
          for (final it in visibleOthers) ...[
            const SizedBox(height: 8),
            it.widget,
          ],
          if (remainingOthers > 0) ...[
            const SizedBox(height: 6),
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              child: Text(
                '+$remainingOthers till',
                style: DisplayTheme.moreCountStyle.copyWith(
                  fontSize: 19,
                  color: displayPalette.textMuted,
                ),
              ),
            ),
          ],
        ],
      );
    }

    var currentH = 0.0;
    var shownCount = 0;

    for (var i = 0; i < items.length; i++) {
      final itemH = (items[i].isRam ? 52.0 : 76.0) + 8.0;
      final isLast = i == items.length - 1;
      final neededH = isLast ? itemH : itemH + 36.0;

      if (currentH + neededH <= h) {
        currentH += itemH;
        shownCount++;
      } else {
        break;
      }
    }

    if (shownCount == 0 && items.isNotEmpty) {
      shownCount = 1;
    }

    final visibleItems =
        items.take(shownCount).map((it) => it.widget).toList();
    final remainingCount = items.length - shownCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibleItems.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          visibleItems[i],
        ],
        if (remainingCount > 0) ...[
          const SizedBox(height: 6),
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 6),
            child: Text(
              '+$remainingCount till',
              style: DisplayTheme.moreCountStyle.copyWith(
                fontSize: 19,
                color: displayPalette.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader(
    UserModel member,
    Color memberColor,
    String presence,
    DateTime now,
    DisplayPalette palette,
  ) {
    String dateStr;
    try {
      final rawDate = DateFormat('EEEE d MMMM', 'sv_SE').format(now);
      dateStr = rawDate.isNotEmpty
          ? rawDate[0].toUpperCase() + rawDate.substring(1)
          : rawDate;
    } catch (_) {
      dateStr = DateFormat('EEEE d MMMM').format(now);
    }

    final names = namnsdagFor(now).take(2).join(', ');
    final flag = isFlaggdag(now) ? ' 🇸🇪' : '';
    final nameLine = '$names$flag'.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FamilyMemberAvatar(
          member: member,
          size: 76,
          borderWidth: 3,
          showRing: true,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: palette.textPrimary,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildPresenceBadge(presence),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dateStr,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            if (nameLine.isNotEmpty)
              Text(
                nameLine,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: palette.textMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildChoresRow(
    List<Map<String, dynamic>> memberChores,
    DateTime now,
    DisplayPalette palette,
  ) {
    String choresContent;
    if (memberChores.isEmpty) {
      choresContent = 'Inga sysslor idag';
    } else {
      choresContent = memberChores.map((d) {
        final done = choreDoneOnDay(d, now);
        final title = (d['title'] as String? ?? '').trim();
        return '${done ? '✅' : '⬜'} $title';
      }).join('  ·  ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.cardBorder, width: 1),
      ),
      child: Row(
        children: [
          Icon(
            Icons.checklist_rounded,
            size: 22,
            color: palette.textMuted,
          ),
          const SizedBox(width: 10),
          Text(
            'Sysslor: ',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          Expanded(
            child: Text(
              choresContent,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: palette.isDark ? palette.textPrimary : const Color(0xFF2C3E50),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTomorrowRow(String tomorrowText, DisplayPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.cardBorder, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: palette.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tomorrowText,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: palette.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersondagItem {
  final int sortMinutes;
  final bool isRam;
  final bool isSchema;
  final Widget widget;

  const _PersondagItem({
    required this.sortMinutes,
    required this.isRam,
    this.isSchema = false,
    required this.widget,
  });
}
