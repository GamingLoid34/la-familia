import 'package:flutter/material.dart';
import 'display_module_registry.dart';
import 'modules/natt_module.dart';

/// Bakåtkompatibel wrapper för nattvyn på storskärm (använder nu NattModule).

class DisplayNightView extends StatelessWidget {
  final DateTime now;

  const DisplayNightView({super.key, required this.now});

  @override
  Widget build(BuildContext context) {
    return NattModule(
      moduleContext: DisplayModuleContext(
        now: now,
        weekStart: now,
        members: const [],
      ),
    );
  }
}
