import 'package:flutter/material.dart';
import 'display_log.dart';
import 'display_module_registry.dart';
import 'display_theme.dart';

/// Layoutmall "board" (FAS 3 Beslut 1).
/// Fyller huvudytan med zon "main" och har tre footerkort ("footer1", "footer2", "footer3")
/// i en footerremsa med samma mått och stil som dagens veckotavla.
class BoardLayout extends StatelessWidget {
  final DisplayModuleContext moduleContext;
  final Map<String, String> zoneModules;

  const BoardLayout({
    super.key,
    required this.moduleContext,
    required this.zoneModules,
  });

  @override
  Widget build(BuildContext context) {
    final mainMod = zoneModules['main'] ?? '';
    final f1Mod = zoneModules['footer1'] ?? '';
    final f2Mod = zoneModules['footer2'] ?? '';
    final f3Mod = zoneModules['footer3'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            children: [
              Expanded(
                child: DisplayModuleRegistry.instance.buildModule(
                  mainMod,
                  context,
                  moduleContext,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: DisplayTheme.footerHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: DisplayModuleRegistry.instance.buildModule(
                        f1Mod,
                        context,
                        moduleContext,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DisplayModuleRegistry.instance.buildModule(
                        f2Mod,
                        context,
                        moduleContext,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DisplayModuleRegistry.instance.buildModule(
                        f3Mod,
                        context,
                        moduleContext,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Layoutmall "fullscreen" (FAS 3 Beslut 1).
/// Fyller hela skärmen med zon "main" (används av nattvyn m.fl.).
class FullscreenLayout extends StatelessWidget {
  final DisplayModuleContext moduleContext;
  final Map<String, String> zoneModules;

  const FullscreenLayout({
    super.key,
    required this.moduleContext,
    required this.zoneModules,
  });

  @override
  Widget build(BuildContext context) {
    final mainMod = zoneModules['main'] ?? '';
    return DisplayModuleRegistry.instance.buildModule(
      mainMod,
      context,
      moduleContext,
    );
  }
}

/// Layoutmall "sidebar" (FAS 4).
/// Huvudyta uppdelad i zon "main" (~64%) och zon "side" (~36%),
/// med samma tre footerkort nedtill som "board".
class SidebarLayout extends StatelessWidget {
  final DisplayModuleContext moduleContext;
  final Map<String, String> zoneModules;

  const SidebarLayout({
    super.key,
    required this.moduleContext,
    required this.zoneModules,
  });

  @override
  Widget build(BuildContext context) {
    final mainMod = zoneModules['main'] ?? '';
    final sideMod = zoneModules['side'] ?? '';
    final f1Mod = zoneModules['footer1'] ?? '';
    final f2Mod = zoneModules['footer2'] ?? '';
    final f3Mod = zoneModules['footer3'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 64,
                      child: DisplayModuleRegistry.instance.buildModule(
                        mainMod,
                        context,
                        moduleContext,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 36,
                      child: DisplayModuleRegistry.instance.buildModule(
                        sideMod,
                        context,
                        moduleContext,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: DisplayTheme.footerHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: DisplayModuleRegistry.instance.buildModule(
                        f1Mod,
                        context,
                        moduleContext,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DisplayModuleRegistry.instance.buildModule(
                        f2Mod,
                        context,
                        moduleContext,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DisplayModuleRegistry.instance.buildModule(
                        f3Mod,
                        context,
                        moduleContext,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bygger den begärda layoutmallen.
/// Om layoutmallen är okänd används 'board' som kodad fallback och händelsen loggas.
Widget buildDisplayLayout({
  required String layoutId,
  required BuildContext context,
  required DisplayModuleContext moduleContext,
  required Map<String, String> zoneModules,
}) {
  switch (layoutId) {
    case 'board':
      return BoardLayout(
        moduleContext: moduleContext,
        zoneModules: zoneModules,
      );
    case 'sidebar':
      return SidebarLayout(
        moduleContext: moduleContext,
        zoneModules: zoneModules,
      );
    case 'fullscreen':
      return FullscreenLayout(
        moduleContext: moduleContext,
        zoneModules: zoneModules,
      );
    default:
      DisplayLog.instance.log(
        'konfig-fallback',
        'Okänd layoutmall "$layoutId", använder fallback "board"',
      );
      return BoardLayout(
        moduleContext: moduleContext,
        zoneModules: zoneModules,
      );
  }
}
