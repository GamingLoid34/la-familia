import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../screens/agenda_page.dart';
import 'activity_detail_sheet.dart';
import 'member_avatar.dart';

DateTime? _parsePlannerDate(dynamic v) {
  try {
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final p = v.split('-');
      if (p.length >= 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    }
  } catch (_) {}
  return null;
}

DateTime? _parsePlannerDateTime(Map<String, dynamic> d) {
  try {
    final base = _parsePlannerDate(d['date']);
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
  } catch (_) {}
  return null;
}

/// Dagens aktiviteter och sysslor för en medlem, med länk till planering.
class MemberDaySheet extends StatefulWidget {
  final UserModel member;
  final UserModel? currentUser;
  final List<QueryDocumentSnapshot> memberEvents;
  final List<QueryDocumentSnapshot> memberChores;

  const MemberDaySheet({
    super.key,
    required this.member,
    required this.currentUser,
    required this.memberEvents,
    required this.memberChores,
  });

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
      return Color(widget.member.colorValue as int);
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

    return DraggableScrollableSheet(
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
                                'Idag: ${_energyLabel(_energyDisplay)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (isSelf) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Din energi idag',
                        style: AppTheme.sectionLabelStyle,
                      ),
                      const SizedBox(height: 8),
                      _EnergyRow(
                        userUid: widget.member.uid,
                        currentEnergy: _energyDisplay,
                        onSelect: (e) => setState(() => _energyDisplay = e),
                      ),
                    ],
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AgendaPage(
                              initialTab: AgendaTab.all,
                              initialPersonFilter: widget.member.name,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
                      label: const Text('Öppna i planering (filtrerat)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dayColor,
                        side: BorderSide(color: dayColor.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('AKTIVITETER IDAG', style: AppTheme.sectionLabelStyle),
                    const SizedBox(height: 10),
                    if (widget.memberEvents.isEmpty)
                      Text(
                        'Inga aktiviteter med ${widget.member.name.split(' ').first} idag.',
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
                        'Inga sysslor tilldelade ${widget.member.name.split(' ').first} just nu.',
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
    final pik = d['piktogram'] as String? ?? '📅';
    final dt = _parsePlannerDateTime(d);
    final timeStr = dt != null ? DateFormat('HH:mm').format(dt) : '';

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
                  Text(pik, style: const TextStyle(fontSize: 28)),
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
