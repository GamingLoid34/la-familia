import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/chore_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../utils/chore_utils.dart';
import '../utils/date_utils.dart';
import '../utils/day_events.dart';
import '../utils/event_actions.dart';
import '../utils/layout.dart';
import '../utils/permissions.dart';
import '../utils/person_match.dart';
import '../screens/staddag_page.dart';
import '../utils/recurrence.dart';
import 'activity_detail_sheet.dart';
import 'member_avatar.dart';
import 'planner_event_leading.dart';

/// Självförsörjande dagbläddring för en medlem (FAS D1).
/// Svep eller bläddra med pilar mellan dagar (±365 dagar).
class MemberDaySheet extends StatefulWidget {
  final UserModel member;
  final UserModel? currentUser;
  final DateTime initialDay;

  MemberDaySheet({
    super.key,
    required this.member,
    required this.currentUser,
    DateTime? initialDay,
  }) : initialDay = initialDay ?? DateTime.now();

  @override
  State<MemberDaySheet> createState() => _MemberDaySheetState();
}

class _MemberDaySheetState extends State<MemberDaySheet> {
  static const int _initialPageIndex = 365;
  static const int _totalPageCount = 731;

  late final PageController _pageController;
  late int _currentPage;
  late final DateTime _baseDay;
  late int _energyDisplay;

  @override
  void initState() {
    super.initState();
    _baseDay = DateTime(
      widget.initialDay.year,
      widget.initialDay.month,
      widget.initialDay.day,
    );
    _currentPage = _initialPageIndex;
    _pageController = PageController(initialPage: _initialPageIndex);
    _energyDisplay = widget.member.energy;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _dayForIndex(int index) {
    return _baseDay.add(Duration(days: index - _initialPageIndex));
  }

  int _indexForDay(DateTime d) {
    final norm = DateTime(d.year, d.month, d.day);
    return _initialPageIndex + norm.difference(_baseDay).inDays;
  }

  Color _memberColor() {
    try {
      return Color(widget.member.colorValue);
    } catch (_) {
      return AppTheme.getDayAccentColor();
    }
  }

  String _energyLabel(int e) {
    return ['', '😔 Låg', '😌 OK', '😊 Bra', '🚀 Topp'][e.clamp(1, 4)];
  }

  @override
  Widget build(BuildContext context) {
    final mc = _memberColor();
    final currentDay = _dayForIndex(_currentPage);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = currentDay.year == today.year &&
        currentDay.month == today.month &&
        currentDay.day == today.day;
    final isFuture = currentDay.isAfter(today);
    final dayColor = AppTheme.getDayAccentColor(currentDay.weekday);

    String dayHeading;
    try {
      dayHeading = DateFormat('EEEE d MMM', 'sv').format(currentDay);
    } catch (_) {
      dayHeading = DateFormat('EEEE d MMM').format(currentDay);
    }
    if (dayHeading.isNotEmpty) {
      dayHeading = '${dayHeading[0].toUpperCase()}${dayHeading.substring(1)}';
    }

    return wrapBottomSheet(
      context,
      DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          FamilyMemberAvatar(
                            member: widget.member,
                            size: 52,
                            borderWidth: 3,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.member.name,
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: mc,
                                  ),
                                ),
                                if (isToday) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Idag: ${_energyLabel(_energyDisplay)}',
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
                      const SizedBox(height: 12),
                      // Dagsnavigator (‹ Dagsrubrik › + Idag-chip)
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded,
                                size: 28),
                            color: Colors.grey.shade700,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dayHeading,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: dayColor,
                              ),
                            ),
                          ),
                          if (!isToday) ...[
                            GestureDetector(
                              onTap: () {
                                final todayIdx = _indexForDay(now);
                                if (todayIdx >= 0 &&
                                    todayIdx < _totalPageCount) {
                                  _pageController.animateToPage(
                                    todayIdx,
                                    duration:
                                        const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: dayColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: dayColor, width: 1.5),
                                ),
                                child: Text(
                                  'Idag',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: dayColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded,
                                size: 28),
                            color: Colors.grey.shade700,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ],
                      ),
                      if (!isToday) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isFuture
                                ? 'Förhandsvisning — bockning görs på dagen'
                                : 'Så blev dagen',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _totalPageCount,
                    onPageChanged: (idx) {
                      setState(() => _currentPage = idx);
                    },
                    itemBuilder: (context, index) {
                      final day = _dayForIndex(index);
                      return _MemberDayPage(
                        day: day,
                        member: widget.member,
                        currentUser: widget.currentUser,
                        energyDisplay: _energyDisplay,
                        onEnergySelect: (e) {
                          setState(() => _energyDisplay = e);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MemberDayPage extends StatelessWidget {
  final DateTime day;
  final UserModel member;
  final UserModel? currentUser;
  final int energyDisplay;
  final void Function(int) onEnergySelect;

  const _MemberDayPage({
    required this.day,
    required this.member,
    required this.currentUser,
    required this.energyDisplay,
    required this.onEnergySelect,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final familyId =
        currentUser?.familyId ?? provider.currentUser?.familyId ?? '';
    final dayColor = AppTheme.getDayAccentColor(day.weekday);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentDay = DateTime(day.year, day.month, day.day);
    final isToday = currentDay == today;
    final isFuture = currentDay.isAfter(today);
    final isPast = currentDay.isBefore(today);
    final isSelf = member.uid == currentUser?.uid;
    final firstName = member.name.split(' ').first;

    // Sysslor filtrerade för denna dag och medlem
    final memberChores = provider.chores.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return choreOccursOnDay(d, currentDay) &&
          choreAssignedToOnDay(d, currentDay,
              uid: member.uid, name: member.name);
    }).toList();

    final stadMemberChores = memberChores.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final k = d['stadKey'] as String?;
      return k != null && k.isNotEmpty;
    }).toList();
    final otherMemberChores = memberChores.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final k = d['stadKey'] as String?;
      return k == null || k.isEmpty;
    }).toList();

    return StreamBuilder<QuerySnapshot>(
      stream: dayEventsStream(familyId: familyId, day: currentDay),
      builder: (context, snapshot) {
        final dateEvents = snapshot.data?.docs ?? const [];
        final recurringEvents = provider.recurringEvents;

        // Dedup och sammanslagning via delad funktion
        final merged = mergeAndDedupDayEvents(
          dateEvents: dateEvents,
          recurringEvents: recurringEvents,
          day: currentDay,
        );

        // Filtrera till medlemmen
        final memberEvents = merged.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return eventIncludesPerson(d, uid: member.uid, name: member.name);
        }).toList()
          ..sort((a, b) {
            final da = a.data() as Map<String, dynamic>;
            final db = b.data() as Map<String, dynamic>;
            final ta = (da['time'] as String? ?? '').trim();
            final tb = (db['time'] as String? ?? '').trim();
            return ta.compareTo(tb);
          });

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            if (isSelf && isToday) ...[
              Text(
                'Din energi idag',
                style: AppTheme.sectionLabelStyle,
              ),
              const SizedBox(height: 8),
              _EnergyRow(
                userUid: member.uid,
                currentEnergy: energyDisplay,
                onSelect: (e) async {
                  onEnergySelect(e);
                  if (e == 1) {
                    final pause = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Tung dag? 💛'),
                        content: const Text(
                          'Vill du pausa dagens påminnelser? '
                          'Inga aktivitets-, övergångs- eller '
                          'sysslonotiser förrän något nytt planeras.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Nej, behåll dem'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Pausa påminnelser'),
                          ),
                        ],
                      ),
                    );
                    if (pause == true) {
                      await NotificationService.cancelByPayloads(
                          {'activity', 'transition', 'chore'});
                    }
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
            Text('AKTIVITETER', style: AppTheme.sectionLabelStyle),
            const SizedBox(height: 10),
            if (memberEvents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  isToday
                      ? 'Inga aktiviteter med $firstName idag.'
                      : (isFuture
                          ? 'Inget planerat 🎈'
                          : 'Inget låg på schemat den här dagen'),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              )
            else
              ...memberEvents.map((doc) => _EventTile(
                    doc: doc,
                    dayColor: dayColor,
                    listDay: currentDay,
                    currentUser: currentUser,
                    familyMembers: provider.familyMembers,
                    familyId: familyId,
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) =>
                            ActivityDetailSheet(docSnapshot: doc),
                      );
                    },
                  )),
            const SizedBox(height: 22),
            Text('SYSSLOR', style: AppTheme.sectionLabelStyle),
            const SizedBox(height: 10),
            if (memberChores.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  isToday
                      ? 'Inga sysslor tilldelade $firstName idag.'
                      : (isFuture
                          ? 'Inga sysslor planerade 🎈'
                          : 'Inga sysslor låg på denna dag'),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              )
            else ...[
              if (stadMemberChores.isNotEmpty)
                _buildStaddagTile(
                  context,
                  stadDocs: stadMemberChores,
                  day: currentDay,
                  dayColor: dayColor,
                ),
              ...otherMemberChores.map((doc) => _ChoreTile(
                    doc: doc,
                    day: currentDay,
                    isToday: isToday,
                    isPast: isPast,
                    isFuture: isFuture,
                    dayColor: dayColor,
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStaddagTile(
    BuildContext context, {
    required List<QueryDocumentSnapshot> stadDocs,
    required DateTime day,
    required Color dayColor,
  }) {
    final doneCount = stadDocs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return choreDoneOnDay(d, day);
    }).length;
    final totalCount = stadDocs.length;
    final isAllDone = totalCount > 0 && doneCount == totalCount;

    String recText = 'varje lördag';
    if (stadDocs.isNotEmpty) {
      final firstD = stadDocs.first.data() as Map<String, dynamic>;
      if (choreIsRecurring(firstD)) {
        recText = recurrenceLabel(firstD);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaddagPage()),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: AppTheme.cardDecoration(radius: 14),
            child: Row(
              children: [
                const Text('🧹', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Städdag · $doneCount av $totalCount klara',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.getTextColor(),
                          decoration:
                              isAllDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🔁 $recText',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAllDone)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF6BAE75),
                    size: 22,
                  )
                else
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
}

class _EnergyRow extends StatelessWidget {
  final String userUid;
  final int currentEnergy;
  final void Function(int) onSelect;

  const _EnergyRow({
    required this.userUid,
    required this.currentEnergy,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final levels = <(int, String, String)>[
      (1, '😔', 'Låg'),
      (2, '😌', 'OK'),
      (3, '😊', 'Bra'),
      (4, '🚀', 'Topp'),
    ];
    final dayColor = AppTheme.getDayAccentColor();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: levels.map((l) {
        final selected = currentEnergy == l.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: GestureDetector(
              onTap: () {
                UserService.updateEnergy(userUid, l.$1);
                onSelect(l.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? dayColor.withValues(alpha: 0.15)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: selected
                      ? Border.all(color: dayColor, width: 2)
                      : null,
                ),
                child: Column(
                  children: [
                    Text(l.$2, style: const TextStyle(fontSize: 22)),
                    Text(
                      l.$3,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EventTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Color dayColor;
  final DateTime listDay;
  final UserModel? currentUser;
  final List<UserModel> familyMembers;
  final String familyId;
  final VoidCallback onTap;

  const _EventTile({
    required this.doc,
    required this.dayColor,
    required this.listDay,
    this.currentUser,
    required this.familyMembers,
    required this.familyId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? '';
    final start = (d['time'] as String?)?.trim() ?? '';
    final end = (d['endTime'] as String?)?.trim() ?? '';
    String timeStr;
    if (start.isNotEmpty && end.isNotEmpty) {
      timeStr = '$start–$end';
    } else if (start.isNotEmpty) {
      timeStr = start;
    } else {
      final dt = parseDateTime(d);
      timeStr = dt != null ? DateFormat('HH:mm').format(dt) : '';
    }
    final canEdit = canEditDoc(currentUser, d);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: AppTheme.cardDecoration(radius: 14).copyWith(
              border: Border(left: BorderSide(color: dayColor, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  PlannerEventLeading(
                    data: d,
                    accentColor: dayColor,
                    emojiSize: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style: TextStyle(
                              color: dayColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (canEdit)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          color: Colors.grey.shade400, size: 20),
                      onSelected: (v) {
                        Navigator.pop(context);
                        handleEventMenuAction(
                          context,
                          action: v,
                          doc: doc,
                          listDay: listDay,
                          familyMembers: familyMembers,
                          familyId: familyId,
                        );
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Redigera'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Ta bort',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoreTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final DateTime day;
  final bool isToday;
  final bool isPast;
  final bool isFuture;
  final Color dayColor;

  const _ChoreTile({
    required this.doc,
    required this.day,
    required this.isToday,
    required this.isPast,
    required this.isFuture,
    required this.dayColor,
  });

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';
    final done = isToday
        ? choreDoneOnDay(d, day)
        : (isPast ? choreDoneOnDay(d, day) : false);

    Widget trailing;
    if (isToday) {
      trailing = InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          try {
            await ChoreService.completeChore(
              choreId: doc.id,
              done: !done,
              dayKey: dateKey(day),
            );
          } catch (_) {}
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: done ? dayColor : Colors.grey.shade400,
            size: 24,
          ),
        ),
      );
    } else if (isPast) {
      trailing = Icon(
        done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        color: done ? dayColor : Colors.grey.shade300,
        size: 22,
      );
    } else {
      trailing = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.cardDecoration(radius: 14),
        child: Row(
          children: [
            Text(pik, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? Colors.grey : AppTheme.getTextColor(),
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
