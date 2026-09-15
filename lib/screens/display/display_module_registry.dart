import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'display_log.dart';
import 'display_module_error_boundary.dart';
import 'display_palette.dart';
import 'display_scene_models.dart';
import 'modules/avgangar_module.dart';
import 'modules/footer_modules.dart';
import 'modules/foto_module.dart';
import 'modules/idag_nu_module.dart';
import 'modules/klocka_module.dart';
import 'modules/middag_vecka_module.dart';
import 'modules/natt_module.dart';
import 'modules/nedrakning_module.dart';
import 'modules/persondag_module.dart';
import 'modules/skolmat_module.dart';
import 'modules/veckotavla_module.dart';

/// Kontekst som skickas till varje modul på storskärmen (FAS 3 Beslut 1).
class DisplayModuleContext {
  final DateTime now;
  final DateTime weekStart;
  final int weekOffset;
  final List<UserModel> members;
  final int weatherRefreshEpoch;
  final String? familyId;
  final DisplayTransitConfig? transitConfig;
  final DisplaySkolmatConfig? skolmatConfig;
  final DisplayFotoConfig? fotoConfig;
  final DisplayPalette palette;
  final int? spotlightIndex;

  const DisplayModuleContext({
    required this.now,
    required this.weekStart,
    this.weekOffset = 0,
    required this.members,
    this.weatherRefreshEpoch = 0,
    this.familyId,
    this.transitConfig,
    this.skolmatConfig,
    this.fotoConfig,
    this.palette = DisplayPalette.light,
    this.spotlightIndex,
  });
}

/// Signatur för modul-byggare.
typedef DisplayModuleBuilder = Widget Function(
  BuildContext context,
  DisplayModuleContext moduleContext,
);

/// Metadata för en modul i storskärmens register (FAS 6a).
class DisplayModuleMeta {
  final String id;
  final String label;
  final IconData icon;
  final String description;
  final Set<String> zones; // 'main', 'side', 'footer'
  final bool manualOnly;

  const DisplayModuleMeta({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
    required this.zones,
    this.manualOnly = false,
  });
}

/// Centralt modulregister för storskärmen (FAS 3, 4 & 6a).
class DisplayModuleRegistry {
  DisplayModuleRegistry._() {
    registerDefaultModules();
  }
  static final DisplayModuleRegistry instance = DisplayModuleRegistry._();

  final Map<String, DisplayModuleBuilder> _modules = {};

  static final Map<String, DisplayModuleMeta> _metadata = {
    'veckotavla': const DisplayModuleMeta(
      id: 'veckotavla',
      label: 'Veckotavla',
      icon: Icons.calendar_view_week_rounded,
      description: 'Översikt över hela familjens vecka',
      zones: {'main'},
    ),
    'idag_nu': const DisplayModuleMeta(
      id: 'idag_nu',
      label: 'Idag & Nu',
      icon: Icons.today_rounded,
      description: 'Dagens aktiviteter och aktuell händelse',
      zones: {'main'},
    ),
    'natt': const DisplayModuleMeta(
      id: 'natt',
      label: 'Nattklocka',
      icon: Icons.bedtime_rounded,
      description: 'Mörk nattvy med dämpad klocka',
      zones: {'main'},
    ),
    'foto': const DisplayModuleMeta(
      id: 'foto',
      label: 'Fotoalbum',
      icon: Icons.photo_library_rounded,
      description: 'Familjens delade bildspel',
      zones: {'main', 'side'},
    ),
    'klocka': const DisplayModuleMeta(
      id: 'klocka',
      label: 'Klocka',
      icon: Icons.access_time_rounded,
      description: 'Digital klocka och datum',
      zones: {'main', 'side', 'footer'},
    ),
    'middag_vecka': const DisplayModuleMeta(
      id: 'middag_vecka',
      label: 'Veckans middagar',
      icon: Icons.restaurant_menu_rounded,
      description: 'Middagsplanering för hela veckan',
      zones: {'main', 'side'},
    ),
    'avgangar': const DisplayModuleMeta(
      id: 'avgangar',
      label: 'Avgångar',
      icon: Icons.directions_transit_rounded,
      description: 'Realtidsavgångar för kollektivtrafik',
      zones: {'main', 'side', 'footer'},
    ),
    'skolmat': const DisplayModuleMeta(
      id: 'skolmat',
      label: 'Skolmat',
      icon: Icons.lunch_dining_rounded,
      description: 'Skolans matsedel för veckan',
      zones: {'main', 'side', 'footer'},
    ),
    'sysslor_idag': const DisplayModuleMeta(
      id: 'sysslor_idag',
      label: 'Dagens sysslor',
      icon: Icons.checklist_rounded,
      description: 'Familjens sysslor och uppdrag för dagen',
      zones: {'side', 'footer'},
    ),
    'tavlan': const DisplayModuleMeta(
      id: 'tavlan',
      label: 'Tavlan',
      icon: Icons.sticky_note_2_rounded,
      description: 'Gemensamma anteckningar och meddelanden',
      zones: {'side', 'footer'},
    ),
    'nedrakning': const DisplayModuleMeta(
      id: 'nedrakning',
      label: 'Nedräkning',
      icon: Icons.timer_rounded,
      description: 'Nedräkning till nästa viktiga händelse',
      zones: {'side', 'footer'},
    ),
    'middag_idag': const DisplayModuleMeta(
      id: 'middag_idag',
      label: 'Dagens middag',
      icon: Icons.dinner_dining_rounded,
      description: 'Vad som serveras till middag idag',
      zones: {'footer'},
    ),
    'persondag': const DisplayModuleMeta(
      id: 'persondag',
      label: 'Persondag',
      icon: Icons.person_rounded,
      description: 'Enskild familjemedlems dagsvy',
      zones: {'main'},
      manualOnly: true,
    ),
  };

  /// Hämtar metadata för en specifik modul.
  DisplayModuleMeta? metaFor(String id) => _metadata[id];

  /// Hämtar alla tillgängliga moduler för en specifik zon ('main', 'side', 'footer').
  /// Om zonnamnet är t.ex. 'footer1', 'footer2', 'footer3' normaliseras det till 'footer'.
  List<DisplayModuleMeta> modulesForZone(String zone, {bool includeManualOnly = false}) {
    final normalizedZone = zone.startsWith('footer') ? 'footer' : zone;
    return _metadata.values.where((m) {
      if (!includeManualOnly && m.manualOnly) return false;
      return m.zones.contains(normalizedZone);
    }).toList();
  }

  /// Hämtar samtliga registrerade moduler.
  List<DisplayModuleMeta> allAvailableModules({bool includeManualOnly = false}) {
    return _metadata.values.where((m) {
      if (!includeManualOnly && m.manualOnly) return false;
      return true;
    }).toList();
  }

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
    register('foto', (ctx, modCtx) => FotoModule(moduleContext: modCtx));
    register('avgangar', (ctx, modCtx) => AvgangarModule(moduleContext: modCtx));
    register('persondag', (ctx, modCtx) => PersondagModule(moduleContext: modCtx));
    register('skolmat', (ctx, modCtx) => SkolmatModule(moduleContext: modCtx));
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
      return DisplayModuleErrorBoundary(
        moduleId: id,
        displayPalette: moduleContext.palette,
        fallbackBuilder: id == 'persondag'
            ? (ctx, err) => PersondagModule(
                  moduleContext: moduleContext,
                  forceClumped: true,
                )
            : null,
        child: builder(context, moduleContext),
      );
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
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
