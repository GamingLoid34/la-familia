import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../../../app_theme.dart';
import '../../../models/user_model.dart';
import '../../../providers/family_provider.dart';
import '../../../utils/day_events.dart';
import '../../../utils/member_presence.dart';
import '../../../utils/person_match.dart';
import '../../../utils/schedule_display.dart';
import '../../../utils/schedule_time_utils.dart';
import '../display_chips.dart';
import '../display_formatters.dart';
import '../display_log.dart';
import '../display_module_registry.dart';
import '../display_palette.dart';
import '../display_scene_models.dart';
import '../display_school_menu_data.dart';
import '../../../utils/school_subject_utils.dart';
import '../../../utils/svenska_dagar.dart';
import '../../../widgets/member_avatar.dart';
import '../display_theme.dart';

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
    DisplaySchoolMenuData.instance.addListener(_onMenuChanged);
    _subscribe();
  }

  void _onMenuChanged() {
    if (mounted) setState(() {});
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
    DisplaySchoolMenuData.instance.removeListener(_onMenuChanged);
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

    try {
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
          .collection('busy_sessions')
          .where('familyId', isEqualTo: fid)
          .snapshots()
          .listen(
        (snap) {
          if (mounted) setState(() => _busyDocs = snap.docs);
        },
        onError: (e) {
          DisplayLog.instance.log('strömfel', 'Fel vid hämtning av busy_sessions i Idag-Nu: $e');
        },
      );
    } catch (e) {
      DisplayLog.instance.log(
        'strömfel',
        'Kunde inte starta Firestore-prenumeration i Idag-Nu: $e',
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

    final todayEvents = provider.todayEvents.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return eventOccursOnDay(d, now);
    }).toList();

    // ─── 1. Hero: Hitta nästa kommande händelse idag (FAS 5.4) ────────────
    // Krav: nästa kommande händelse idag för NÅGON medlem (inkl. familjehändelser),
    // hela dagen fram till midnatt, med namn i parentes som i lördagens visning.
    QueryDocumentSnapshot? nextUpcomingEvent;
    int minDiffMinutes = 999999;

    for (final doc in todayEvents) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['planningImportKind'] == 'schedule') continue;

      // Beräkna starttid för IDAG (now) via centrala hjälparen plannerTimedStart.
      final s = plannerTimedStart(d, now);
      if (s == null) continue;

      final diff = s.difference(now).inMinutes;
      // Infaller idag från och med now fram till midnatt
      if (diff >= 0 && sameCalendarDay(s, now) && diff < minDiffMinutes) {
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
        } else {
          final pName = (d['personName'] as String? ?? '').trim();
          if (pName.isNotEmpty) {
            who = ' (${pName.split(' ').first})';
          }
        }
      }

      final prefix = formatHeroPrefix(d['location'] as String?);
      final timePart = time.isNotEmpty ? ' $time' : '';
      heroText = '$prefix $countdownStr · $piktogram $title$timePart$who';
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

    final displayPalette = DisplayPalette.of(context);
    final heroTextColor = displayPalette.isDark
        ? palette.light
        : displayPalette.dayHeaderTextColor(now.weekday);

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
                child: Text(
                  'IDAG',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: palette.onColor,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Builder(
                builder: (context) {
                  final names = namnsdagFor(now).take(2).join(', ');
                  final flag = isFlaggdag(now) ? ' 🇸🇪' : '';
                  final nameLine = '$names$flag'.trim();

                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: dateStr),
                        if (nameLine.isNotEmpty)
                          TextSpan(
                            text: ' · $nameLine',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: displayPalette.textMuted,
                            ),
                          ),
                      ],
                    ),
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: displayPalette.textPrimary,
                    ),
                  );
                },
              ),
              const Spacer(),
              // Hero Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.base.withValues(
                    alpha: displayPalette.isDark ? 0.20 : 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: palette.base.withValues(
                      alpha: displayPalette.isDark ? 0.45 : 0.35,
                    ),
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
                      color: heroTextColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      heroText,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: heroTextColor,
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
                  displayPalette: displayPalette,
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
                      Expanded(
                        child: Text(
                          'Familjen',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: displayPalette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  content: familyEvents.isEmpty
                      ? Center(
                          child: Text(
                            'Inga familjehändelser idag',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 14,
                              color: displayPalette.textMuted,
                            ),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            QueryDocumentSnapshot? nextFamilyDoc;
                            int minFamilyDiff = 999999;
                            for (final doc in familyEvents) {
                              final d = doc.data() as Map<String, dynamic>;
                              final isOngoing =
                                  plannerTimedEventIsActiveNow(d, now);
                              final end = plannerTimedEnd(d, onDay: now);
                              final isPast = end != null && end.isBefore(now);
                              if (isOngoing || isPast) continue;
                              final s = plannerTimedStart(d, now);
                              if (s == null) continue;
                              final diff = s.difference(now).inMinutes;
                              if (diff >= 0 && diff < minFamilyDiff) {
                                minFamilyDiff = diff;
                                nextFamilyDoc = doc;
                              }
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: familyEvents.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, i) {
                                final doc = familyEvents[i];
                                final d = doc.data() as Map<String, dynamic>;
                                final isOngoing =
                                    plannerTimedEventIsActiveNow(d, now);
                                final end = plannerTimedEnd(d, onDay: now);
                                final isPast = end != null && end.isBefore(now);
                                final isNextUpcoming = doc == nextFamilyDoc &&
                                    !isOngoing &&
                                    !isPast;

                                String? badgeText;
                                if (isOngoing) {
                                  badgeText = 'PÅGÅR';
                                } else if (isNextUpcoming &&
                                    minFamilyDiff >= 0) {
                                  badgeText =
                                      formatCountdownMinutes(minFamilyDiff);
                                }

                                return DisplayActivityCard(
                                  data: d,
                                  memberColor: palette.base,
                                  isFolded: true,
                                  isLowStimuli: isLowStimuli,
                                  isOngoing: isOngoing,
                                  isPast: isPast,
                                  badgeText: badgeText,
                                );
                              },
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
                    displayPalette: displayPalette,
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
    required DisplayPalette displayPalette,
    required DateTime now,
    required bool isLowStimuli,
  }) {
    final memberColor = _memberColor(member, palette);
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
      final isOngoing = workShiftIsActiveNow(d, now);

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
              ? formatWallRange(sHm, eHm)
              : formatWallRange('–$eHm');
        } else {
          timeStr = formatWallRange(sHm, eHm);
        }
      } else {
        final startField = (d['startTime'] ?? d['start']) as String? ?? '';
        final endField = (d['endTime'] ?? d['end']) as String? ?? '';
        timeStr = formatWallRange(startField, endField);
      }

      final displayText =
          timeStr.isNotEmpty ? '$pik · $label · $timeStr' : '$pik · $label';

      items.add(DisplayRamPlate(
        piktogram: pik,
        label: label,
        time: timeStr,
        text: displayText,
        memberColor: memberColor,
        isOngoing: isOngoing,
      ));
    }

    // 2. Skola/schema klumpning
    bool lunchShown = false;
    for (final entry in buildScheduleDisplay(scheduleDocs, clumpSchool: true)) {
      if (entry is ScheduleClusterEntry) {
        final maps = entry.docs.map((d) => d.data() as Map<String, dynamic>);
        final pik = maps.isNotEmpty ? schemaPiktogramFor(maps.first) : '🏫';
        final label = maps.isNotEmpty ? schemaLabelFor(maps.first) : 'Skola';
        final span = scheduleTimeSpan(maps);
        final timeStr = formatWallRange(span.minStart ?? '', span.maxEnd);

        final sDt = parseHmOnDate(span.minStart, now);
        final eDt = parseHmOnDate(span.maxEnd, now);
        final isOngoing = sDt != null &&
            eDt != null &&
            !now.isBefore(sDt) &&
            now.isBefore(eDt);

        // FAS 6d Beslut 3 & FAS 6d.2: Pågående lektion i Idag & Nu-ramen (liten)
        String nuSuffix = '';
        if (isOngoing) {
          for (final doc in entry.docs) {
            final docMap = doc.data() as Map<String, dynamic>;
            final lStart = parseHmOnDate(docMap['time'] as String?, now);
            final lEnd = parseHmOnDate(docMap['endTime'] as String?, now);
            if (lStart != null && !now.isBefore(lStart) && (lEnd == null || now.isBefore(lEnd))) {
              final rawLessonTitle = (docMap['title'] as String? ?? '').trim();
              final lessonTitle = expandSchoolSubjectTitle(rawLessonTitle);
              final endStr = (docMap['endTime'] as String? ?? '').trim();
              if (lessonTitle.isNotEmpty) {
                final compactEnd = formatWallTime(endStr);
                nuSuffix = compactEnd.isNotEmpty
                    ? ' · nu: $lessonTitle (till $compactEnd)'
                    : ' · nu: $lessonTitle';
                break;
              }
            }
          }
        }

        items.add(LayoutBuilder(
          builder: (context, constraints) {
            final baseText = timeStr.isNotEmpty
                ? '$pik · $label · $timeStr'
                : '$pik · $label';
            final fullText = '$baseText$nuSuffix';

            bool showNu = false;
            if (nuSuffix.isNotEmpty && constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
              // Exakt TextPainter-mätning (som chipsen i 5.6):
              const double platePadding = 16.0;
              final double badgeW = isOngoing ? 72.0 : 0.0;
              final double availWidth = constraints.maxWidth - platePadding - badgeW;

              final textPainter = TextPainter(
                text: TextSpan(
                  text: fullText,
                  style: DisplayTheme.ramTextStyle,
                ),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout();

              showNu = textPainter.width <= availWidth;
            }

            final displayText = showNu ? fullText : baseText;

            return DisplayRamPlate(
              piktogram: pik,
              label: label,
              time: timeStr,
              text: displayText,
              memberColor: memberColor,
              isOngoing: isOngoing,
            );
          },
        ));

        // FAS 5.1, 5.1b & 5.7: Dagens lunch eller väggnudge under barnets skolram
        final lunchInfo = DisplaySchoolMenuData.instance.lunchFor(
          member.uid,
          now,
          widget.moduleContext.skolmatConfig ?? const DisplaySkolmatConfig(),
        );
        if (lunchInfo != null &&
            lunchInfo.lunch != null &&
            lunchInfo.lunch!.isNotEmpty) {
          lunchShown = true;
          final compactDish = formatCompactLunch(lunchInfo.lunch!);
          if (compactDish.isNotEmpty) {
            items.add(Padding(
              padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2),
              child: Text(
                '🍽 $compactDish',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: displayPalette.textMuted,
                ),
              ),
            ));
          }
        }
      }
    }

    // FAS 5.1b & 5.7: Om barnet saknar schemakluster idag (t.ex. söndag >= 16:00 eller ledig dag),
    // men en väggnudge för manuell matsedel är aktiv: visa den i barnets kolumn
    if (!lunchShown) {
      final lunchInfo = DisplaySchoolMenuData.instance.lunchFor(
        member.uid,
        now,
        widget.moduleContext.skolmatConfig ?? const DisplaySkolmatConfig(),
      );
      if (lunchInfo != null && lunchInfo.isNudge && lunchInfo.lunch != null) {
        final compactDish = formatCompactLunch(lunchInfo.lunch!);
        if (compactDish.isNotEmpty) {
          items.add(Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2),
            child: Text(
              '🍽 $compactDish',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: displayPalette.textMuted,
              ),
            ),
          ));
        }
      }
    }

    // 3. Vanliga aktiviteter
    QueryDocumentSnapshot? nextMemberDoc;
    int minMemberDiff = 999999;
    for (final doc in activityDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final isOngoing = plannerTimedEventIsActiveNow(d, now);
      final end = plannerTimedEnd(d, onDay: now);
      final isPast = end != null && end.isBefore(now);
      if (isOngoing || isPast) continue;
      final s = plannerTimedStart(d, now);
      if (s == null) continue;
      final diff = s.difference(now).inMinutes;
      if (diff >= 0 && diff < minMemberDiff) {
        minMemberDiff = diff;
        nextMemberDoc = doc;
      }
    }

    for (final doc in activityDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final isOngoing = plannerTimedEventIsActiveNow(d, now);
      final end = plannerTimedEnd(d, onDay: now);
      final isPast = end != null && end.isBefore(now);
      final isNextUpcoming = doc == nextMemberDoc && !isOngoing && !isPast;

      String? badgeText;
      if (isOngoing) {
        badgeText = 'PÅGÅR';
      } else if (isNextUpcoming && minMemberDiff >= 0) {
        badgeText = formatCountdownMinutes(minMemberDiff);
      }

      items.add(DisplayActivityCard(
        data: d,
        memberColor: memberColor,
        isLowStimuli: isLowStimuli,
        isOngoing: isOngoing,
        isPast: isPast,
        badgeText: badgeText,
      ));
    }

    return _buildColumnCard(
      displayPalette: displayPalette,
      header: Row(
        children: [
          // Fas 6d: Fas 4.6:s deklarerade undantag ("initialer på väggen") upphävs
          // på beställarens begäran. Färgringen är 2.5px i medlemsfärgen.
          FamilyMemberAvatar(
            member: member,
            size: 36,
            borderWidth: 2.5,
            showRing: true,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              firstName,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: displayPalette.textPrimary,
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
          ? Center(
              child: Text(
                'Inga händelser idag',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 14,
                  color: displayPalette.textMuted,
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
    required DisplayPalette displayPalette,
    required Widget header,
    required Widget content,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: displayPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: displayPalette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: displayPalette.isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
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
          Divider(height: 1, color: displayPalette.divider),
          const SizedBox(height: 6),
          Expanded(child: content),
        ],
      ),
    );
  }
}
