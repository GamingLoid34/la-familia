import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'display_log.dart';
import 'modules/footer_modules.dart';
import 'modules/idag_nu_module.dart';
import 'modules/klocka_module.dart';
import 'modules/middag_vecka_module.dart';
import 'modules/natt_module.dart';
import 'modules/nedrakning_module.dart';
import 'modules/veckotavla_module.dart';

/// Kontekst som skickas till varje modul på storskärmen (FAS 3 Beslut 1).
class DisplayModuleContext {
  final DateTime now;
  final DateTime weekStart;
  final int weekOffset;
  final List<UserModel> members;
  final int weatherRefreshEpoch;

  const DisplayModuleContext({
    required this.now,
    required this.weekStart,
    this.weekOffset = 0,
    required this.members,
    this.weatherRefreshEpoch = 0,
  });
}

/// Signatur för modul-byggare.
typedef DisplayModuleBuilder = Widget Function(
  BuildContext context,
  DisplayModuleContext moduleContext,
);

/// Centralt modulregister för storskärmen (FAS 3 & 4).
class DisplayModuleRegistry {
  DisplayModuleRegistry._() {
    registerDefaultModules();
  }
  static final DisplayModuleRegistry instance = DisplayModuleRegistry._();

  final Map<String, DisplayModuleBuilder> _modules = {};

  /// Registrerar appens standardmoduler (FAS 3 & 4).
  void registerDefaultModules() {
    register('veckotavla', (ctx, modCtx) => VeckotavlaModule(moduleContext: modCtx));
    register('middag_idag', (ctx, modCtx) => MiddagIdagModule(moduleContext: modCtx));
    register('sysslor_idag', (ctx, modCtx) => SysslorIdagModule(moduleContext: modCtx));
    register('tavlan', (ctx, modCtx) => TavlanModule(moduleContext: modCtx));
    register('klocka', (ctx, modCtx) => KlockaModule(moduleContext: modCtx));
    register('natt', (ctx, modCtx) => NattModule(moduleContext: modCtx));
    register('idag_nu', (ctx, modCtx) => IdagNuModule(moduleContext: modCtx));
    register('middag_vecka', (ctx, modCtx) => MiddagVeckaModule(moduleContext: modCtx));
    register('nedrakning', (ctx, modCtx) => NedrakningModule(moduleContext: modCtx));
  }

  /// Registrerar en modul med ett unikt id.
  void register(String id, DisplayModuleBuilder builder) {
    _modules[id] = builder;
  }

  /// Bygger modulen för givet id, eller returnerar en feltolerant platshållare vid okänt id.
  Widget buildModule(
    String id,
    BuildContext context,
    DisplayModuleContext moduleContext,
  ) {
    final builder = _modules[id];
    if (builder != null) {
      return builder(context, moduleContext);
    }

    DisplayLog.instance.log(
      'konfig',
      'Okänd modul i konfigurationen: "$id" — renderar platshållare',
    );
    return PlaceholderModule(moduleId: id);
  }

  /// Rensar registret (används primärt i tester).
  void clear() {
    _modules.clear();
  }
}

/// Feltolerant platshållare för okända moduler (FAS 3 Beslut 2).
class PlaceholderModule extends StatelessWidget {
  final String moduleId;

  const PlaceholderModule({super.key, required this.moduleId});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2330).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.extension_off_rounded,
            color: Colors.amber,
            size: 24,
          ),
          const SizedBox(height: 6),
          Text(
            'Okänd modul: "$moduleId"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
