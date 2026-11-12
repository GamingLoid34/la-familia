import 'package:flutter/material.dart';
import 'legacy_archive_page.dart';

/// Compatibility route. The implementation now lives in the Hem app.
class StaddagPage extends StatelessWidget {
  final String? familyId;
  const StaddagPage({super.key, this.familyId});

  @override
  Widget build(BuildContext context) => const LegacyArchivePage();
}
