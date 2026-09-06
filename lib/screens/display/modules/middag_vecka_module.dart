import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../app_theme.dart';
import '../../../providers/family_provider.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/schedule_time_utils.dart';
import '../display_module_registry.dart';

/// Modul: Veckans middagar ("middag_vecka") (FAS 4).
/// Visar måndag–söndag i sidokortet med fetstil/färgaccent för idag.
class MiddagVeckaModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const MiddagVeckaModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final fid = provider.currentUser?.familyId ?? '';
    final palette = AppTheme.dayPalette(moduleContext.now.weekday);

    final weekDays = List.generate(
      7,
      (i) => moduleContext.weekStart.add(Duration(days: i)),
    );
    final weekKeys = weekDays.map((d) => dateKey(d)).toList();

    if (fid.isEmpty) {
      return _buildCard(
        palette: palette,
        child: const Center(
          child: Text(
            'Ingen familj vald',
            style: TextStyle(fontFamily: 'Nunito', color: Color(0xFF888888)),
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('meals')
          .where('familyId', isEqualTo: fid)
          .where('date', whereIn: weekKeys)
          .snapshots(),
      builder: (context, snapshot) {
        final mealByDate = <String, Map<String, dynamic>>{};
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['date'] as String? ?? '').trim();
            if (date.isNotEmpty) {
              mealByDate[date] = data;
            }
          }
        }

        return _buildCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.restaurant_rounded,
                    size: 22,
                    color: palette.base,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Veckans middagar',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFE2E5EE)),
              const SizedBox(height: 8),
              // 7 dagsrader
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: weekDays.map((day) {
                    final k = dateKey(day);
                    final isToday = sameCalendarDay(day, moduleContext.now);
                    final meal = mealByDate[k];

                    final dayName = DateFormat('EEEE', 'sv').format(day);
                    final dayCapitalized =
                        dayName[0].toUpperCase() + dayName.substring(1);
                    final dayStr = '$dayCapitalized ${day.day}';

                    String mealText = '—';
                    if (meal != null) {
                      final rawTitle = (meal['title'] as String? ?? '').trim();
                      final rawEmoji = (meal['emoji'] as String? ?? '').trim();
                      if (rawTitle.isNotEmpty) {
                        mealText = rawEmoji.isNotEmpty
                            ? '$rawEmoji $rawTitle'
                            : rawTitle;
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isToday
                            ? palette.base.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(
                                color: palette.base.withValues(alpha: 0.4),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              dayStr,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 15,
                                fontWeight:
                                    isToday ? FontWeight.w800 : FontWeight.w600,
                                color: isToday
                                    ? palette.deep
                                    : const Color(0xFF5C6877),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              mealText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 15,
                                fontWeight:
                                    isToday ? FontWeight.w800 : FontWeight.w600,
                                color: isToday
                                    ? const Color(0xFF1A1A2E)
                                    : const Color(0xFF2C3E50),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard({
    required DayPalette palette,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E5EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
