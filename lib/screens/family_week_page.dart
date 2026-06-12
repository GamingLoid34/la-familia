import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/conflict_detector.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';
import '../widgets/busy_check_in_sheet.dart';
import '../widgets/family_notes_strip.dart';
import '../widgets/member_day_sheet.dart';
import '../widgets/week_grid.dart';
import 'family_status_page.dart';
import 'meal_planner_page.dart';

/// Familjen-fliken (ROADMAP Etapp 9): hela familjens vecka i ett ögonkast,
/// med konfliktvarningar när flera vuxna är upptagna samtidigt.
class FamilyWeekPage extends StatefulWidget {
  const FamilyWeekPage({super.key});

  @override
  State<FamilyWeekPage> createState() => _FamilyWeekPageState();
}

class _FamilyWeekPageState extends State<FamilyWeekPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  void _shiftWeek(int weeks) => setState(() => _weekStart =
      DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks));

  Stream<QuerySnapshot>? _eventsStream(String? fid) =>
      (fid == null || fid.isEmpty)
          ? null
          : FirebaseFirestore.instance
              .collection('planner_events')
              .where('familyId', isEqualTo: fid)
              .snapshots();

  Stream<QuerySnapshot>? _shiftsStream(String? fid) =>
      (fid == null || fid.isEmpty)
          ? null
          : FirebaseFirestore.instance
              .collection('work_shifts')
              .where('familyId', isEqualTo: fid)
              .snapshots();

  void _openCell(FamilyProvider provider, UserModel member, DateTime day,
      List<QueryDocumentSnapshot> dayEvents) {
    final chores = provider.chores.where((doc) {
      return assignedToPerson(doc.data() as Map<String, dynamic>,
          uid: member.uid, name: member.name);
    }).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberDaySheet(
        member: member,
        currentUser: provider.currentUser,
        memberEvents: dayEvents,
        memberChores: chores,
      ),
    );
  }

  Future<void> _takeResponsibility(
      FamilyProvider provider, ScheduleConflict c) async {
    final me = provider.currentUser;
    if (me == null) return;
    final now = DateTime.now();
    final label =
        '${DateFormat('EEE', 'sv').format(c.day)} ${DateFormat('HH:mm').format(c.start)}';
    try {
      await FirebaseFirestore.instance.collection('family_notes').add({
        'familyId': me.familyId,
        'fromUid': me.uid,
        'fromName': me.name,
        'fromColor': me.color,
        'date': dateKey(c.day),
        'createdAt': FieldValue.serverTimestamp(),
        'text': '✋ ${me.name.split(' ').first} tar ansvar $label',
        'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Noterat på familjetavlan! ✋'),
            backgroundColor: Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('takeResponsibility misslyckades',
          error: e, stackTrace: stack);
    }
  }

  void _showConflict(FamilyProvider provider, ScheduleConflict c) {
    final names = c.adults.map((a) => a.name.split(' ').first).join(' & ');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Krock i schemat 🚨'),
        content: Text(
          '${DateFormat('EEEE d/M', 'sv').format(c.day)} '
          '${DateFormat('HH:mm').format(c.start)}–${DateFormat('HH:mm').format(c.end)}\n\n'
          '$names är upptagna samtidigt. Vem tar hämtningar och barn under '
          'den tiden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stäng'),
          ),
          FilledButton.icon(
            icon: const Text('✋'),
            label: const Text('Jag tar det'),
            onPressed: () => _takeResponsibility(provider, c),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<FamilyProvider>();
    final fid = provider.currentUser?.familyId;
    final members = provider.familyMembers;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppTheme.getBackground(),
        child: StreamBuilder<QuerySnapshot>(
          stream: _eventsStream(fid),
          builder: (ctx, evSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: _shiftsStream(fid),
              builder: (ctx2, shSnap) {
                final events =
                    evSnap.data?.docs ?? const <QueryDocumentSnapshot>[];
                final shifts =
                    shSnap.data?.docs ?? const <QueryDocumentSnapshot>[];
                final conflicts = detectAdultConflicts(
                  members: members,
                  events: events,
                  shifts: shifts,
                  weekStart: _weekStart,
                );

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(context)),
                    const SliverToBoxAdapter(child: FamilyNotesStrip()),
                    if (conflicts.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _buildConflictStrip(provider, conflicts),
                      ),
                    SliverToBoxAdapter(child: _buildWeekNav()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: members.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(40),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              )
                            : WeekGrid(
                                members: members,
                                events: events,
                                weekStart: _weekStart,
                                onCellTap: (m, day, dayEvents) =>
                                    _openCell(provider, m, day, dayEvents),
                              ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'family_busy',
        backgroundColor: AppTheme.getDayAccentColor(),
        foregroundColor:
            AppTheme.getNpfTextColor(DateTime.now().weekday),
        icon: const Icon(Icons.do_not_disturb_on_rounded),
        label: const Text('Jag är upptagen'),
        onPressed: () {
          final me = provider.currentUser;
          if (me == null || fid == null || fid.isEmpty) return;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => BusyCheckInSheet(
              familyId: fid,
              userName: me.name,
              userUid: me.uid,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final weekday = DateTime.now().weekday;
    final textColor = AppTheme.getNpfTextColor(weekday);

    return Container(
      decoration: AppTheme.headerDecoration(weekday),
      padding: AppTheme.paddingBelowStatusBar(context, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Familjen',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor)),
                const SizedBox(height: 2),
                Text('Veckans översikt — tryck på en ruta för detaljer',
                    style: TextStyle(
                        fontSize: 13,
                        color: textColor.withValues(alpha: 0.85))),
              ],
            ),
          ),
          _headerPill(
            textColor,
            Icons.restaurant_rounded,
            'Mat',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MealPlannerPage()),
            ),
          ),
          const SizedBox(width: 6),
          _headerPill(
            textColor,
            Icons.insights_rounded,
            'Status',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FamilyStatusPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPill(
      Color textColor, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 16),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekNav() {
    final palette = AppTheme.dayPalette();
    final weekEnd = DateTime(
        _weekStart.year, _weekStart.month, _weekStart.day + 6);
    final label =
        '${DateFormat('d MMM', 'sv').format(_weekStart)} – ${DateFormat('d MMM', 'sv').format(weekEnd)}';
    final isThisWeek = _weekStart == _mondayOf(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _shiftWeek(-1),
          ),
          Expanded(
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          if (!isThisWeek)
            TextButton(
              onPressed: () =>
                  setState(() => _weekStart = _mondayOf(DateTime.now())),
              child: Text('Idag',
                  style: TextStyle(
                      color: palette.deep, fontWeight: FontWeight.w700)),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _shiftWeek(1),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictStrip(
      FamilyProvider provider, List<ScheduleConflict> conflicts) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: conflicts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = conflicts[i];
          final label =
              '${DateFormat('EEE', 'sv').format(c.day)} ${DateFormat('HH:mm').format(c.start)}';
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _showConflict(provider, c),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE57368)),
                ),
                child: Row(
                  children: [
                    const Text('🚨', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      '$label — båda upptagna',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF93331F),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
