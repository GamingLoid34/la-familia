import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/family_provider.dart';
import '../display_module_registry.dart';
import '../display_week_data.dart';

/// Modul: Veckotavlan ("veckotavla") (FAS 3).
/// Förser storskärmen med hela veckans händelser, dagshuvuden med väder samt grid.
class VeckotavlaModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const VeckotavlaModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final fid = provider.currentUser?.familyId ?? '';

    return DisplayWeekData(
      familyId: fid,
      weekStart: moduleContext.weekStart,
      now: moduleContext.now,
      members: moduleContext.members,
      weekOffset: moduleContext.weekOffset,
      weatherRefreshEpoch: moduleContext.weatherRefreshEpoch,
    );
  }
}
