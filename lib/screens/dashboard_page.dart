import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/chore_utils.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/member_presence.dart';
import '../utils/minute_ticker.dart';
import '../utils/person_match.dart';
import '../widgets/member_avatar.dart';
import '../widgets/member_day_sheet.dart';
import '../widgets/min_dag_view.dart';
import '../widgets/routine_card.dart';
import '../widgets/today_chores_sheet.dart';
import '../widgets/weather_widgets.dart';
import 'meal_planner_page.dart';
import 'min_dag_page.dart';
import 'verktyg_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    MinuteTicker.ensureRunning();
  }

  Stream<QuerySnapshot>? _shiftsStream(String? fid) => fid == null || fid.isEmpty
      ? null
      : FirebaseFirestore.instance
          .collection('families')
          .doc(fid)
          .collection('work_shifts')
          .snapshots();

  Stream<QuerySnapshot>? _busyStream(String? fid) => fid == null || fid.isEmpty
      ? null
      : FirebaseFirestore.instance
          .collection('families')
          .doc(fid)
          .collection('busy_sessions')
          .snapshots();

  List<QueryDocumentSnapshot> _getSortedDocs(List<QueryDocumentSnapshot> rawDocs) {
    final list = rawDocs.toList();
    list.sort((a, b) {
      final dA = parseDateTime(a.data() as Map<String, dynamic>);
      final dB = parseDateTime(b.data() as Map<String, dynamic>);
      if (dA == null && dB == null) return 0;
      if (dA == null) return 1;
      if (dB == null) return -1;
      return dA.compareTo(dB);
    });
    return list;
  }

  /// Kalender som importerats som ”schema” visas bara under Scheman, inte på hem.
  bool _showEventOnHome(Map<String, dynamic> d) {
    if (d['source'] == 'calendar') {
      final kind = d['planningImportKind'] as String? ?? 'schedule';
      return kind == 'activity';
    }
    return true;
  }

  List<QueryDocumentSnapshot> _eventsForMe(
    List<QueryDocumentSnapshot> todayEvents,
    UserModel? me,
  ) {
    if (me == null) return todayEvents;
    return todayEvents.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!_showEventOnHome(d)) return false;
      if (eventHasNoPersons(d)) return true;
      return eventIncludesPerson(d, uid: me.uid, name: me.name);
    }).toList();
  }

  List<QueryDocumentSnapshot> _choresForMe(
    List<QueryDocumentSnapshot> chores,
    UserModel? me,
  ) {
    final today = DateTime.now();
    return chores.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!choreOccursOnDay(d, today)) return false;
      if (me == null) return true;
      return choreAssignedToOnDay(d, today, uid: me.uid, name: me.name);
    }).toList();
  }

  DateTime _computeEndTime(DateTime start, Map<String, dynamic> d) {
    final endTimeStr = (d['endTime'] as String? ?? '').trim();
    if (endTimeStr.isNotEmpty) {
      final parts = endTimeStr.split(':');
      if (parts.length >= 2) {
        final eh = int.tryParse(parts[0]);
        final em = int.tryParse(parts[1]);
        if (eh != null && em != null) {
          return DateTime(start.year, start.month, start.day, eh, em);
        }
      }
    }
    return start.add(const Duration(minutes: 60));
  }

  _HeroEventInfo _computeHeroInfo(
    FamilyProvider provider,
    UserModel? user,
    DateTime now,
  ) {
    final myEvents = _eventsForMe(provider.todayEvents, user);
    final timedToday = <({Map<String, dynamic> data, DateTime start, DateTime end})>[];

    for (final doc in myEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final parsed = parseDateTime(d);
      final timeStr = (d['time'] as String? ?? '').trim();
      if (parsed != null && timeStr.isNotEmpty) {
        final end = _computeEndTime(parsed, d);
        timedToday.add((data: d, start: parsed, end: end));
      }
    }

    timedToday.sort((a, b) => a.start.compareTo(b.start));

    // 1. Pågående aktivitet
    for (final ev in timedToday) {
      if (!now.isBefore(ev.start) && now.isBefore(ev.end)) {
        final totalMs = ev.end.difference(ev.start).inMilliseconds;
        final elapsedMs = now.difference(ev.start).inMilliseconds;
        final progress = totalMs > 0 ? (elapsedMs / totalMs).clamp(0.0, 1.0) : 0.0;
        final endStr = DateFormat('HH:mm').format(ev.end);
        final title = ev.data['title'] as String? ?? 'Aktivitet';
        final pik = ev.data['piktogram'] as String? ?? '📅';

        return _HeroEventInfo(
          isOngoing: true,
          isUpcoming: false,
          isTomorrow: false,
          isEmpty: false,
          heroTag: 'NU',
          title: title,
          timeInfo: 'slutar $endStr',
          piktogram: pik,
          progress: progress,
        );
      }
    }

    // 2. Nästa kommande aktivitet idag
    for (final ev in timedToday) {
      if (ev.start.isAfter(now)) {
        final diffMin = ev.start.difference(now).inMinutes;
        String tag;
        if (diffMin <= 1) {
          tag = 'OM 1 MIN';
        } else if (diffMin < 60) {
          tag = 'OM $diffMin MIN';
        } else if (diffMin < 120) {
          tag = 'OM 1 TIMME';
        } else {
          tag = 'OM ${(diffMin / 60).round()} TIMMAR';
        }

        final startStr = DateFormat('HH:mm').format(ev.start);
        final title = ev.data['title'] as String? ?? 'Aktivitet';
        final pik = ev.data['piktogram'] as String? ?? '📅';

        return _HeroEventInfo(
          isOngoing: false,
          isUpcoming: true,
          isTomorrow: false,
          isEmpty: false,
          heroTag: tag,
          title: title,
          timeInfo: startStr,
          piktogram: pik,
        );
      }
    }

    // 3. Inga fler aktiviteter idag -> kolla morgondagen
    final tomEvents = _eventsForMe(provider.tomorrowEvents, user);
    final timedTomorrow = <({Map<String, dynamic> data, DateTime start})>[];

    for (final doc in tomEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final parsed = parseDateTime(d);
      final timeStr = (d['time'] as String? ?? '').trim();
      if (parsed != null && timeStr.isNotEmpty) {
        timedTomorrow.add((data: d, start: parsed));
      }
    }

    timedTomorrow.sort((a, b) => a.start.compareTo(b.start));

    if (timedTomorrow.isNotEmpty) {
      final firstTom = timedTomorrow.first;
      final tStr = DateFormat('HH:mm').format(firstTom.start);
      final title = firstTom.data['title'] as String? ?? 'Aktivitet';
      final pik = firstTom.data['piktogram'] as String? ?? '📅';

      return _HeroEventInfo(
        isOngoing: false,
        isUpcoming: false,
        isTomorrow: true,
        isEmpty: false,
        heroTag: 'Inget mer idag 🎈',
        title: '$pik $title',
        timeInfo: 'I morgon kl $tStr',
        piktogram: pik,
        subtext: 'I morgon kl $tStr',
      );
    }

    return _HeroEventInfo(
      isOngoing: false,
      isUpcoming: false,
      isTomorrow: false,
      isEmpty: true,
      heroTag: 'Inget mer idag 🎈',
      title: 'Inget mer planerat idag',
      timeInfo: '',
      piktogram: '🎈',
      subtext: now.hour >= 18 ? 'Ha en fin kväll!' : 'Ha en fin dag!',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    context.select((FamilyProvider p) => (
          p.isLoading,
          p.currentUser,
          p.todayEvents,
          p.tomorrowEvents,
          p.chores,
          p.routines,
          p.todayMeals,
          p.familyMembers,
          p.todayNotes,
        ));
    final familyProvider = context.read<FamilyProvider>();

    if (familyProvider.isLoading) {
      return Container(
        decoration: AppTheme.getBackground(),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = familyProvider.currentUser;
    final isFocusOrChild = user?.isFocusMode == true || user?.isChildMode == true;

    // FAS H2: Fokus- och barnläge får den inbäddade Min dag-tidslinjen.
    if (isFocusOrChild) {
      return const MinDagView(embedded: true);
    }

    // Förälder- och ungdomsläge får "Upp näst"-hemmet.
    return Container(
      decoration: AppTheme.getBackground(),
      child: _buildParentYouthView(familyProvider),
    );
  }

  Widget _buildParentYouthView(FamilyProvider provider) {
    final user = provider.currentUser;
    final fid = user?.familyId ?? provider.currentUser?.familyId;
    final chores = _choresForMe(provider.chores, user);
    final dayColor = AppTheme.getDayAccentColor();

    return StreamBuilder<QuerySnapshot>(
      stream: _shiftsStream(fid),
      builder: (context, shiftSnap) {
        final shifts = shiftSnap.data?.docs ?? const <QueryDocumentSnapshot>[];

        return StreamBuilder<QuerySnapshot>(
          stream: _busyStream(fid),
          builder: (context, busySnap) {
            final busyDocs = busySnap.data?.docs ?? const <QueryDocumentSnapshot>[];

            if (!WindowSize.of(context).isWide) {
              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(user)),
                  SliverToBoxAdapter(
                    child: _buildNuNastHero(context, provider, user, dayColor),
                  ),
                  ..._myRoutineSlivers(provider, user),
                  SliverToBoxAdapter(
                    child: _buildFamilyRow(context, provider, user, shifts, busyDocs),
                  ),
                  if (provider.todayMeals.isNotEmpty)
                    SliverToBoxAdapter(child: _buildTonightMeal(provider)),
                  SliverToBoxAdapter(
                    child: _buildChoresCard(context, chores, user, dayColor),
                  ),
                  if (DateTime.now().hour >= 18)
                    SliverToBoxAdapter(
                      child: _buildSection(
                        'I MORGON',
                        _buildTomorrowPreview(provider, user),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: navSafeBottom(context).bottom + 20),
                  ),
                ],
              );
            }

            // Bred skärm
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(user)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: navSafeBottom(context),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Vänster kolumn
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildNuNastHero(context, provider, user, dayColor),
                                _buildFamilyRow(context, provider, user, shifts, busyDocs),
                                ..._routineColumnChildren(provider, user),
                              ],
                            ),
                          ),
                          // Höger kolumn
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (provider.todayMeals.isNotEmpty)
                                  _buildTonightMeal(provider),
                                _buildChoresCard(context, chores, user, dayColor),
                                if (DateTime.now().hour >= 18)
                                  _buildSection(
                                    'I MORGON',
                                    _buildTomorrowPreview(provider, user),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNuNastHero(
    BuildContext context,
    FamilyProvider provider,
    UserModel? user,
    Color dayColor,
  ) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: MinuteTicker.now,
      builder: (context, now, _) {
        final info = _computeHeroInfo(provider, user, now);
        final isLowStimuli = AppTheme.lowStimuli;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const MinDagPage(),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: AppTheme.cardDecoration(radius: 20).copyWith(
                  border: info.isOngoing
                      ? Border.all(color: const Color(0xFF2F3B45), width: 2)
                      : Border.all(color: dayColor.withValues(alpha: 0.3), width: 1.2),
                  boxShadow: isLowStimuli
                      ? null
                      : [
                          BoxShadow(
                            color: info.isOngoing
                                ? const Color(0xFF2F3B45).withValues(alpha: 0.12)
                                : dayColor.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: info.isOngoing
                                ? const Color(0xFF2F3B45)
                                : dayColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            info.heroTag,
                            style: TextStyle(
                              color: info.isOngoing ? Colors.white : dayColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (info.isEmpty || info.isTomorrow) ...[
                      Row(
                        children: [
                          const Text('🎈', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (info.subtext != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    info.subtext!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Text(info.piktogram,
                              style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  info.timeInfo,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (info.isOngoing) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: info.progress,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF2F3B45)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFamilyRow(
    BuildContext context,
    FamilyProvider provider,
    UserModel? user,
    List<QueryDocumentSnapshot> shifts,
    List<QueryDocumentSnapshot> busyDocs,
  ) {
    final members = provider.familyMembers;
    if (members.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      'IDAG I FAMILJEN',
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: members.map((m) {
            final memberEvents = provider.todayEvents.where((doc) {
              return eventIncludesPerson(
                doc.data() as Map<String, dynamic>,
                uid: m.uid,
                name: m.name,
              );
            }).toList();

            final presence = computeMemberPresence(
              m,
              memberTodayEvents: memberEvents,
              familyShiftDocs: shifts,
              familyBusyDocs: busyDocs,
            );

            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => MemberDaySheet(
                    member: m,
                    currentUser: user,
                    initialDay: DateTime.now(),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FamilyMemberAvatar(
                      member: m,
                      size: 50,
                      presenceColor: presence.ringColor,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 58,
                      child: Text(
                        m.name.split(' ').first,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildChoresCard(
    BuildContext context,
    List<QueryDocumentSnapshot> chores,
    UserModel? user,
    Color dayColor,
  ) {
    final uncompleted = chores
        .where((d) => (d.data() as Map<String, dynamic>)['isDone'] != true)
        .toList();

    if (uncompleted.isEmpty) return const SizedBox.shrink();

    final count = uncompleted.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => TodayChoresSheet(
              onlyAssignedTo: user?.name,
              onlyAssignedToUid: user?.uid,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: AppTheme.cardDecoration(radius: 16),
            child: Row(
              children: [
                const Text('✅', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$count ${count == 1 ? 'syssla' : 'sysslor'} kvar idag',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: dayColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _routineColumnChildren(
      FamilyProvider provider, UserModel? user) {
    if (user == null) return const [];
    final hour = DateTime.now().hour;
    final String? wantedType =
        hour < 12 ? 'morning' : (hour >= 18 ? 'evening' : null);
    if (wantedType == null) return const [];
    final docs = provider.routines.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return d['ownerUid'] == user.uid &&
          (d['type'] as String? ?? 'morning') == wantedType;
    }).toList();
    if (docs.isEmpty) return const [];
    return [
      _buildSection(
        wantedType == 'morning' ? 'MIN MORGON' : 'MIN KVÄLL',
        Column(
          children: [
            for (final doc in docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RoutineCard(routineDoc: doc),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _buildTonightMeal(FamilyProvider provider) {
    final d = provider.todayMeals.first.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? '';
    if (title.isEmpty) return const SizedBox.shrink();
    final emoji = d['emoji'] as String? ?? '🍽️';
    final palette = AppTheme.dayPalette();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MealPlannerPage())),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: AppTheme.cardDecoration(radius: 16),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ikväll: $title',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: palette.deep, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _myRoutineSlivers(FamilyProvider provider, UserModel? user) {
    if (user == null) return const [];
    final hour = DateTime.now().hour;
    final String? wantedType =
        hour < 12 ? 'morning' : (hour >= 18 ? 'evening' : null);
    if (wantedType == null) return const [];

    final docs = provider.routines.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return d['ownerUid'] == user.uid &&
          (d['type'] as String? ?? 'morning') == wantedType;
    }).toList();
    if (docs.isEmpty) return const [];

    return [
      SliverToBoxAdapter(
        child: _buildSection(
          wantedType == 'morning' ? 'MIN MORGON' : 'MIN KVÄLL',
          Column(
            children: [
              for (final doc in docs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RoutineCard(routineDoc: doc),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildTomorrowPreview(FamilyProvider provider, UserModel? user) {
    final events = _getSortedDocs(
      _eventsForMe(provider.tomorrowEvents, user),
    );
    final dayColor = AppTheme.getDayAccentColor();

    if (events.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: AppTheme.cardDecoration(),
        child: Row(
          children: [
            const Text('😌', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Inget planerat i morgon — sov gott!',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: events.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final t = (d['time'] as String? ?? '').trim();
          final title = d['title'] as String? ?? '';
          final pik = d['piktogram'] as String? ?? '📅';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(pik, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  child: Text(
                    t.isEmpty ? '–' : t,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: dayColor,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(UserModel? user) {
    final now = DateTime.now();
    final weekday = now.weekday;
    final textColor = AppTheme.getNpfTextColor(weekday);
    final dayName = _swedishWeekday(weekday);
    final dateStr = DateFormat('d MMMM', 'sv').format(now);
    final firstName = user?.name.split(' ').first ?? '';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
        decoration: AppTheme.headerDecoration(weekday),
        child: Stack(
          children: [
            if (!AppTheme.lowStimuli) ...[
              Positioned(
                top: -36,
                right: -28,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                bottom: -50,
                right: 60,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
            ],
            Padding(
              padding: AppTheme.paddingBelowStatusBar(context),
              child: _buildHeaderContent(user, textColor, dayName, dateStr,
                  firstName),
            ),
          ],
        ),
      ),
    );
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 10) return 'God morgon';
    if (hour >= 10 && hour < 12) return 'God förmiddag';
    if (hour >= 12 && hour < 18) return 'God eftermiddag';
    if (hour >= 18 && hour < 23) return 'God kväll';
    return 'God natt';
  }

  Widget _buildHeaderContent(UserModel? user, Color textColor, String dayName,
      String dateStr, String firstName) {
    final provider = context.watch<FamilyProvider>();
    final hasWeather = provider.hasHomeLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                dayName,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
            ),
            if (hasWeather) ...[
              WeatherHeaderBadge(
                lat: provider.homeLat!,
                lon: provider.homeLon!,
                placeName: provider.homeName,
                textColor: textColor,
              ),
              const SizedBox(width: 6),
            ],
            IconButton(
              icon: const Text('🧰', style: TextStyle(fontSize: 18)),
              tooltip: 'Verktyg',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VerktygPage()),
              ),
            ),
            const SizedBox(width: 4),
            if (user != null)
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: textColor.withValues(alpha: 0.18),
                  foregroundColor: textColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Text('🧭', style: TextStyle(fontSize: 14)),
                label: const Text(
                  'Min dag',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => const MinDagPage(),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(dateStr,
            style: TextStyle(
                fontSize: 13, color: textColor.withValues(alpha: 0.85))),
        const SizedBox(height: 4),
        if (firstName.isNotEmpty)
          Text('${_timeGreeting()}, $firstName!',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor)),
      ],
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(title, style: AppTheme.sectionLabelStyle),
          ),
          child,
        ],
      ),
    );
  }

  String _swedishWeekday(int weekday) {
    const days = [
      '', 'Måndag', 'Tisdag', 'Onsdag', 'Torsdag',
      'Fredag', 'Lördag', 'Söndag'
    ];
    return days[weekday.clamp(1, 7)];
  }
}

class _HeroEventInfo {
  final bool isOngoing;
  final bool isUpcoming;
  final bool isTomorrow;
  final bool isEmpty;
  final String heroTag;
  final String title;
  final String timeInfo;
  final String piktogram;
  final double progress;
  final String? subtext;

  _HeroEventInfo({
    required this.isOngoing,
    required this.isUpcoming,
    required this.isTomorrow,
    required this.isEmpty,
    required this.heroTag,
    required this.title,
    required this.timeInfo,
    required this.piktogram,
    this.progress = 0.0,
    this.subtext,
  });
}