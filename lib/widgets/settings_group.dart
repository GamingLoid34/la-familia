import 'package:flutter/material.dart';

/// En ingång per ämne. Att öppna en grupp ändrar inga inställningar.
class SettingsGroup extends StatelessWidget {
  final String title;
  final String summary;
  final List<Widget> children;
  const SettingsGroup({
    super.key,
    required this.title,
    required this.summary,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: ExpansionTile(
      key: PageStorageKey(title),
      title: Text(title),
      subtitle: Text(summary),
      childrenPadding: const EdgeInsets.only(bottom: 16),
      children: children,
    ),
  );
}
