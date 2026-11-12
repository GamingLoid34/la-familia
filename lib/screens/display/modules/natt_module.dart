import 'package:flutter/material.dart';
import '../display_module_registry.dart';
import 'klocka_module.dart';

/// Modul: Natt ("natt") (FAS 3).
/// Svart fond + klocka i dämpad stil med inbränningsskydd (exakt som DisplayNightView).
class NattModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;

  const NattModule({super.key, required this.moduleContext});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: KlockaModule(
        moduleContext: moduleContext,
        dimmed: true,
        burnInShift: true,
      ),
    );
  }
}
