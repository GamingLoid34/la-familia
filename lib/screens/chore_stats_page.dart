import 'package:flutter/material.dart';
import 'legacy_archive_page.dart';

/// Compatibility route. The implementation now lives in the Hem app.
class ChoreStatsPage extends StatelessWidget {
  const ChoreStatsPage({super.key});

  @override
  Widget build(BuildContext context) => const LegacyArchivePage();
}
