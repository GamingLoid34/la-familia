import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/member_presence.dart';
import '../utils/person_match.dart';
import '../utils/schedule_time_utils.dart';
import '../widgets/busy_check_in_sheet.dart';
import '../widgets/planner_event_leading.dart';

class FamilyStatusPage extends StatefulWidget {
  const FamilyStatusPage({super.key});
  @override
  State<FamilyStatusPage> createState() => _FamilyStatusPageState();
}

class _FamilyStatusPageState extends State<FamilyStatusPage> {
  DateTime? _parseDate(dynamic v) {
    return parseYmdDate(v);
  }

  DateTime? _parseDateTime(Map<String, dynamic> d) {
    final base = _parseDate(d['date']);
    if (base == null) return null;
    final timeStr = d['time'] as String? ?? '';
    if (timeStr.isNotEmpty) {
      final tp = timeStr.split(':');
      if (tp.length >= 2) {
        return DateTime(
          base.year,
          base.month,
          base.day,
          int.parse(tp[0]),
          int.parse(tp[1]),
        );
      }
    }
    return base;
  }

  QueryDocumentSnapshot? _getCurrentEvent(
    UserModel m,
    List<QueryDocumentSnapshot> memberEvents,
  ) {
    final now = DateTime.now();
    for (final doc in memberEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final start = plannerTimedStart(d);
      final end = plannerTimedEnd(d);
      if (start != null && end != null && !now.isBefore(start) && now.isBefore(end)) {
        return doc;
      }
    }
    for (final doc in memberEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final start = _parseDateTime(d);
      if (start == null) continue;
      final end = start.add(const Duration(hours: 1));
      if (start.isBefore(now) && end.isAfter(now)) return doc;
    }
    for (final doc in memberEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final start = _parseDateTime(d);
      if (start != null && start.isAfter(now)) return doc;
    }
    return null;
  }

  void _openBusySheet(String familyId, String userName, String userUid) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BusyCheckInSheet(
        familyId: familyId,
        userName: userName,
        userUid: userUid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    final provider = context.watch<FamilyProvider>();
    final members = provider.familyMembers;
    final todayEvents = provider.todayEvents;
    final String? fid = provider.currentUser?.familyId;
    final UserModel? me = provider.currentUser;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: AppTheme.getBackground(),
            child: fid == null || fid.isEmpty
                ? CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      _buildSliverHeader(context, dayColor, textColor),
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Ingen familj inlagd.'),
                        ),
                      ),
                    ],
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('work_shifts')
                        .where('familyId', isEqualTo: fid)
                        .snapshots(),
                    builder: (context, ws) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('busy_sessions')
                            .where('familyId', isEqualTo: fid)
                            .snapshots(),
                        builder: (context, bs) {
                          final shiftDocs = ws.data?.docs ?? [];
                          final busyDocs = bs.data?.docs ?? [];

                          return CustomScrollView(
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              _buildSliverHeader(context, dayColor, textColor),
                              if (provider.isLoading)
                                const SliverToBoxAdapter(
                                  child: Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(40),
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                )
                              else if (members.isEmpty)
                                SliverToBoxAdapter(
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(16, 40, 16, 0),
                                    padding: const EdgeInsets.all(32),
                                    decoration: AppTheme.cardDecoration(),
                                    child: Column(
                                      children: [
                                        const Text('👨‍👩‍👧‍👦',
                                            style: TextStyle(fontSize: 48)),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Inga familjemedlemmar hittades',
                                          style: AppTheme.sectionTitleStyle,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Lägg till via Inställningar → Bjud in.',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 13,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (_, i) {
                                      final m = members[i];
                                      final memberEvents = todayEvents.where((doc) {
                                        return eventIncludesPerson(
                                            doc.data() as Map<String, dynamic>,
                                            uid: m.uid,
                                            name: m.name);
                                      }).toList();

                                      return _buildMemberCard(
                                        m,
                                        memberEvents,
                                        shiftDocs,
                                        busyDocs,
                                        dayColor,
                                      );
                                    },
                                    childCount: members.length,
                                  ),
                                ),
                              const SliverToBoxAdapter(child: SizedBox(height: 100)),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
      floatingActionButton: (me == null || fid == null || fid.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openBusySheet(fid, me.name, me.uid),
              backgroundColor: dayColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.event_busy_rounded),
              label: const Text('Jag är upptagen'),
            ),
    );
  }

  Widget _buildSliverHeader(
    BuildContext context,
    Color dayColor,
    Color textColor,
  ) {
    return SliverToBoxAdapter(
      child: Container(
        decoration: AppTheme.headerDecoration(),
        padding: AppTheme.paddingBelowStatusBar(context),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.arrow_back_ios_rounded, color: textColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Familjestatus',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(
    UserModel m,
    List<QueryDocumentSnapshot> memberEvents,
    List<QueryDocumentSnapshot> shiftDocs,
    List<QueryDocumentSnapshot> busyDocs,
    Color dayColor,
  ) {
    final presence = computeMemberPresence(
      m,
      memberTodayEvents: memberEvents,
      familyShiftDocs: shiftDocs,
      familyBusyDocs: busyDocs,
    );
    final currentEvent = _getCurrentEvent(m, memberEvents);
    Color mc;
    try {
      mc = Color(m.colorValue as int);
    } catch (_) {
      mc = dayColor;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: AppTheme.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: mc,
                  child: Text(
                    m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: presence.ringColor, width: 3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: presence.ringColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          presence.statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: presence.ringColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (currentEvent != null) ...[
                    const SizedBox(height: 4),
                    Builder(
                      builder: (_) {
                        final d = currentEvent.data() as Map<String, dynamic>;
                        final title = d['title'] as String? ?? '';
                        final start = _parseDateTime(d);
                        final now = DateTime.now();
                        final end = plannerTimedEnd(d) ??
                            start?.add(const Duration(hours: 1));
                        String timeInfo = '';
                        if (start != null && start.isAfter(now)) {
                          final mins = start.difference(now).inMinutes;
                          timeInfo = 'Om $mins min';
                        } else if (end != null && end.isAfter(now)) {
                          final mins = end.difference(now).inMinutes;
                          timeInfo = 'Slut om $mins min';
                        }
                        final accent = AppTheme.getDayAccentColor();
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            PlannerEventLeading(
                              data: d,
                              accentColor: accent,
                              emojiSize: 18,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$title${timeInfo.isNotEmpty ? ' · $timeInfo' : ''}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ] else
                    Text(
                      presence == MemberPresence.free ? 'Ledig 🟢' : '',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
