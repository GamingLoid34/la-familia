import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';

/// Rättvisestatistik över klarade sysslor (Fas 2) — ersätter poängligan.
class ChoreStatsPage extends StatefulWidget {
  const ChoreStatsPage({super.key});

  @override
  State<ChoreStatsPage> createState() => _ChoreStatsPageState();
}

enum _StatsRange { thisWeek, lastWeek, fourWeeks }

class _ChoreStatsPageState extends State<ChoreStatsPage> {
  _StatsRange _range = _StatsRange.thisWeek;

  DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  ({DateTime start, DateTime end}) _boundsFor(_StatsRange range) {
    final now = DateTime.now();
    final thisMon = _mondayOf(now);
    switch (range) {
      case _StatsRange.thisWeek:
        return (start: thisMon, end: thisMon.add(const Duration(days: 7)));
      case _StatsRange.lastWeek:
        final start = thisMon.subtract(const Duration(days: 7));
        return (start: start, end: thisMon);
      case _StatsRange.fourWeeks:
        return (
          start: thisMon.subtract(const Duration(days: 21)),
          end: thisMon.add(const Duration(days: 7)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final provider = context.watch<FamilyProvider>();
    final familyId = provider.currentUser?.familyId;
    final members = provider.familyMembers;
    final wide = WindowSize.of(context).isWide;
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: AppTheme.getBackground(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: AppTheme.headerDecoration(),
                padding: AppTheme.paddingBelowStatusBar(context),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_rounded, color: textColor),
                    ),
                    Expanded(
                      child: Text(
                        'Statistik',
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
            ),
            if (!wide || _range == _StatsRange.fourWeeks)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SegmentedButton<_StatsRange>(
                    segments: [
                      if (!wide) ...const [
                        ButtonSegment(
                            value: _StatsRange.thisWeek,
                            label: Text('Denna vecka')),
                        ButtonSegment(
                            value: _StatsRange.lastWeek, label: Text('Förra')),
                      ],
                      if (wide)
                        const ButtonSegment(
                            value: _StatsRange.thisWeek,
                            label: Text('Veckovis')),
                      const ButtonSegment(
                          value: _StatsRange.fourWeeks, label: Text('4 veckor')),
                    ],
                    selected: {
                      wide && _range != _StatsRange.fourWeeks
                          ? _StatsRange.thisWeek
                          : _range
                    },
                    onSelectionChanged: (s) =>
                        setState(() => _range = s.first),
                    style: ButtonStyle(
                      foregroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return dayColor;
                      }),
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return dayColor;
                        }
                        return Colors.white;
                      }),
                    ),
                  ),
                ),
              ),
            if (wide && _range != _StatsRange.fourWeeks)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(
                              () => _range = _StatsRange.fourWeeks),
                          child: const Text('Visa 4 veckor'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (familyId == null || familyId.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('Ingen familj kopplad.')),
              )
            else if (wide && _range != _StatsRange.fourWeeks)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _StatsPanel(
                          title: 'Denna vecka',
                          familyId: familyId,
                          members: members,
                          dayColor: dayColor,
                          bounds: _boundsFor(_StatsRange.thisWeek),
                          onTapMember: _showMemberLogs,
                        ),
                      ),
                      Expanded(
                        child: _StatsPanel(
                          title: 'Förra veckan',
                          familyId: familyId,
                          members: members,
                          dayColor: dayColor,
                          bounds: _boundsFor(_StatsRange.lastWeek),
                          onTapMember: _showMemberLogs,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: _StatsPanel(
                    title: '',
                    familyId: familyId,
                    members: members,
                    dayColor: dayColor,
                    bounds: _boundsFor(_range),
                    onTapMember: _showMemberLogs,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMemberLogs(
      BuildContext context, _MemberStats stats, Color color) {
    final fmt = DateFormat('EEE d MMM', 'sv');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final entries = List<Map<String, dynamic>>.from(stats.entries)
          ..sort((a, b) {
            final da = a['date'] as String? ?? '';
            final db = b['date'] as String? ?? '';
            return db.compareTo(da);
          });
        return wrapBottomSheet(
          ctx,
          DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (_, scroll) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    stats.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.count} sysslor · vikt ${stats.weightSum}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  ...entries.map((e) {
                    final title = e['choreTitle'] as String? ?? '';
                    final pik = e['piktogram'] as String? ?? '✅';
                    final weight = (e['weight'] as num?)?.toInt() ?? 0;
                    final dateStr = e['date'] as String? ?? '';
                    final parsed = parseDate(dateStr);
                    final dayLabel =
                        parsed != null ? fmt.format(parsed) : dateStr;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(pik, style: const TextStyle(fontSize: 22)),
                      title: Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(dayLabel),
                      trailing: Text(
                        '★$weight',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final String title;
  final String familyId;
  final List<UserModel> members;
  final Color dayColor;
  final ({DateTime start, DateTime end}) bounds;
  final void Function(BuildContext, _MemberStats, Color) onTapMember;

  const _StatsPanel({
    required this.title,
    required this.familyId,
    required this.members,
    required this.dayColor,
    required this.bounds,
    required this.onTapMember,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chore_log')
          .where('familyId', isEqualTo: familyId)
          .where('completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(bounds.start))
          .where('completedAt', isLessThan: Timestamp.fromDate(bounds.end))
          .snapshots(),
      builder: (context, snap) {
        Widget body;
        if (snap.hasError) {
          body = Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Kunde inte ladda statistik.\n${snap.error}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        } else if (!snap.hasData) {
          body = const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snap.data!.docs.isEmpty) {
          body = Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Inget loggat än — statistiken byggs när sysslor bockas av.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          );
        } else {
          final byUid = <String, _MemberStats>{};
          for (final doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final uid = d['whoUid'] as String? ?? '';
            if (uid.isEmpty) continue;
            final s = byUid.putIfAbsent(
                uid,
                () => _MemberStats(
                      uid: uid,
                      name: d['whoName'] as String? ?? '',
                    ));
            s.count++;
            s.weightSum += (d['weight'] as num?)?.toInt() ?? 0;
            s.entries.add(d);
          }

          final ordered = <_MemberStats>[];
          for (final m in members) {
            final s = byUid.remove(m.uid);
            if (s != null) {
              s.name = m.name;
              s.color = m.color;
              ordered.add(s);
            }
          }
          ordered.addAll(byUid.values);
          ordered.sort((a, b) => b.weightSum.compareTo(a.weightSum));

          final maxWeight = ordered.isEmpty
              ? 1
              : ordered
                  .map((e) => e.weightSum)
                  .reduce((a, b) => a > b ? a : b);

          body = Column(
            children: [
              for (final s in ordered)
                _memberCard(context, s, maxWeight),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Text(
                  title,
                  style: AppTheme.sectionTitleStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            body,
          ],
        );
      },
    );
  }

  Widget _memberCard(BuildContext context, _MemberStats s, int maxWeight) {
    Color barColor;
    try {
      barColor = Color(int.parse(
          s.color.startsWith('0x') ? s.color : '0xFF${s.color}',
          radix: 16));
    } catch (_) {
      barColor = dayColor;
    }
    final frac = maxWeight == 0 ? 0.0 : s.weightSum / maxWeight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTapMember(context, s, barColor),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.cardDecoration(radius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: barColor,
                      child: Text(
                        s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.name.split(' ').first,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      '${s.count} st · vikt ${s.weightSum}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: frac.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: barColor.withValues(alpha: 0.15),
                    color: barColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberStats {
  final String uid;
  String name;
  String color = 'ff2A6F97';
  int count = 0;
  int weightSum = 0;
  final List<Map<String, dynamic>> entries = [];

  _MemberStats({
    required this.uid,
    required this.name,
  });
}
