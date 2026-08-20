import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/layout.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../utils/date_utils.dart';
import 'activity_detail_sheet.dart';
import 'member_avatar.dart';
import 'planner_event_leading.dart';

/// Dagens (eller vald dags) aktiviteter och sysslor för en medlem.
class MemberDaySheet extends StatefulWidget {
  final UserModel member;
  final UserModel? currentUser;
  final List<QueryDocumentSnapshot> memberEvents;
  final List<QueryDocumentSnapshot> memberChores;
  /// Den dag användaren öppnade (veckogrid-cell). Default = idag.
  final DateTime day;

  MemberDaySheet({
    super.key,
    required this.member,
    required this.currentUser,
    required this.memberEvents,
    required this.memberChores,
    DateTime? day,
  }) : day = day ?? DateTime.now();

  @override
  State<MemberDaySheet> createState() => _MemberDaySheetState();
}

class _MemberDaySheetState extends State<MemberDaySheet> {
  late int _energyDisplay;

  @override
  void initState() {
    super.initState();
    _energyDisplay = widget.member.energy;
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
    final isSelf = widget.member.uid == widget.currentUser?.uid;
    final dayColor = AppTheme.getDayAccentColor();
    final day = DateTime(widget.day.year, widget.day.month, widget.day.day);
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    String dayHeading;
    try {
      dayHeading = DateFormat('EEEE d MMM', 'sv').format(day);
    } catch (_) {
      dayHeading = DateFormat('EEEE d MMM').format(day);
    }
    if (dayHeading.isNotEmpty) {
      dayHeading =
          '${dayHeading[0].toUpperCase()}${dayHeading.substring(1)}';
    }
    final firstName = widget.member.name.split(' ').first;

    return wrapBottomSheet(
      context,
      DraggableScrollableSheet(
      initialChildSize: 0.72,
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
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    Row(
                      children: [
                        FamilyMemberAvatar(
                            member: widget.member, size: 56, borderWidth: 3),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.member.name,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: mc,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dayHeading,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
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
                    if (isSelf && isToday) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Din energi idag',
                        style: AppTheme.sectionLabelStyle,
                      ),
                      const SizedBox(height: 8),
                      _EnergyRow(
                        userUid: widget.member.uid,
                        currentEnergy: _energyDisplay,
                        onSelect: (e) async {
                          setState(() => _energyDisplay = e);
                          // Låg energi → erbjud att dämpa dagens påminnelser.
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
                    ],
                    const SizedBox(height: 20),
                    Text('AKTIVITETER', style: AppTheme.sectionLabelStyle),
                    const SizedBox(height: 10),
                    if (widget.memberEvents.isEmpty)
                      Text(
                        isToday
                            ? 'Inga aktiviteter med $firstName idag.'
                            : 'Inga aktiviteter med $firstName den här dagen.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      )
                    else
                      ...widget.memberEvents.map((doc) => _EventTile(
                            doc: doc,
                            dayColor: dayColor,
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
                    if (widget.memberChores.isEmpty)
                      Text(
                        'Inga sysslor tilldelade $firstName just nu.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      )
                    else
                      ...widget.memberChores.map((doc) => _ChoreTile(doc: doc)),
                  ],
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
  final VoidCallback onTap;

  const _EventTile({
    required this.doc,
    required this.dayColor,
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

  const _ChoreTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['chore'] as String? ?? d['title'] as String? ?? '';
    final pik = d['piktogram'] as String? ?? '✅';
    final done = d['isDone'] == true;

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
            if (done)
              Icon(Icons.check_circle_rounded,
                  color: AppTheme.getDayAccentColor(), size: 22),
          ],
        ),
      ),
    );
  }
}
