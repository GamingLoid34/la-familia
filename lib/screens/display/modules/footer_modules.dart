import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_theme.dart';
import '../../../providers/family_provider.dart';
import '../../../utils/chore_utils.dart';
import '../display_module_registry.dart';
import '../display_theme.dart';

/// Gemensamt fotkort för storskärmen (FAS 3).
/// Exakt samma mått, styling, typografi och skuggor som dagens veckotavla.
class DisplayFooterCard extends StatelessWidget {
  final IconData iconData;
  final Color iconColor;
  final String title;
  final String content;

  const DisplayFooterCard({
    super.key,
    required this.iconData,
    required this.iconColor,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(iconData, size: 22, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5C6877),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DisplayTheme.footerStyle.copyWith(
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modul: Middag ikväll ("middag_idag")
class MiddagIdagModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const MiddagIdagModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final palette = AppTheme.dayPalette(moduleContext.now.weekday);

    String mealText = 'Ingen middag planerad';
    String mealEmoji = '';
    if (provider.todayMeals.isNotEmpty) {
      final d = provider.todayMeals.first.data() as Map<String, dynamic>;
      final title = (d['title'] as String? ?? '').trim();
      if (title.isNotEmpty) {
        mealText = title;
        final rawEmoji = (d['emoji'] as String? ?? '').trim();
        if (rawEmoji.isNotEmpty) mealEmoji = '$rawEmoji ';
      }
    }

    return DisplayFooterCard(
      iconData: Icons.restaurant_rounded,
      iconColor: palette.base,
      title: 'Middag ikväll',
      content: '$mealEmoji$mealText',
    );
  }
}

/// Modul: Sysslor idag ("sysslor_idag")
class SysslorIdagModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const SysslorIdagModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final palette = AppTheme.dayPalette(moduleContext.now.weekday);

    final todayChores = provider.chores.where((c) {
      final d = c.data() as Map<String, dynamic>;
      return choreOccursOnDay(d, moduleContext.now);
    }).toList();

    final doneChores = todayChores.where((c) {
      final d = c.data() as Map<String, dynamic>;
      return choreDoneOnDay(d, moduleContext.now);
    }).length;

    final choreText = todayChores.isEmpty
        ? 'Inga sysslor idag'
        : '$doneChores av ${todayChores.length} klara';

    return DisplayFooterCard(
      iconData: Icons.check_circle_rounded,
      iconColor: palette.base,
      title: 'Sysslor idag',
      content: choreText,
    );
  }
}

/// Modul: Familjetavlan ("tavlan")
class TavlanModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const TavlanModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final palette = AppTheme.dayPalette(moduleContext.now.weekday);

    String noteText = 'Inga lappar';
    if (provider.todayNotes.isNotEmpty) {
      final note = provider.todayNotes.first;
      final fromName = note.fromName.split(' ').first;
      noteText = fromName.isNotEmpty ? '$fromName: ${note.text}' : note.text;
    }

    return DisplayFooterCard(
      iconData: Icons.push_pin_rounded,
      iconColor: palette.base,
      title: 'Familjetavlan',
      content: noteText,
    );
  }
}
