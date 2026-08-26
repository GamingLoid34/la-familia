import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/minute_ticker.dart';
import '../utils/person_match.dart';
import '../services/user_service.dart';
import '../widgets/activity_detail_sheet.dart';
import '../widgets/routine_card.dart';
import '../widgets/today_chores_sheet.dart';
import '../widgets/planner_event_leading.dart';
import '../widgets/weather_widgets.dart';
import 'meal_planner_page.dart';
import 'timer_page.dart';
import 'shopping_list_page.dart';

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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Selectera dataskivor — bygger bara om när dessa referenser ändras (Fas 2½).
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
    final isFocus = user?.isFocusMode ?? false;

    return Container(
      decoration: AppTheme.getBackground(),
      child: isFocus
          ? _buildFocusView(familyProvider)
          : _buildParentView(familyProvider),
    );
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
    List<QueryDocumentSnapshot> list;
    if (me == null) {
      list = chores.toList();
    } else {
      list = chores
          .where((doc) => assignedToPerson(
              doc.data() as Map<String, dynamic>,
              uid: me.uid,
              name: me.name))
          .toList();
    }
    return list
        .where((doc) =>
            (doc.data() as Map<String, dynamic>)['isDone'] != true)
        .toList();
  }

  Widget _buildParentView(FamilyProvider provider) {
    final user = provider.currentUser;
    final todayEvents = _eventsForMe(provider.todayEvents, user);
    final chores = _choresForMe(provider.chores, user);

    if (!WindowSize.of(context).isWide) {
      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(user)),
          // Rutin visas på Hem: morgonrutin före 12, kvällsrutin från 18.
          ..._myRoutineSlivers(provider, user),
          // Ikväll-kort: dagens middag om planerad (Etapp 12).
          if (provider.todayMeals.isNotEmpty)
            SliverToBoxAdapter(child: _buildTonightMeal(provider)),
          SliverToBoxAdapter(
            child: _buildSection(
              'MIN DAGSLINJE',
              _buildTimeline(todayEvents),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildSection(
              'MINA SYSSLOR',
              _buildChoreSummary(
                chores,
                onlyAssignedTo: user?.name,
                onlyAssignedToUid: user?.uid,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildSection('SNABBVERKTYG', _buildQuickTools()),
          ),
          if (DateTime.now().hour >= 18)
            SliverToBoxAdapter(
              child: _buildSection(
                  'I MORGON', _buildTomorrowPreview(provider, user)),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(user)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: WindowSize.navScrollPadding),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vänster: dagslinje + sysslor
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSection(
                          'MIN DAGSLINJE',
                          _buildTimeline(todayEvents),
                        ),
                        _buildSection(
                          'MINA SYSSLOR',
                          _buildChoreSummary(
                            chores,
                            onlyAssignedTo: user?.name,
                            onlyAssignedToUid: user?.uid,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Höger: rutin / ikväll / imorgon / snabbverktyg
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._routineColumnChildren(provider, user),
                        if (provider.todayMeals.isNotEmpty)
                          _buildTonightMeal(provider),
                        if (DateTime.now().hour >= 18)
                          _buildSection(
                            'I MORGON',
                            _buildTomorrowPreview(provider, user),
                          ),
                        _buildSection('SNABBVERKTYG', _buildQuickTools()),
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

  /// Min rutin för rätt tid på dygnet: morgon före 12, kväll från 18.
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

  /// Kvällens förhandsvisning av morgondagen — förutsägbarhet minskar ångest.
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

  Widget _buildFocusView(FamilyProvider provider) {
    final user = provider.currentUser;
    final name = user?.name.split(' ').first ?? '';
    final docs = _getSortedDocs(
      _eventsForMe(provider.todayEvents, user),
    );
        
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(user)),
        if (docs.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildFocusMainCard(docs.first)),
          if (docs.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Text('Senare idag',
                    style: AppTheme.sectionLabelStyle),
              ),
            ),
          if (docs.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 110,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length - 1,
                  itemBuilder: (_, i) =>
                      _buildFocusSmallCard(docs[i + 1]),
                ),
              ),
            ),
        ] else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    const Text('😌', style: TextStyle(fontSize: 52)),
                    const SizedBox(height: 12),
                    Text('Ingen planering idag, $name!',
                        style: AppTheme.sectionTitleStyle,
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  /// "om 45 min" istället för bara klockslag — NPF: hur länge till, inte när.
  String _untilLabel(Duration left) {
    if (left.inMinutes < 1) return 'nu!';
    if (left.inMinutes < 60) return 'om ${left.inMinutes} min';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return m == 0 ? 'om $h h' : 'om $h h $m min';
  }

  Widget _buildFocusMainCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? '';
    final date = parseDateTime(data);
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '';
    final dayColor = AppTheme.getDayAccentColor();
    final palette = AppTheme.dayPalette();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          PlannerEventLeadingHero(data: data, accentColor: dayColor),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          ValueListenableBuilder<DateTime>(
            valueListenable: MinuteTicker.now,
            builder: (context, now, _) {
              final left = date?.difference(now);
              final started = left != null && left.isNegative;
              final showBar =
                  left != null && !started && left.inMinutes <= 60;
              return Column(
                children: [
                  Text(
                    started
                        ? 'Pågår nu · började $timeStr'
                        : (left != null
                            ? '$timeStr · ${_untilLabel(left)}'
                            : timeStr),
                    style: TextStyle(
                        fontSize: 18,
                        color: dayColor,
                        fontWeight: FontWeight.w600),
                  ),
                  if (showBar) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (left.inSeconds / 3600).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor:
                            palette.base.withValues(alpha: 0.15),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(dayColor),
                      ),
                    ),
                  ],
                  if (left != null &&
                      !started &&
                      left.inMinutes >= 1) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      icon: Icon(Icons.timer_rounded,
                          size: 18, color: palette.deep),
                      label: Text('Starta nedräkning',
                          style: TextStyle(color: palette.deep)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: dayColor.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TimerPage(
                            initialSeconds: left.inSeconds,
                            label: 'Tills $title börjar',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text('Du klarar det! 💪',
              style: TextStyle(
                  fontSize: 15, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildFocusSmallCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? '';
    final date = parseDateTime(data);
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '';
    final dayColor = AppTheme.getDayAccentColor();
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PlannerEventLeading(
            data: data,
            accentColor: dayColor,
            emojiSize: 28,
          ),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          Text(timeStr,
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade500)),
        ],
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
            // Mjuka ljuscirklar — ger djup utan att störa läsbarheten.
            // Utelämnas i lågstimuli-läge.
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
                  textColor: textColor,
                ),
                const SizedBox(width: 8),
              ],
              if (user != null)
                _DashboardViewModeToggle(user: user, textColor: textColor),
            ],
          ),
          const SizedBox(height: 2),
          Text(dateStr,
              style: TextStyle(
                  fontSize: 13,
                  color: textColor.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          if (firstName.isNotEmpty)
            Text('God morgon, $firstName!',
                style: TextStyle(fontSize: 15, color: textColor)),
        ],
      );
  }

  Widget _buildTimeline(List<QueryDocumentSnapshot> rawDocs) {
    final docs = _getSortedDocs(rawDocs);
        
    if (docs.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: AppTheme.cardDecoration(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📅', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Inga aktiviteter för dig idag — lägg till under Planering.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 125,
      child: ValueListenableBuilder<DateTime>(
        valueListenable: MinuteTicker.now,
        builder: (context, now, _) {
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final date = parseDateTime(d);
              final title = d['title'] as String? ?? '';
              final dayColor = AppTheme.getDayAccentColor();
              final isCurrent = date != null &&
                  date.isBefore(now) &&
                  date.add(const Duration(hours: 1)).isAfter(now);
              return GestureDetector(
                onTap: () => _openDetail(docs[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin:
                      const EdgeInsets.only(right: 10, bottom: 8, top: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  transformAlignment: Alignment.center,
                  transform: isCurrent
                      ? Matrix4.diagonal3Values(1.05, 1.05, 1.05)
                      : Matrix4.identity(),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? dayColor
                        : dayColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: isCurrent
                        ? null
                        : Border.all(color: dayColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlannerEventLeading(
                        data: d,
                        accentColor: dayColor,
                        emojiSize: 18,
                        leadingStyle: isCurrent
                            ? PlannerEventLeadingStyle.onColoredSurface
                            : PlannerEventLeadingStyle.normal,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date != null
                            ? DateFormat('HH:mm').format(date)
                            : '',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? Colors.white
                              : AppTheme.getTextColor(),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isCurrent)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('NU',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChoreSummary(
    List<QueryDocumentSnapshot> chores, {
    String? onlyAssignedTo,
    String? onlyAssignedToUid,
  }) {
    final total = chores.length;
    final done = chores.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data['isDone'] == true;
    }).length;
    final dayColor = AppTheme.getDayAccentColor();
    final progress = total > 0 ? done / total : 0.0;

    if (total == 0 && onlyAssignedTo != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: AppTheme.cardDecoration(),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: dayColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Inga väntande sysslor just nu.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TodayChoresSheet(
            onlyAssignedTo: onlyAssignedTo,
            onlyAssignedToUid: onlyAssignedToUid),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$done av $total klara',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    AlwaysStoppedAnimation<Color>(dayColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTools() {
    final palette = AppTheme.dayPalette();
    final tools = <Map<String, dynamic>>[
      {
        'icon': Icons.timer_rounded,
        'label': 'Timer',
        'page': const TimerPage(),
      },
      {
        'icon': Icons.shopping_cart_rounded,
        'label': 'Inköp',
        'page': const ShoppingListPage(),
      },
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: tools
            .map((t) => Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => t['page'] as Widget)),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      height: 88,
                      decoration: AppTheme.cardDecoration(radius: 18),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Färgad mjuk bricka bakom ikonen — dagens kulör.
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: palette.base.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(t['icon'] as IconData,
                                size: 24, color: palette.deep),
                          ),
                          const SizedBox(height: 6),
                          Text(t['label'] as String,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.getTextColor()),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(title, style: AppTheme.sectionLabelStyle),
          ),
          child,
        ],
      ),
    );
  }

  void _openDetail(QueryDocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ActivityDetailSheet(docSnapshot: doc),
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

/// Snabbväxling hem-skärmen: samma alternativ som under Inställningar.
class _DashboardViewModeToggle extends StatelessWidget {
  final UserModel user;
  final Color textColor;

  const _DashboardViewModeToggle({
    required this.user,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final modes = <String>[];
    final labels = <String>[];
    if (user.isParent) {
      modes.addAll(['parent', 'focus']);
    } else if (user.role == 'youth') {
      modes.addAll(['youth', 'focus']);
    } else {
      modes.addAll(['child', 'focus']);
    }
    labels.addAll(['Allt', 'Fokus']);
    final selectedIndex = modes.contains(user.viewMode)
        ? modes.indexOf(user.viewMode)
        : 0;

    return ToggleButtons(
      direction: Axis.horizontal,
      borderRadius: BorderRadius.circular(12),
      selectedColor: textColor,
      fillColor: textColor.withValues(alpha: 0.22),
      color: textColor.withValues(alpha: 0.65),
      selectedBorderColor: Colors.transparent,
      borderColor: textColor.withValues(alpha: 0.35),
      constraints: const BoxConstraints(
        minHeight: 34,
        minWidth: 0,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      isSelected: List.generate(modes.length, (i) => i == selectedIndex),
      onPressed: (index) async {
        await UserService.updateViewMode(user.uid, modes[index]);
      },
      children: [
        for (final l in labels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}