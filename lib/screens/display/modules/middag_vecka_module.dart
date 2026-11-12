import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../app_theme.dart';
import '../../../providers/family_provider.dart';
import '../../../utils/date_utils.dart';
import '../../../utils/schedule_time_utils.dart';
import '../display_module_registry.dart';
import '../display_palette.dart';

/// Modul: Veckans middagar ("middag_vecka") (FAS 4, 6c).
/// Visar måndag–söndag i sidokortet med färgprick per dag och accent för idag.
class MiddagVeckaModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const MiddagVeckaModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    final displayPalette = DisplayPalette.of(context);
    final provider = context.watch<FamilyProvider>();
    final fid = provider.currentUser?.familyId ?? '';
    final todayPalette = AppTheme.dayPalette(moduleContext.now.weekday);

    final weekDays = List.generate(
      7,
      (i) => moduleContext.weekStart.add(Duration(days: i)),
    );
    final weekKeys = weekDays.map((d) => dateKey(d)).toList();

    if (fid.isEmpty) {
      return _buildCard(
        displayPalette: displayPalette,
        child: Center(
          child: Text(
            'Ingen familj vald',
            style: TextStyle(
              fontFamily: 'Nunito',
              color: displayPalette.textMuted,
            ),
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
          displayPalette: displayPalette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.restaurant_rounded,
                    size: 22,
                    color: todayPalette.base,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Veckans middagar',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: displayPalette.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: displayPalette.divider),
              const SizedBox(height: 8),
              // 7 dagsrader
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: weekDays.map((day) {
                    final k = dateKey(day);
                    final isToday = sameCalendarDay(day, moduleContext.now);
                    final meal = mealByDate[k];
                    final dayPal = AppTheme.dayPalette(day.weekday);

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
                            ? todayPalette.base.withValues(
                                alpha: displayPalette.isDark ? 0.20 : 0.12,
                              )
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(
                                color: todayPalette.base.withValues(
                                  alpha: displayPalette.isDark ? 0.50 : 0.40,
                                ),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          // Färgprick i dagens färg
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: dayPal.base,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: Text(
                              dayStr,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 18,
                                fontWeight:
                                    isToday ? FontWeight.w800 : FontWeight.w600,
                                color: isToday
                                    ? (displayPalette.isDark
                                        ? todayPalette.light
                                        : displayPalette
                                            .dayHeaderTextColor(day.weekday))
                                    : displayPalette.textMuted,
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
                                fontSize: 18,
                                fontWeight:
                                    isToday ? FontWeight.w800 : FontWeight.w600,
                                color: isToday
                                    ? displayPalette.textPrimary
                                    : (displayPalette.isDark
                                        ? displayPalette.textPrimary
                                        : const Color(0xFF2C3E50)),
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
    required DisplayPalette displayPalette,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: displayPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: displayPalette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: displayPalette.isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
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
