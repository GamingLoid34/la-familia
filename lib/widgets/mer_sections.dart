import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../navigation/app_navigation.dart';
import 'vardag_header.dart';

class _MerItem {
  final String emoji;
  final String title;
  final String? subtitle;
  final MerRoute route;
  const _MerItem(this.emoji, this.title, this.route, [this.subtitle]);
}

/// Mer-flikens verktygssektioner (Androids `MerScreen`). Visas överst i Mer,
/// före INSTÄLLNINGAR. Uppgifter, Inkorg, PLANERING och IMPORT & DATA är bara
/// för förälder/admin. Städdag och Sysslostatistik hör till Sysslor, rutinerna
/// till inställningarna nedan, och Besök är dolt som i Android.
class MerSections extends StatelessWidget {
  final bool isParent;
  const MerSections({super.key, required this.isParent});

  static List<(String?, List<_MerItem>)> _sections(bool isParent) => [
        (null, [
          const _MerItem('🔁', 'Återkommande', MerRoute.aterkommande,
              'allt som upprepas'),
          if (isParent)
            const _MerItem('📌', 'Uppgifter', MerRoute.tasks,
                'sådant som ska bli gjort'),
          if (isParent)
            const _MerItem(
                '📥', 'Inkorg', MerRoute.inbox, 'klistra in ett veckobrev'),
        ]),
        ('VARDAG', const [
          _MerItem('⏱️', 'Timer', MerRoute.timer),
          _MerItem('🛒', 'Inköpslista', MerRoute.shopping),
          _MerItem('🍽️', 'Mat & matsedel', MerRoute.meals),
          _MerItem('📖', 'Lathund', MerRoute.lathund),
        ]),
        if (isParent)
          ('PLANERING', const [
            _MerItem('💼', 'Arbetsschema', MerRoute.workSchedule),
            _MerItem('🗓️', 'Vardagsplan', MerRoute.vardagsplan),
          ]),
        if (isParent)
          ('IMPORT & DATA', const [
            _MerItem('📸', 'Skanna schema', MerRoute.scheduleScan),
            _MerItem('🔗', 'Importer', MerRoute.calendarImport,
                'lägg till & ta bort'),
          ]),
      ];

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    final sections = _sections(isParent);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, items) in sections) ...[
            if (label != null)
              VardagSectionLabel(label,
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8)),
            VardagCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 56, color: c.divider),
                  _MerRow(item: items[i]),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _MerRow extends StatelessWidget {
  final _MerItem item;
  const _MerRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AppNavigation.pageFor(item.route))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 28,
            child: Text(item.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: c.onCardPrimary)),
                if (item.subtitle != null)
                  Text(item.subtitle!,
                      style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.onCardIcon),
        ]),
      ),
    );
  }
}
