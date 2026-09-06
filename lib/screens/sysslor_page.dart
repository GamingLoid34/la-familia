import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/notification_service.dart';
import '../utils/chore_utils.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/permissions.dart';
import '../utils/person_match.dart';
import '../widgets/shimmer_list_placeholder.dart';
import '../widgets/stadskapet_guide_sheet.dart';
import '../widgets/stadzoner_seeder_sheet.dart';
import '../widgets/trasa_chip.dart';
import '../data/stadzoner.dart';
import 'agenda_page.dart';
import 'chore_stats_page.dart';
import 'chores_page.dart';
import 'staddag_page.dart';
import 'stadlage_page.dart';

class SysslorPage extends StatefulWidget {
  const SysslorPage({super.key});

  @override
  State<SysslorPage> createState() => _SysslorPageState();
}

class _SysslorPageState extends State<SysslorPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _filterPerson;
  String? _filterPersonUid;
  bool _doneExpanded = false;
  bool _recurringExpanded = false;

  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _onChoreCompleted() => _confettiController.play();

  bool _matchesPerson(
    Map<String, dynamic> d,
    UserModel? user,
    bool isFocus,
  ) {
    if (_filterPerson != null) {
      return assignedToPerson(
        d,
        uid: _filterPersonUid ?? '',
        name: _filterPerson!,
      );
    }
    if (isFocus && user != null) {
      return assignedToPerson(d, uid: user.uid, name: user.name);
    }
    return true;
  }

  ({
    List<QueryDocumentSnapshot> today,
    List<QueryDocumentSnapshot> open,
    List<QueryDocumentSnapshot> recurringLater,
    List<QueryDocumentSnapshot> done,
  }) _splitChores(
    List<QueryDocumentSnapshot> all,
    UserModel? user,
    bool isFocus,
  ) {
    final today = DateTime.now();
    final todayList = <QueryDocumentSnapshot>[];
    final openList = <QueryDocumentSnapshot>[];
    final recurringLaterList = <QueryDocumentSnapshot>[];
    final doneList = <QueryDocumentSnapshot>[];

    for (final doc in all) {
      final d = doc.data() as Map<String, dynamic>;
      final forToday = choreOccursOnDay(d, today);
      if (forToday) {
        if (_filterPerson != null) {
          if (!choreAssignedToOnDay(d, today,
              uid: _filterPersonUid ?? '', name: _filterPerson!)) {
            continue;
          }
        } else if (isFocus && user != null) {
          if (!choreAssignedToOnDay(d, today,
              uid: user.uid, name: user.name)) {
            continue;
          }
        }
      } else if (!_matchesPerson(d, user, isFocus)) {
        continue;
      }

      if (choreIsRecurring(d)) {
        if (!choreOccursOnDay(d, today)) {
          recurringLaterList.add(doc);
          continue;
        }
        if (choreDoneOnDay(d, today)) {
          doneList.add(doc);
        } else {
          todayList.add(doc);
        }
      } else if (d['isDone'] == true) {
        doneList.add(doc);
      } else if (choreOccursOnDay(d, today)) {
        todayList.add(doc);
      } else {
        openList.add(doc);
      }
    }

    int byTitle(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
      final ta = ((a.data() as Map)['chore'] as String? ??
              (a.data() as Map)['title'] as String? ??
              '')
          .toLowerCase();
      final tb = ((b.data() as Map)['chore'] as String? ??
              (b.data() as Map)['title'] as String? ??
              '')
          .toLowerCase();
      return ta.compareTo(tb);
    }

    todayList.sort(byTitle);
    openList.sort(byTitle);
    recurringLaterList.sort(byTitle);
    doneList.sort(byTitle);
    return (
      today: todayList,
      open: openList,
      recurringLater: recurringLaterList,
      done: doneList,
    );
  }

  Stream<QuerySnapshot>? _templatesStream(String? familyId) {
    if (familyId == null || familyId.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('chore_templates')
        .where('familyId', isEqualTo: familyId)
        .snapshots();
  }

  Future<void> _addChoreFromTemplate(
    Map<String, dynamic> template,
    String familyId,
    List<UserModel> members,
  ) async {
    final title = template['title'] as String? ?? '';
    if (title.isEmpty) return;
    final who = template['defaultWho'] as String? ?? '';
    String whoColor = '';
    if (who.isNotEmpty) {
      for (final m in members) {
        if (m.name == who) {
          whoColor = m.color;
          break;
        }
      }
    }
    final today = DateTime.now();
    final points = (template['points'] as int?) ?? 10;
    final pik = template['piktogram'] as String? ?? '✅';
    await FirebaseFirestore.instance.collection('chores').add({
      'chore': title,
      'piktogram': pik,
      'who': who,
      'whoUid': uidForName(members, who),
      'whoColor': whoColor,
      'isDone': false,
      'points': points,
      'isRecurring': false,
      'familyId': familyId,
      'dueDate': dateKey(today),
      'substeps': <Map<String, dynamic>>[],
      if (FirebaseAuth.instance.currentUser != null)
        'createdByUid': FirebaseAuth.instance.currentUser!.uid,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Syssla från mall tillagd'),
        backgroundColor: Color(0xFF6BAE75),
      ),
    );
  }

  Widget _buildChoreTemplatesStrip(
    String? familyId,
    List<UserModel> members,
    bool isParent,
    Color dayColor,
  ) {
    final stream = _templatesStream(familyId);
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        final raw = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
        final docs = List<QueryDocumentSnapshot>.from(raw)
          ..sort((a, b) {
            final ta = (a.data() as Map)['title'] as String? ?? '';
            final tb = (b.data() as Map)['title'] as String? ?? '';
            return ta.toLowerCase().compareTo(tb.toLowerCase());
          });
        if (docs.isEmpty && !isParent) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MALLAR', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Inga mallar ännu — de skapas när du lägger till en syssla.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final doc = docs[i];
                      final d = doc.data() as Map<String, dynamic>;
                      final title = d['title'] as String? ?? '';
                      final pik = d['piktogram'] as String? ?? '✅';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: familyId == null || familyId.isEmpty
                              ? null
                              : () => _addChoreFromTemplate(
                                    d,
                                    familyId,
                                    members,
                                  ),
                          onLongPress: isParent
                              ? () async {
                                  final del = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Ta bort mall?'),
                                      content: Text('"$title" tas bort.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('Avbryt'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red),
                                          child: const Text('Ta bort'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (del == true) {
                                    await NotificationService.cancel(doc.id);
                                    await doc.reference.delete();
                                  }
                                }
                              : null,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: dayColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: dayColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(pik,
                                    style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 120),
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddSheet(FamilyProvider provider, Color dayColor) {
    if (provider.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Laddar familjedata... försök igen'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final today = DateTime.now();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => wrapBottomSheet(
        ctx,
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Text('Lägg till syssla', style: AppTheme.sectionTitleStyle),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: dayColor.withValues(alpha: 0.15),
                  child: Icon(Icons.flash_on_rounded, color: dayColor),
                ),
                title: const Text('Snabb syssla',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Titel + vem — klar på några sekunder'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => QuickChoreSheet(
                      familyMembers: provider.familyMembers,
                      familyId: provider.currentUser?.familyId,
                      selectedDay: today,
                    ),
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: dayColor.withValues(alpha: 0.15),
                  child: Icon(Icons.checklist_rounded, color: dayColor),
                ),
                title: const Text('Ny syssla',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Piktogram, delsteg, vikt m.m.'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AddChoreSheet(
                      familyMembers: provider.familyMembers,
                      familyId: provider.currentUser?.familyId ?? '',
                      preselectedDay: today,
                      startOnForm: true,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openStadskapetGuide(BuildContext context, String familyId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StadskapetGuideSheet(familyId: familyId),
    );
  }

  void _openStadzonerSeeder(BuildContext context, String familyId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StadzonerSeederSheet(familyId: familyId),
    );
  }

  List<QueryDocumentSnapshot> _getTodayStadzoner(
    List<QueryDocumentSnapshot> all,
    UserModel? user,
    bool isFocus,
  ) {
    final today = DateTime.now();
    final zoner = <QueryDocumentSnapshot>[];

    for (final doc in all) {
      final d = doc.data() as Map<String, dynamic>;
      final stadKey = d['stadKey'] as String?;
      if (stadKey == null || stadKey.isEmpty) continue;
      if (!choreOccursOnDay(d, today)) continue;

      if (_filterPerson != null) {
        if (!choreAssignedToOnDay(d, today,
                uid: _filterPersonUid ?? '', name: _filterPerson!) &&
            (d['who'] as String? ?? '').isNotEmpty) {
          continue;
        }
      } else if (isFocus && user != null) {
        if (!choreAssignedToOnDay(d, today, uid: user.uid, name: user.name) &&
            (d['who'] as String? ?? '').isNotEmpty) {
          continue;
        }
      }

      zoner.add(doc);
    }

    zoner.sort((a, b) {
      final ka = (a.data() as Map<String, dynamic>)['stadKey'] as String? ?? '';
      final kb = (b.data() as Map<String, dynamic>)['stadKey'] as String? ?? '';
      final ia = stadZoner.indexWhere((z) => z.key == ka);
      final ib = stadZoner.indexWhere((z) => z.key == kb);
      return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
    });

    return zoner;
  }

  Widget _buildStadzonerHub({
    required List<QueryDocumentSnapshot> zoner,
    required Color dayColor,
    required String familyId,
    required bool isLowStimulus,
  }) {
    final today = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('STÄDZONER', style: AppTheme.sectionLabelStyle),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.help_outline_rounded, size: 18),
                    color: Colors.grey.shade500,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'Städskåpet & Färgguide',
                    onPressed: () => _openStadskapetGuide(context, familyId),
                  ),
                ],
              ),
              Text(
                'Färgen på kortet = trasan du tar',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 146,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: zoner.length,
            itemBuilder: (context, index) {
              final doc = zoner[index];
              final d = doc.data() as Map<String, dynamic>;
              final title = (d['chore'] as String?) ??
                  (d['title'] as String?) ??
                  'Zon';
              final pik = (d['piktogram'] as String?) ?? '🧹';
              final stadKey = d['stadKey'] as String?;
              final stadFarg = d['stadFarg'] as String?;
              final knownZon = stadZonByKey(stadKey);
              final farg = stadFarg ?? knownZon?.farg;
              final fargHex = knownZon?.fargHex ??
                  (farg == 'gul'
                      ? StadFarger.gulHex
                      : farg == 'vit'
                          ? StadFarger.vitHex
                          : farg == 'bla'
                              ? StadFarger.blaHex
                              : farg == 'rod'
                                  ? StadFarger.rodHex
                                  : null);
              final trasaLabel = knownZon?.trasaLabel;
              final verktyg = (d['verktyg'] as List? ??
                      knownZon?.verktyg ??
                      const [])
                  .cast<String>();

              Color? zoneColor;
              if (fargHex != null && fargHex.isNotEmpty) {
                try {
                  zoneColor = Color(int.parse(
                      'FF${fargHex.replaceFirst('#', '')}',
                      radix: 16));
                } catch (_) {}
              }

              final isDone = choreDoneOnDay(d, today);
              final substeps = (d['substeps'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              final totalSteps = substeps.length;
              final doneSteps =
                  substeps.where((s) => s['isDone'] == true).length;

              final cardColor = isLowStimulus
                  ? Colors.white
                  : (zoneColor != null
                      ? Color.alphaBlend(
                          zoneColor.withValues(alpha: isDone ? 0.04 : 0.12),
                          Colors.white)
                      : Colors.white);

              final borderColor = isLowStimulus
                  ? Colors.grey.shade300
                  : (zoneColor != null
                      ? zoneColor.withValues(alpha: isDone ? 0.2 : 0.45)
                      : Colors.grey.shade300);

              return Container(
                width: 170,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StadlagePage(
                            choreId: doc.id,
                            accent: zoneColor ?? dayColor,
                          ),
                        ),
                      );
                    },
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isDone ? 0.55 : 1.0,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: borderColor,
                              width: isLowStimulus ? 1 : 1.5),
                          boxShadow: isLowStimulus
                              ? null
                              : [
                                  BoxShadow(
                                    color: (zoneColor ?? Colors.black)
                                        .withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: TrasaChip(
                                    farg: farg,
                                    fargHex: fargHex,
                                    trasaLabel: trasaLabel,
                                    verktyg: verktyg,
                                    circleSize: 14,
                                  ),
                                ),
                                if (isDone)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF6BAE75),
                                    size: 18,
                                  ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(pik,
                                    style: const TextStyle(fontSize: 26)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      decoration: isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '$doneSteps av $totalSteps steg',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(Color dayColor, bool isParent, String familyId) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Sysslor',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Statistik',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChoreStatsPage(),
                ),
              );
            },
            icon: Icon(Icons.bar_chart_rounded, color: textColor),
          ),
          if (isParent)
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_vert_rounded, color: textColor),
              onSelected: (v) {
                if (v == 'seed_stadzoner') {
                  _openStadzonerSeeder(context, familyId);
                } else if (v == 'stadskapet_guide') {
                  _openStadskapetGuide(context, familyId);
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'seed_stadzoner',
                  child: Row(
                    children: [
                      Text('🧹', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 10),
                      Text('Skapa städzoner'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'stadskapet_guide',
                  child: Row(
                    children: [
                      Text('🧴', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 10),
                      Text('Städskåpet & Färgguide'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPersonFilter(List<UserModel> familyMembers, Color dayColor) {
    if (familyMembers.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          _FilterPill(
            label: 'Alla',
            selected: _filterPerson == null,
            color: dayColor,
            onTap: () => setState(() {
              _filterPerson = null;
              _filterPersonUid = null;
            }),
          ),
          ...familyMembers.map((m) {
            Color mc;
            try {
              mc = Color(m.colorValue);
            } catch (_) {
              mc = dayColor;
            }
            return _FilterPill(
              label: m.name.split(' ').first,
              selected: _filterPerson == m.name,
              color: mc,
              onTap: () => setState(() {
                if (_filterPerson == m.name) {
                  _filterPerson = null;
                  _filterPersonUid = null;
                } else {
                  _filterPerson = m.name;
                  _filterPersonUid = m.uid;
                }
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(title, style: AppTheme.sectionLabelStyle),
    );
  }

  Widget _choreRow(
    QueryDocumentSnapshot doc,
    Color dayColor,
    List<UserModel> members,
    String familyId,
    UserModel? user, {
    String? subtitle,
  }) {
    return RepaintBoundary(
      child: AgendaChoreRow(
        doc: doc,
        day: DateTime.now(),
        dayColor: dayColor,
        familyMembers: members,
        familyId: familyId,
        currentUser: user,
        allowDrag: canEditDoc(user, doc.data() as Map<String, dynamic>),
        onComplete: _onChoreCompleted,
        subtitle: subtitle,
      ),
    );
  }

  Widget _buildStaddagCard({
    required int zoneCount,
    required String nextDateStr,
    required Color dayColor,
  }) {
    final zoneText = zoneCount == 1 ? '1 zon' : '$zoneCount zoner';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaddagPage()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '🧹 Städdag · $zoneText · nästa: $nextDateStr',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(22),
      decoration: AppTheme.cardDecoration(),
      child: Center(
        child: Text(message, style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }

  List<Widget> _buildFocusSlivers({
    required List<QueryDocumentSnapshot> today,
    required List<QueryDocumentSnapshot> allChores,
    required Color dayColor,
    required List<UserModel> members,
    required String familyId,
    required UserModel? user,
    required bool isParent,
  }) {
    final name = user?.name.split(' ').first ?? '';
    final total = today.length;
    final done =
        today.where((d) => choreDoneOnDay(d.data() as Map<String, dynamic>, DateTime.now())).length;
    final todayZoner = _getTodayStadzoner(allChores, user, true);

    return [
      SliverToBoxAdapter(child: _buildHeader(dayColor, isParent, familyId)),
      if (todayZoner.isNotEmpty)
        SliverToBoxAdapter(
          child: _buildStadzonerHub(
            zoner: todayZoner,
            dayColor: dayColor,
            familyId: familyId,
            isLowStimulus: AppTheme.lowStimuli,
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mina sysslor', style: AppTheme.sectionTitleStyle),
              Text(
                '$name — $done av $total klara idag',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
      if (today.isEmpty)
        SliverToBoxAdapter(
          child: _buildEmptyCard('Inga sysslor idag — bra jobbat! 🎉'),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _choreRow(today[i], dayColor, members, familyId, user),
            childCount: today.length,
          ),
        ),
      SliverToBoxAdapter(
        child: SizedBox(height: navSafeBottom(context).bottom),
      ),
    ];
  }

  List<Widget> _buildParentSlivers({
    required List<QueryDocumentSnapshot> today,
    required List<QueryDocumentSnapshot> open,
    required List<QueryDocumentSnapshot> recurringLater,
    required List<QueryDocumentSnapshot> done,
    required List<QueryDocumentSnapshot> allChores,
    required Color dayColor,
    required List<UserModel> members,
    required String familyId,
    required UserModel? user,
    required bool isParent,
  }) {
    final todayZoner = _getTodayStadzoner(allChores, user, false);

    final slivers = <Widget>[
      SliverToBoxAdapter(child: _buildHeader(dayColor, isParent, familyId)),
      SliverToBoxAdapter(child: _buildPersonFilter(members, dayColor)),
      if (todayZoner.isNotEmpty)
        SliverToBoxAdapter(
          child: _buildStadzonerHub(
            zoner: todayZoner,
            dayColor: dayColor,
            familyId: familyId,
            isLowStimulus: AppTheme.lowStimuli,
          ),
        ),
      SliverToBoxAdapter(
        child: _buildChoreTemplatesStrip(
          familyId.isEmpty ? null : familyId,
          members,
          isParent,
          dayColor,
        ),
      ),
      SliverToBoxAdapter(child: _sectionLabel('IDAG')),
    ];

    if (today.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildEmptyCard('Inga sysslor för idag.'),
        ),
      );
    } else {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _choreRow(today[i], dayColor, members, familyId, user),
            childCount: today.length,
          ),
        ),
      );
    }

    slivers.add(SliverToBoxAdapter(child: _sectionLabel('ÖPPNA')));

    if (open.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildEmptyCard('Inga öppna sysslor med annat datum.'),
        ),
      );
    } else {
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _choreRow(open[i], dayColor, members, familyId, user),
            childCount: open.length,
          ),
        ),
      );
    }

    if (recurringLater.isNotEmpty) {
      final stadDocs = recurringLater.where((doc) {
        final d = doc.data() as Map<String, dynamic>;
        final k = d['stadKey'] as String?;
        return k != null && k.isNotEmpty;
      }).toList();
      final otherRecurring = recurringLater.where((doc) {
        final d = doc.data() as Map<String, dynamic>;
        final k = d['stadKey'] as String?;
        return k == null || k.isEmpty;
      }).toList();

      slivers.add(
        SliverToBoxAdapter(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _recurringExpanded = !_recurringExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Row(
                  children: [
                    Text('ÅTERKOMMANDE', style: AppTheme.sectionLabelStyle),
                    const SizedBox(width: 8),
                    Text(
                      '${recurringLater.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _recurringExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      if (_recurringExpanded) {
        if (stadDocs.isNotEmpty) {
          DateTime? nextStadDate;
          final today = DateTime.now();
          for (final doc in stadDocs) {
            final d = doc.data() as Map<String, dynamic>;
            final next = nextChoreOccurrence(d, today);
            if (next != null) {
              if (nextStadDate == null || next.isBefore(nextStadDate)) {
                nextStadDate = next;
              }
            }
          }
          nextStadDate ??= nextSaturdayAfter(today);
          const days = [
            '',
            'måndag',
            'tisdag',
            'onsdag',
            'torsdag',
            'fredag',
            'lördag',
            'söndag',
          ];
          final dayName = days[nextStadDate.weekday];
          final nextDateStr = '$dayName ${nextStadDate.day}/${nextStadDate.month}';

          slivers.add(
            SliverToBoxAdapter(
              child: _buildStaddagCard(
                zoneCount: stadDocs.length,
                nextDateStr: nextDateStr,
                dayColor: dayColor,
              ),
            ),
          );
        }

        if (otherRecurring.isNotEmpty) {
          final today = DateTime.now();
          slivers.add(
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final doc = otherRecurring[i];
                  final d = doc.data() as Map<String, dynamic>;
                  final next = nextChoreOccurrence(d, today);
                  final subtitle = next != null
                      ? formatNextOccurrence(next)
                      : 'nästa: > 14 dagar';
                  return _choreRow(
                    doc,
                    dayColor,
                    members,
                    familyId,
                    user,
                    subtitle: subtitle,
                  );
                },
                childCount: otherRecurring.length,
              ),
            ),
          );
        }
      }
    }

    if (done.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _doneExpanded = !_doneExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Row(
                  children: [
                    Text('KLARA', style: AppTheme.sectionLabelStyle),
                    const SizedBox(width: 8),
                    Text(
                      '${done.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _doneExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (_doneExpanded) {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) =>
                  _choreRow(done[i], dayColor, members, familyId, user),
              childCount: done.length,
            ),
          ),
        );
      }
    }

    slivers.add(
      SliverToBoxAdapter(
        child: SizedBox(height: navSafeBottom(context).bottom),
      ),
    );
    return slivers;
  }

  Widget _buildFab(Color dayColor, FamilyProvider fp) {
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    return Positioned(
      right: 16,
      bottom: bottom,
      child: FloatingActionButton(
        heroTag: 'sysslor_add',
        onPressed: () => _showAddSheet(fp, dayColor),
        backgroundColor: dayColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    context.select((FamilyProvider p) => (
          p.isLoading,
          p.currentUser,
          p.chores,
          p.familyMembers,
        ));
    final fp = context.read<FamilyProvider>();
    final user = fp.currentUser;
    final members = fp.familyMembers;
    final isFocus = user?.isFocusMode ?? false;
    final dayColor = AppTheme.getDayAccentColor();
    final familyId = user?.familyId ?? '';

    final split = _splitChores(fp.chores, user, isFocus);

    return Container(
      decoration: AppTheme.getBackground(),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (fp.isLoading)
            const ShimmerListPlaceholder()
          else
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: isFocus
                  ? _buildFocusSlivers(
                      today: split.today,
                      allChores: fp.chores,
                      dayColor: dayColor,
                      members: members,
                      familyId: familyId,
                      user: user,
                      isParent: user?.isParent ?? false,
                    )
                  : _buildParentSlivers(
                      today: split.today,
                      open: split.open,
                      recurringLater: split.recurringLater,
                      done: split.done,
                      allChores: fp.chores,
                      dayColor: dayColor,
                      members: members,
                      familyId: familyId,
                      user: user,
                      isParent: user?.isParent ?? false,
                    ),
            ),
          if (!fp.isLoading && !isFocus) _buildFab(dayColor, fp),
          ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.1,
            numberOfParticles: 20,
            colors: [dayColor, Colors.amber, Colors.pink, Colors.purple],
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.getTextColor(),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
