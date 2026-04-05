import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../widgets/activity_detail_sheet.dart';
import '../widgets/member_day_sheet.dart';
import '../widgets/member_avatar.dart';
import 'agenda_page.dart';
import 'timer_page.dart';
import 'shopping_list_page.dart';
import 'screen_rules_page.dart';
import 'family_status_page.dart';
import 'work_schedule_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static DateTime? _parseDate(dynamic v) {
    try {
      if (v is Timestamp) return v.toDate();
      if (v is String) {
        final p = v.split('-');
        if (p.length >= 3) return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    } catch (_) {}
    return null;
  }

  static DateTime? _parseDateTime(Map<String, dynamic> d) {
    try {
      final base = _parseDate(d['date']);
      if (base == null) return null;
      final timeStr = d['time'] as String? ?? '';
      if (timeStr.isNotEmpty) {
        final tp = timeStr.split(':');
        if (tp.length >= 2) {
          return DateTime(base.year, base.month, base.day,
              int.parse(tp[0]), int.parse(tp[1]));
        }
      }
      return base;
    } catch (_) {}
    return null;
  }

  List<QueryDocumentSnapshot> _getSortedDocs(List<QueryDocumentSnapshot> rawDocs) {
    final list = rawDocs.toList();
    list.sort((a, b) {
      final dA = _parseDateTime(a.data() as Map<String, dynamic>);
      final dB = _parseDateTime(b.data() as Map<String, dynamic>);
      if (dA == null && dB == null) return 0;
      if (dA == null) return 1;
      if (dB == null) return -1;
      return dA.compareTo(dB);
    });
    return list;
  }

  void _openMemberDaySheet(FamilyProvider provider, UserModel member) {
    final events = provider.todayEvents.where((doc) {
      final persons = ((doc.data() as Map<String, dynamic>)['persons'] as List? ?? [])
          .cast<String>();
      return persons.contains(member.name);
    }).toList();
    events.sort((a, b) {
      final dA = _parseDateTime(a.data() as Map<String, dynamic>);
      final dB = _parseDateTime(b.data() as Map<String, dynamic>);
      if (dA == null && dB == null) return 0;
      if (dA == null) return 1;
      if (dB == null) return -1;
      return dA.compareTo(dB);
    });
    final chores = provider.chores.where((doc) {
      final who =
          (doc.data() as Map<String, dynamic>)['who'] as String? ?? '';
      return who == member.name;
    }).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberDaySheet(
        member: member,
        currentUser: provider.currentUser,
        memberEvents: events,
        memberChores: chores,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Hämta vår samlade data via Provider!
    final familyProvider = context.watch<FamilyProvider>();

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

  Widget _buildParentView(FamilyProvider provider) {
    final user = provider.currentUser;
    final todayEvents = provider.todayEvents;
    final chores = provider.chores;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(user)),
        SliverToBoxAdapter(child: _buildFamilyStrip(context, provider)),
        SliverToBoxAdapter(
          child: _buildSection(
            'DAGSTIDSLINJE',
            _buildTimeline(todayEvents),
          ),
        ),
        SliverToBoxAdapter(
          child: _buildSection('HÄRNÄST', _buildNextCard(todayEvents)),
        ),
        SliverToBoxAdapter(
          child: _buildSection('SYSSLOR IDAG', _buildChoreSummary(chores)),
        ),
        SliverToBoxAdapter(
          child: _buildSection('SNABBVERKTYG', _buildQuickTools()),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildFocusView(FamilyProvider provider) {
    final user = provider.currentUser;
    final name = user?.name.split(' ').first ?? '';
    final docs = _getSortedDocs(provider.todayEvents);
        
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

  Widget _buildFocusMainCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final piktogram = data['piktogram'] as String? ?? '📅';
    final title = data['title'] as String? ?? '';
    final date = _parseDateTime(data);
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '';
    final dayColor = AppTheme.getDayAccentColor();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Text(piktogram, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(timeStr,
              style: TextStyle(
                  fontSize: 18,
                  color: dayColor,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Text('Du klarar det! 💪',
              style: TextStyle(
                  fontSize: 15, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildFocusSmallCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final piktogram = data['piktogram'] as String? ?? '📅';
    final title = data['title'] as String? ?? '';
    final date = _parseDateTime(data);
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '';
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(piktogram, style: const TextStyle(fontSize: 28)),
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

  Widget _buildFamilyStrip(BuildContext context, FamilyProvider provider) {
    final members = provider.familyMembers;
    if (members.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('FAMILJEN', style: AppTheme.sectionLabelStyle),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tryck för aktiviteter, sysslor och energi',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 124,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: members.length,
              itemBuilder: (_, i) =>
                  _buildFamilyMemberCard(context, provider, members[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyMemberCard(
    BuildContext context,
    FamilyProvider provider,
    UserModel member,
  ) {
    Color mc;
    try {
      mc = Color(member.colorValue as int);
    } catch (_) {
      mc = AppTheme.getDayAccentColor();
    }
    final energyColor = _energyColor(member.energy);
    final first = member.name.split(' ').first;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openMemberDaySheet(provider, member),
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            width: 108,
            child: Ink(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              decoration: AppTheme.cardDecoration(radius: 22).copyWith(
                border:
                    Border.all(color: mc.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FamilyMemberAvatar(member: member, size: 46),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: energyColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: mc,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Visa dag',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Icon(Icons.expand_more_rounded,
                          size: 12, color: Colors.grey.shade400),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(UserModel? user) {
    final dayColor = AppTheme.getDayAccentColor();
    final now = DateTime.now();
    final weekday = now.weekday;
    final textColor = AppTheme.getNpfTextColor(weekday);
    final dayName = _swedishWeekday(weekday);
    final dateStr = DateFormat('d MMMM', 'sv').format(now);
    final firstName = user?.name.split(' ').first ?? '';

    return Container(
      decoration: BoxDecoration(
        color: dayColor,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(dayName,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor)),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FamilyStatusPage())),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_rounded,
                          color: textColor, size: 16),
                      const SizedBox(width: 4),
                      Text('Familjestatus',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(dateStr,
              style: TextStyle(
                  fontSize: 13,
                  color: textColor.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          if (firstName.isNotEmpty)
            Text('God morgon, $firstName! ☀️',
                style: TextStyle(fontSize: 15, color: textColor)),
        ],
      ),
    );
  }

  Color _energyColor(int energy) {
    switch (energy) {
      case 4:
        return const Color(0xFF6BAE75);
      case 3:
        return const Color(0xFFEDD87A);
      case 2:
        return const Color(0xFFE8A5B0);
      default:
        return const Color(0xFFD95F4B);
    }
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
                'Inga aktiviteter idag — lägg till i Planering!',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    return SizedBox(
      height: 125,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final d = docs[i].data() as Map<String, dynamic>;
          final date = _parseDateTime(d);
          final title = d['title'] as String? ?? '';
          final piktogram = d['piktogram'] as String? ?? '📅';
          final dayColor = AppTheme.getDayAccentColor();
          final isCurrent = date != null &&
              date.isBefore(now) &&
              date.add(const Duration(hours: 1)).isAfter(now);
          return GestureDetector(
            onTap: () => _openDetail(docs[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10, bottom: 8, top: 4),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              transformAlignment: Alignment.center,
              transform: isCurrent
                  ? (Matrix4.identity()..scale(1.05))
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
                  Text(piktogram,
                      style: const TextStyle(fontSize: 18)),
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
      ),
    );
  }

  Widget _buildNextCard(List<QueryDocumentSnapshot> rawDocs) {
    final docs = _getSortedDocs(rawDocs);
        
    if (docs.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          children: [
            const Text('✨', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text('Inget planerat härnäst',
                style: AppTheme.sectionTitleStyle,
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Tryck på Planering för att lägga till',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    QueryDocumentSnapshot? targetDoc;
    for (var d in docs) {
      final dt = _parseDateTime(d.data() as Map<String, dynamic>);
      if (dt != null && dt.add(const Duration(hours: 1)).isAfter(now)) {
        targetDoc = d;
        break;
      }
    }
    final doc = targetDoc ?? docs.last;

    final d = doc.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? '';
    final piktogram = d['piktogram'] as String? ?? '📅';
    final date = _parseDateTime(d);
    final checklist =
        (d['checklist'] as List? ?? []).cast<Map<String, dynamic>>();
    final dayColor = AppTheme.getDayAccentColor();
    final diffMin = date != null
        ? date.difference(now).inMinutes
        : 0;
    final timeLabel = diffMin <= 0
        ? 'NU PÅGÅR'
        : diffMin < 60
            ? 'OM ${diffMin} MIN'
            : 'OM ${(diffMin / 60).round()} H';
    final timeStr =
        date != null ? DateFormat('HH:mm').format(date) : '';

    return GestureDetector(
      onTap: () => _openDetail(doc),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: AppTheme.cardDecoration().copyWith(
          border: Border(
            left: BorderSide(color: dayColor, width: 6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: dayColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(timeLabel,
                    style: TextStyle(
                        color: dayColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(piktogram,
                      style: const TextStyle(fontSize: 40)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text(timeStr,
                            style: TextStyle(
                                fontSize: 14,
                                color: dayColor,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              if (checklist.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...checklist.map((item) => _ChecklistTile(
                      item: item,
                      docId: doc.id,
                      dayColor: dayColor,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoreSummary(List<QueryDocumentSnapshot> chores) {
    final total = chores.length;
    final done = chores.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data['isDone'] == true;
    }).length;
    final dayColor = AppTheme.getDayAccentColor();
    final progress = total > 0 ? done / total : 0.0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AgendaPage(initialTab: AgendaTab.chores),
        ),
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
    final tools = [
      {'emoji': '⏱️', 'label': 'Timer', 'page': const TimerPage()},
      {'emoji': '📱', 'label': 'Skärmtid', 'page': const ScreenRulesPage()},
      {'emoji': '🛒', 'label': 'Inköp', 'page': const ShoppingListPage()},
      {'emoji': '💼', 'label': 'Arbete', 'page': const WorkSchedulePage()},
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
                      height: 80,
                      decoration: AppTheme.cardDecoration(radius: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(t['emoji'] as String,
                              style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 4),
                          Text(t['label'] as String,
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
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

class _ChecklistTile extends StatefulWidget {
  final Map<String, dynamic> item;
  final String docId;
  final Color dayColor;

  const _ChecklistTile({
    required this.item,
    required this.docId,
    required this.dayColor,
  });

  @override
  State<_ChecklistTile> createState() => _ChecklistTileState();
}

class _ChecklistTileState extends State<_ChecklistTile>
    with SingleTickerProviderStateMixin {
  late bool _isDone;
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _isDone = widget.item['isDone'] == true;
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: 1.2)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isDone = !_isDone);
    _anim.forward().then((_) => _anim.reverse());
    FirebaseFirestore.instance
        .collection('planner_events')
        .doc(widget.docId)
        .get()
        .then((doc) {
      if (!doc.exists) return;
      final list = List<Map<String, dynamic>>.from(
          (doc.data()!['checklist'] as List? ?? []));
      final idx = list.indexWhere(
          (e) => e['item'] == widget.item['item']);
      if (idx != -1) {
        list[idx] = {...list[idx], 'isDone': _isDone};
        doc.reference.update({'checklist': list});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _isDone
              ? widget.dayColor.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ScaleTransition(
              scale: _scale,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color:
                      _isDone ? widget.dayColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _isDone
                          ? widget.dayColor
                          : Colors.grey.shade400,
                      width: 2),
                ),
                child: _isDone
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.item['item'] as String? ?? '',
                style: TextStyle(
                    fontSize: 15,
                    decoration: _isDone
                        ? TextDecoration.lineThrough
                        : null,
                    color: _isDone
                        ? Colors.grey.shade400
                        : AppTheme.getTextColor()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}