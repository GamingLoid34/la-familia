import 'package:flutter/material.dart';
import 'legacy_archive_page.dart';

/// Compatibility route. The implementation now lives in the Hem app.
class MealPlannerPage extends StatelessWidget {
  const MealPlannerPage({super.key});

  @override
  Widget build(BuildContext context) => const LegacyArchivePage();
}
