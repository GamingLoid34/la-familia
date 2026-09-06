import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../providers/family_provider.dart';
import '../utils/layout.dart';
import 'calendar_import_page.dart';
import 'chore_stats_page.dart';
import 'lathund_page.dart';
import 'manage_routines_page.dart';
import 'meal_planner_page.dart';
import 'schedule_scan_page.dart';
import 'shopping_list_page.dart';
import 'staddag_page.dart';
import 'timer_page.dart';
import 'vardagsplan_page.dart';
import 'visit_admin_page.dart';
import 'work_schedule_page.dart';

/// Verktygssida: samlad hub för vardags-, planerings- och importverktyg.
/// Rollbaserad åtkomst (föräldrasektioner döljs för barn).
class VerktygPage extends StatelessWidget {
  const VerktygPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    final isParent = user?.isParent == true;
    final weekday = DateTime.now().weekday;
    final dayColor = AppTheme.getDayAccentColor(weekday);
    final isLowStimuli = AppTheme.lowStimuli;
    final maxW = WindowSize.of(context).isExpanded
        ? WindowSize.settingsMaxWidth
        : 520.0;
    final crossAxisCount = WindowSize.of(context).isExpanded ? 3 : 2;

    return Scaffold(
      backgroundColor: isLowStimuli
          ? const Color(0xFFF0F2F5)
          : const Color(0xFFF5F7FA),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Column(
            children: [
              _buildHeader(context, dayColor, weekday),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: [
                    // Sektion 1: VARDAG (alla)
                    _buildSectionHeader('VARDAG', dayColor),
                    const SizedBox(height: 10),
                    _buildGrid(
                      context,
                      crossAxisCount: crossAxisCount,
                      items: [
                        _VerktygItem(
                          emoji: '⏱️',
                          label: 'Timer',
                          page: const TimerPage(),
                        ),
                        _VerktygItem(
                          emoji: '🛒',
                          label: 'Inköpslista',
                          page: const ShoppingListPage(),
                        ),
                        _VerktygItem(
                          emoji: '🍽️',
                          label: 'Mat & matsedel',
                          page: const MealPlannerPage(),
                        ),
                        _VerktygItem(
                          emoji: '📖',
                          label: 'Lathund',
                          page: const LathundPage(),
                        ),
                        _VerktygItem(
                          emoji: '🧹',
                          label: 'Städdag',
                          subtitle: 'zoner, trasor & steg',
                          page: const StaddagPage(),
                        ),
                      ],
                    ),

                    // Sektion 2: PLANERING (föräldrar)
                    if (isParent) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('PLANERING', dayColor),
                      const SizedBox(height: 10),
                      _buildGrid(
                        context,
                        crossAxisCount: crossAxisCount,
                        items: [
                          _VerktygItem(
                            emoji: '💼',
                            label: 'Arbetsschema',
                            page: const WorkSchedulePage(),
                          ),
                          _VerktygItem(
                            emoji: '🗓️',
                            label: 'Vardagsplan',
                            page: const VardagsplanPage(),
                          ),
                          _VerktygItem(
                            emoji: '🌅',
                            label: 'Morgon & kväll',
                            page: const ManageRoutinesPage(),
                          ),
                          _VerktygItem(
                            emoji: '🏥',
                            label: 'Besök',
                            page: const VisitAdminPage(),
                          ),
                        ],
                      ),
                    ],

                    // Sektion 3: IMPORT & DATA (föräldrar)
                    if (isParent) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('IMPORT & DATA', dayColor),
                      const SizedBox(height: 10),
                      _buildGrid(
                        context,
                        crossAxisCount: crossAxisCount,
                        items: [
                          _VerktygItem(
                            emoji: '📸',
                            label: 'Skanna schema',
                            page: const ScheduleScanPage(),
                          ),
                          _VerktygItem(
                            emoji: '🔗',
                            label: 'Kalenderimport',
                            page: const CalendarImportPage(),
                          ),
                          _VerktygItem(
                            emoji: '📊',
                            label: 'Sysslostatistik',
                            page: const ChoreStatsPage(),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color dayColor, int weekday) {
    final palette = AppTheme.dayPalette(weekday);
    final textColor = AppTheme.getNpfTextColor(weekday);
    final isLowStimuli = AppTheme.lowStimuli;

    return Container(
      decoration: isLowStimuli
          ? BoxDecoration(color: palette.base)
          : AppTheme.headerDecoration(weekday),
      padding: AppTheme.paddingBelowStatusBar(
        context,
        horizontal: 16,
        bottom: 16,
        extraBelowStatus: 4,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 26),
            tooltip: 'Tillbaka',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(
            'Verktyg 🧰',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color dayColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context, {
    required int crossAxisCount,
    required List<_VerktygItem> items,
  }) {
    final palette = AppTheme.dayPalette();
    final isLowStimuli = AppTheme.lowStimuli;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 104,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => item.page),
              );
            },
            child: Container(
              decoration: AppTheme.cardDecoration(radius: 18).copyWith(
                boxShadow: isLowStimuli
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.base.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      item.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.getTextColor(),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VerktygItem {
  final String emoji;
  final String label;
  final String? subtitle;
  final Widget page;

  const _VerktygItem({
    required this.emoji,
    required this.label,
    this.subtitle,
    required this.page,
  });
}
