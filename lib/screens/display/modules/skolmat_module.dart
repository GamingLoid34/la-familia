import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../../../utils/schedule_time_utils.dart';
import '../display_module_registry.dart';
import '../display_palette.dart';
import '../display_scene_models.dart';
import '../display_school_menu_data.dart';
import 'footer_modules.dart';

/// Fristående modul: Skolmat ("skolmat") (FAS 5.1).
///
/// Visar dagens lunch per skola i footerkortet (<= 130px)
/// eller fullständig veckomatsedel per skola i större zon.
class SkolmatModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const SkolmatModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DisplaySchoolMenuData.instance,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight <= 130) {
              return _buildFooter(context, DisplaySchoolMenuData.instance);
            }
            return _buildLarge(context, DisplaySchoolMenuData.instance);
          },
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, DisplaySchoolMenuData menuData) {
    final palette = AppTheme.dayPalette(moduleContext.now.weekday);
    final schools = moduleContext.skolmatConfig?.schools ??
        DisplayConfig.defaultConfig().skolmat.schools;

    if (schools.isEmpty) {
      return DisplayFooterCard(
        iconData: Icons.restaurant_rounded,
        iconColor: palette.base,
        title: 'Skolmat',
        content: 'Ingen skola konfigurerad',
      );
    }

    if (menuData.isLoading && menuData.menus.isEmpty) {
      return DisplayFooterCard(
        iconData: Icons.restaurant_rounded,
        iconColor: palette.base,
        title: 'Skolmat',
        content: 'Hämtar matsedel...',
      );
    }

    if (menuData.error != null && menuData.menus.isEmpty) {
      return DisplayFooterCard(
        iconData: Icons.restaurant_rounded,
        iconColor: palette.base,
        title: 'Skolmat',
        content: 'Matsedel ej tillgänglig',
      );
    }

    // Sammanställ lunch för skolorna idag (FAS 5.7: rena rätter utan "Lunch 1:"-rubriker)
    final parts = <String>[];
    for (final s in schools) {
      final menu = menuData.menuForSchool(s.id);
      final day = menu?.dayFor(moduleContext.now);
      final rawLunch = day?.lunch;
      if (rawLunch != null && rawLunch.isNotEmpty) {
        final cleanLunch = cleanDishTitle(rawLunch);
        final hasVeg = hasDistinctVegetarian(cleanLunch, day?.vegetarian);
        final cleanVeg = hasVeg ? cleanDishTitle(day!.vegetarian!) : null;
        final dishStr = (cleanVeg != null && cleanVeg.isNotEmpty)
            ? '$cleanLunch · 🌱 $cleanVeg'
            : cleanLunch;
        if (schools.length > 1) {
          parts.add('${s.name}: $dishStr');
        } else {
          parts.add(dishStr);
        }
      } else {
        if (schools.length > 1) {
          parts.add('${s.name}: Matsedel ej tillgänglig');
        } else {
          parts.add('Matsedel ej tillgänglig');
        }
      }
    }

    final summary =
        parts.isNotEmpty ? parts.join(' · ') : 'Ingen skollunch idag';

    return DisplayFooterCard(
      iconData: Icons.restaurant_rounded,
      iconColor: palette.base,
      title: 'Skolmat',
      content: summary,
    );
  }

  Widget _buildLarge(BuildContext context, DisplaySchoolMenuData menuData) {
    final displayPalette = DisplayPalette.of(context);
    final palette = AppTheme.dayPalette(moduleContext.now.weekday);
    final schools = moduleContext.skolmatConfig?.schools ??
        DisplayConfig.defaultConfig().skolmat.schools;

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.restaurant_rounded, size: 24, color: palette.base),
              const SizedBox(width: 10),
              Text(
                'Skolmatsedel',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: displayPalette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: displayPalette.divider),
          const SizedBox(height: 12),
          if (schools.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Inga skolor konfigurerade',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    color: displayPalette.textMuted,
                  ),
                ),
              ),
            )
          else if (menuData.isLoading && menuData.menus.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Hämtar skolmatsedel...',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    color: displayPalette.textMuted,
                  ),
                ),
              ),
            )
          else if (menuData.error != null && menuData.menus.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Matsedel ej tillgänglig',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    color: displayPalette.textMuted,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: schools.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, idx) {
                  final school = schools[idx];
                  final menu = menuData.menuForSchool(school.id);
                  return _buildSchoolWeek(school, menu, palette, displayPalette);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSchoolWeek(
    DisplaySkolmatSchoolConfig school,
    SchoolMenu? menu,
    DayPalette palette,
    DisplayPalette displayPalette,
  ) {
    // Måndag–fredag i aktuell vecka
    final schoolDays = List.generate(
      5,
      (i) => moduleContext.weekStart.add(Duration(days: i)),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: displayPalette.isDark
            ? displayPalette.background
            : const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: displayPalette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            school.name,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: displayPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...schoolDays.map((day) {
            final isToday = sameCalendarDay(day, moduleContext.now);
            final dayMenu = menu?.dayFor(day);
            final dayCap = _formatDayHeading(day);

            final cleanLunch = dayMenu != null && dayMenu.lunch != null
                ? cleanDishTitle(dayMenu.lunch!)
                : (dayMenu?.lunch ?? '—');
            final hasVeg = hasDistinctVegetarian(cleanLunch, dayMenu?.vegetarian);
            final cleanVeg = hasVeg ? cleanDishTitle(dayMenu!.vegetarian!) : null;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isToday
                    ? (displayPalette.isDark
                        ? displayPalette.card
                        : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isToday
                    ? Border.all(
                        color: palette.base.withValues(alpha: 0.5),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      dayCap,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                        color: isToday
                            ? (displayPalette.isDark
                                ? palette.light
                                : displayPalette.dayHeaderTextColor(day.weekday))
                            : displayPalette.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cleanLunch,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight:
                                isToday ? FontWeight.w700 : FontWeight.w500,
                            color: displayPalette.textPrimary,
                          ),
                        ),
                        if (cleanVeg != null && cleanVeg.isNotEmpty)
                          Text(
                            '🌱 $cleanVeg',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: displayPalette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatDayHeading(DateTime day) {
    const swedishWeekdays = [
      'Måndag',
      'Tisdag',
      'Onsdag',
      'Torsdag',
      'Fredag',
      'Lördag',
      'Söndag',
    ];
    const swedishMonths = [
      'jan',
      'feb',
      'mar',
      'apr',
      'maj',
      'jun',
      'jul',
      'aug',
      'sep',
      'okt',
      'nov',
      'dec',
    ];
    final wd = swedishWeekdays[(day.weekday - 1).clamp(0, 6)];
    final mo = swedishMonths[(day.month - 1).clamp(0, 11)];
    return '$wd ${day.day} $mo';
  }
}
