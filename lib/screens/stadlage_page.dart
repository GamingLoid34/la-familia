import 'package:flutter/material.dart';
import 'legacy_archive_page.dart';

/// Compatibility route. The implementation now lives in the Hem app.
class StadlagePage extends StatelessWidget {
  final String choreId;
  final Color? accent;
  final DateTime? targetDay;
  const StadlagePage({super.key, required this.choreId, this.accent, this.targetDay});

  @override
  Widget build(BuildContext context) => const LegacyArchivePage();
}
