import 'dart:developer' as developer;

/// En schemapost för dygnet (FAS 3 & 4).
class DisplayScheduleEntry {
  final String start; // 'HH:mm'
  final String scene; // scen-id, t.ex. 'standard', 'natt', 'morgon', 'kvall'
  final List<int>? days; // 1 = måndag .. 7 = söndag. null eller tom = alla dagar
  final int startMinutes; // Minuter sedan midnatt (0..1439)

  DisplayScheduleEntry({
    required this.start,
    required this.scene,
    this.days,
  }) : startMinutes = _parseMinutes(start);

  static int _parseMinutes(String time) {
    final parts = time.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0].trim()) ?? 0;
      final m = int.tryParse(parts[1].trim()) ?? 0;
      return (h.clamp(0, 23) * 60) + m.clamp(0, 59);
    }
    return 0;
  }

  factory DisplayScheduleEntry.fromMap(Map<String, dynamic> map) {
    final rawStart = (map['start'] as String? ?? '00:00').trim();
    final rawScene = (map['scene'] as String? ?? 'standard').trim();
    final rawDays = map['days'];
    List<int>? days;
    if (rawDays is List) {
      days = rawDays
          .map((e) => (e as num?)?.toInt())
          .whereType<int>()
          .where((d) => d >= 1 && d <= 7)
          .toList();
    }
    return DisplayScheduleEntry(
      start: rawStart.isNotEmpty ? rawStart : '00:00',
      scene: rawScene.isNotEmpty ? rawScene : 'standard',
      days: days,
    );
  }

  Map<String, dynamic> toMap() => {
        'start': start,
        'scene': scene,
        if (days != null && days!.isNotEmpty) 'days': days,
      };
}

/// En scenkonfiguration: layoutmall och moduler per zon (FAS 3 & 4).
class DisplayScene {
  final String id;
  final String name;
  final String layout; // 'board', 'fullscreen', 'sidebar'
  final Map<String, String> modules; // zonId -> modulId

  const DisplayScene({
    required this.id,
    required this.name,
    required this.layout,
    required this.modules,
  });

  factory DisplayScene.fromMap(String id, Map<String, dynamic> map) {
    final rawName = (map['name'] as String? ?? id).trim();
    final rawLayout = (map['layout'] as String? ?? 'board').trim();
    final rawModules = <String, String>{};

    final modsObj = map['modules'];
    if (modsObj is Map) {
      for (final entry in modsObj.entries) {
        final k = entry.key?.toString().trim() ?? '';
        final v = entry.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          rawModules[k] = v;
        }
      }
    }

    return DisplayScene(
      id: id,
      name: rawName.isNotEmpty ? rawName : id,
      layout: rawLayout.isNotEmpty ? rawLayout : 'board',
      modules: rawModules,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'layout': layout,
        'modules': modules,
      };
}

/// Filter för en hållplats (FAS 6b).
class DisplayTransitFilter {
  final List<String> modes;
  final List<String> destinations;

  const DisplayTransitFilter({
    this.modes = const [],
    this.destinations = const [],
  });

  factory DisplayTransitFilter.fromMap(Map<String, dynamic> map) {
    final rawModes = map['modes'];
    final modes = rawModes is List
        ? rawModes
            .map((m) => m?.toString().trim() ?? '')
            .where((m) => m.isNotEmpty)
            .toList()
        : const <String>[];

    final rawDest = map['destinations'];
    final destinations = rawDest is List
        ? rawDest
            .map((d) => d?.toString().trim() ?? '')
            .where((d) => d.isNotEmpty)
            .toList()
        : const <String>[];

    return DisplayTransitFilter(
      modes: modes,
      destinations: destinations,
    );
  }

  Map<String, dynamic> toMap() => {
        'modes': modes,
        'destinations': destinations,
      };
}

/// En hållplatskonfiguration för kollektivtrafik (FAS 5 & FAS 6b).
class DisplayTransitStop {
  final String id;
  final String name;
  final String icon;
  final int walkMinutes;
  final DisplayTransitFilter? filter;

  const DisplayTransitStop({
    required this.id,
    required this.name,
    required this.icon,
    this.walkMinutes = 5,
    this.filter,
  });

  factory DisplayTransitStop.fromMap(Map<String, dynamic> map) {
    final rawFilter = map['filter'];
    return DisplayTransitStop(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      icon: (map['icon'] as String? ?? '🚌').trim(),
      walkMinutes: (map['walkMinutes'] as num?)?.toInt() ?? 5,
      filter: rawFilter is Map
          ? DisplayTransitFilter.fromMap(Map<String, dynamic>.from(rawFilter))
          : null,
    );
  }

  String get stopId => id;

  DisplayTransitStop copyWith({
    String? id,
    String? name,
    String? icon,
    int? walkMinutes,
    DisplayTransitFilter? filter,
  }) {
    return DisplayTransitStop(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      walkMinutes: walkMinutes ?? this.walkMinutes,
      filter: filter ?? this.filter,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'walkMinutes': walkMinutes,
        if (filter != null) 'filter': filter!.toMap(),
      };
}

/// Kollektivtrafik-inställningar för storskärmen (FAS 5).
///
/// OBS / Strukturell avvikelse (FAS 5.3):
/// Filtren (destinations, modes) och standard-walkMinutes ligger för närvarande
/// på transit-roten snarare än per enskild hållplats. Detta fungerar väl med en
/// aktiv tåghållplats (Tranås station), men om en busshållplats återinförs skulle
/// den i dagsläget ärva tågfiltret om inte filtren flyttas ned på per-hållplatsnivå.
/// Detta kommer att arkitektoniskt separeras och lösas i Storskärmsstudion.
class DisplayTransitConfig {
  final List<DisplayTransitStop> stops;
  final List<String> destinations;
  final List<String> modes;
  final int walkMinutes;

  const DisplayTransitConfig({
    this.stops = const [],
    this.destinations = const ['Mjölby', 'Linköping', 'Norrköping'],
    this.modes = const ['train'],
    this.walkMinutes = 5,
  });

  factory DisplayTransitConfig.fromMap(Map<String, dynamic> map) {
    final rawStops = map['stops'];
    final stops = <DisplayTransitStop>[];
    if (rawStops is List) {
      for (final s in rawStops) {
        if (s is Map) {
          stops.add(DisplayTransitStop.fromMap(Map<String, dynamic>.from(s)));
        }
      }
    }

    final rawDest = map['destinations'];
    final destinations = rawDest is List
        ? rawDest
            .map((d) => d.toString().trim())
            .where((d) => d.isNotEmpty)
            .toList()
        : const ['Mjölby', 'Linköping', 'Norrköping'];

    final rawModes = map['modes'];
    final modes = rawModes is List
        ? rawModes
            .map((m) => m.toString().trim())
            .where((m) => m.isNotEmpty)
            .toList()
        : const ['train'];

    final walk = (map['walkMinutes'] as num?)?.toInt() ?? 5;

    return DisplayTransitConfig(
      stops: stops,
      destinations: destinations,
      modes: modes,
      walkMinutes: walk,
    );
  }

  Map<String, dynamic> toMap() => {
        'stops': stops.map((s) => s.toMap()).toList(),
        'destinations': destinations,
        'modes': modes,
        'walkMinutes': walkMinutes,
      };
}

/// En skola och dess kopplade familjemedlemmar för skolmatsedel (FAS 5.1 & 5.1b).
class DisplaySkolmatSchoolConfig {
  final String id;
  final String name;
  final String municipality;
  final String source; // 'mateo' | 'manual' (saknat = mateo)
  final List<String> memberUids;

  const DisplaySkolmatSchoolConfig({
    required this.id,
    required this.name,
    this.municipality = 'tranas',
    this.source = 'mateo',
    this.memberUids = const [],
  });

  bool get isManual => source == 'manual';

  factory DisplaySkolmatSchoolConfig.fromMap(Map<String, dynamic> map) {
    final rawUids = map['memberUids'];
    final uids = <String>[];
    if (rawUids is List) {
      for (final u in rawUids) {
        if (u != null && u.toString().trim().isNotEmpty) {
          uids.add(u.toString().trim());
        }
      }
    }
    final rawSource =
        (map['source'] as String? ?? 'mateo').trim().toLowerCase();
    return DisplaySkolmatSchoolConfig(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      municipality: (map['municipality'] as String? ??
              (rawSource == 'manual' ? '' : 'tranas'))
          .trim()
          .toLowerCase(),
      source: rawSource.isEmpty ? 'mateo' : rawSource,
      memberUids: uids,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (municipality.isNotEmpty) 'municipality': municipality,
        'source': source,
        'memberUids': memberUids,
      };
}

/// Skolmat-inställningar för storskärmen (FAS 5.1).
class DisplaySkolmatConfig {
  final List<DisplaySkolmatSchoolConfig> schools;

  const DisplaySkolmatConfig({
    this.schools = const [],
  });

  factory DisplaySkolmatConfig.fromMap(Map<String, dynamic> map) {
    final rawSchools = map['schools'];
    final schools = <DisplaySkolmatSchoolConfig>[];
    if (rawSchools is List) {
      for (final s in rawSchools) {
        if (s is Map) {
          schools.add(DisplaySkolmatSchoolConfig.fromMap(
              Map<String, dynamic>.from(s)));
        }
      }
    }
    return DisplaySkolmatConfig(schools: schools);
  }

  DisplaySkolmatSchoolConfig? schoolForMember(String memberUid) {
    for (final school in schools) {
      if (school.memberUids.contains(memberUid)) {
        return school;
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'schools': schools.map((s) => s.toMap()).toList(),
      };
}

/// Bildspelskonfiguration för storskärmen (FAS 6b).
class DisplayFotoConfig {
  final int intervalSec;

  const DisplayFotoConfig({
    this.intervalSec = 45,
  });

  factory DisplayFotoConfig.fromMap(Map<String, dynamic> map) {
    final sec = (map['intervalSec'] as num?)?.toInt() ?? 45;
    return DisplayFotoConfig(intervalSec: sec.clamp(20, 120));
  }

  Map<String, dynamic> toMap() => {
        'intervalSec': intervalSec,
      };
}

/// Temakonfiguration för storskärmen (FAS 6c).
class DisplayThemeConfig {
  final String mode; // 'light' | 'dark' | 'auto'
  final String darkFrom; // '18:00'
  final String darkTo; // '07:00'

  const DisplayThemeConfig({
    this.mode = 'light',
    this.darkFrom = '18:00',
    this.darkTo = '07:00',
  });

  factory DisplayThemeConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DisplayThemeConfig();
    final m = (map['mode'] as String? ?? 'light').trim().toLowerCase();
    final mode = (m == 'dark' || m == 'auto') ? m : 'light';
    final from = (map['darkFrom'] as String? ?? '18:00').trim();
    final to = (map['darkTo'] as String? ?? '07:00').trim();
    return DisplayThemeConfig(
      mode: mode,
      darkFrom: _validHm(from) ? from : '18:00',
      darkTo: _validHm(to) ? to : '07:00',
    );
  }

  static bool _validHm(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60;
  }

  static int _toMinutes(String hm) {
    final parts = hm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  /// Avgör om det effektiva läget är mörkt för en given tidpunkt [now] (FAS 6c Beslut 3).
  ///
  /// Testtidskompatibel och ren funktion:
  /// - 'light' -> false
  /// - 'dark' -> true
  /// - 'auto' -> mörkt i intervallet [darkFrom, darkTo) med midnattsvändning
  bool resolveIsDark(DateTime now) {
    if (mode == 'light') return false;
    if (mode == 'dark') return true;

    final nowMin = now.hour * 60 + now.minute;
    final fromMin = _toMinutes(darkFrom);
    final toMin = _toMinutes(darkTo);

    if (fromMin <= toMin) {
      return nowMin >= fromMin && nowMin < toMin;
    } else {
      return nowMin >= fromMin || nowMin < toMin;
    }
  }

  /// Returnerar det effektiva temaläget som sträng: 'light' eller 'dark'.
  String resolveEffectiveMode(DateTime now) =>
      resolveIsDark(now) ? 'dark' : 'light';

  Map<String, dynamic> toMap() => {
        'mode': mode,
        'darkFrom': darkFrom,
        'darkTo': darkTo,
      };
}

/// Komplett storskärmskonfiguration från Firestore eller kodad fallback (FAS 3, 4, 5, 5.1, 6a, 6b & 6c).
class DisplayConfig {
  final int version;
  final Map<String, DisplayScene> scenes;
  final List<DisplayScheduleEntry> schedule;
  final DisplayTransitConfig transit;
  final DisplaySkolmatConfig skolmat;
  final DisplayFotoConfig foto;
  final DisplayThemeConfig theme;
  final Map<String, String> keymap;
  final List<String> seededSceneIds;

  const DisplayConfig({
    required this.version,
    required this.scenes,
    required this.schedule,
    this.transit = const DisplayTransitConfig(),
    this.skolmat = const DisplaySkolmatConfig(),
    this.foto = const DisplayFotoConfig(),
    this.theme = const DisplayThemeConfig(),
    this.keymap = const {
      '1': 'standard',
      '2': 'natt',
      '3': 'morgon',
      '4': 'kvall',
      '5': 'foto',
    },
    this.seededSceneIds = const [
      'standard',
      'natt',
      'morgon',
      'kvall',
      'foto',
      'person',
    ],
  });

  /// Kodad standardkonfiguration v10 (FAS 6c).
  static DisplayConfig defaultConfig() {
    return DisplayConfig(
      version: 10,
      foto: const DisplayFotoConfig(intervalSec: 45),
      theme: const DisplayThemeConfig(),
      keymap: const {
        '1': 'standard',
        '2': 'natt',
        '3': 'morgon',
        '4': 'kvall',
        '5': 'foto',
      },
      seededSceneIds: const [
        'standard',
        'natt',
        'morgon',
        'kvall',
        'foto',
        'person',
      ],
      transit: const DisplayTransitConfig(
        stops: [
          DisplayTransitStop(
            id: '740000041',
            name: 'Tranås station',
            icon: '🚆',
            walkMinutes: 5,
            filter: DisplayTransitFilter(
              modes: ['train'],
              destinations: ['Mjölby', 'Linköping', 'Norrköping'],
            ),
          ),
        ],
        destinations: ['Mjölby', 'Linköping', 'Norrköping'],
        modes: ['train'],
        walkMinutes: 5,
      ),
      skolmat: const DisplaySkolmatConfig(
        schools: [],
      ),
      scenes: const {
        'morgon': DisplayScene(
          id: 'morgon',
          name: 'Morgon',
          layout: 'board',
          modules: {
            'main': 'idag_nu',
            'footer1': 'avgangar',
            'footer2': 'sysslor_idag',
            'footer3': 'tavlan',
          },
        ),
        'standard': DisplayScene(
          id: 'standard',
          name: 'Veckotavlan',
          layout: 'board',
          modules: {
            'main': 'veckotavla',
            'footer1': 'middag_idag',
            'footer2': 'sysslor_idag',
            'footer3': 'tavlan',
          },
        ),
        'kvall': DisplayScene(
          id: 'kvall',
          name: 'Kväll',
          layout: 'sidebar',
          modules: {
            'main': 'veckotavla',
            'side': 'middag_vecka',
            'footer1': 'sysslor_idag',
            'footer2': 'tavlan',
            'footer3': 'nedrakning',
          },
        ),
        'natt': DisplayScene(
          id: 'natt',
          name: 'Natt',
          layout: 'fullscreen',
          modules: {
            'main': 'natt',
          },
        ),
        'foto': DisplayScene(
          id: 'foto',
          name: 'Foton',
          layout: 'fullscreen',
          modules: {
            'main': 'foto',
          },
        ),
        'person': DisplayScene(
          id: 'person',
          name: 'Person',
          layout: 'fullscreen',
          modules: {
            'main': 'persondag',
          },
        ),
      },
      schedule: [
        DisplayScheduleEntry(
          start: '05:30',
          scene: 'morgon',
          days: [1, 2, 3, 4, 5],
        ),
        DisplayScheduleEntry(
          start: '07:30',
          scene: 'standard',
          days: [6, 7],
        ),
        DisplayScheduleEntry(start: '08:30', scene: 'standard'),
        DisplayScheduleEntry(start: '17:00', scene: 'kvall'),
        DisplayScheduleEntry(start: '22:00', scene: 'natt'),
      ],
    );
  }

  /// Rådata-representation av standardkonfiguration v10 för Firestore-seed / uppgradering.
  static Map<String, dynamic> defaultRawMap() => {
        'version': 10,
        'theme': {
          'mode': 'light',
          'darkFrom': '18:00',
          'darkTo': '07:00',
        },
        'foto': {
          'intervalSec': 45,
        },
        'keymap': {
          '1': 'standard',
          '2': 'natt',
          '3': 'morgon',
          '4': 'kvall',
          '5': 'foto',
        },
        'seededSceneIds': [
          'standard',
          'natt',
          'morgon',
          'kvall',
          'foto',
          'person',
        ],
        'transit': {
          'stops': [
            {
              'id': '740000041',
              'name': 'Tranås station',
              'icon': '🚆',
              'walkMinutes': 5,
              'filter': {
                'modes': ['train'],
                'destinations': ['Mjölby', 'Linköping', 'Norrköping'],
              },
            },
          ],
          'destinations': ['Mjölby', 'Linköping', 'Norrköping'],
          'modes': ['train'],
          'walkMinutes': 5,
        },
        'skolmat': {
          'schools': [],
        },
        'scenes': {
          'morgon': {
            'name': 'Morgon',
            'layout': 'board',
            'modules': {
              'main': 'idag_nu',
              'footer1': 'avgangar',
              'footer2': 'sysslor_idag',
              'footer3': 'tavlan',
            },
          },
          'standard': {
            'name': 'Veckotavlan',
            'layout': 'board',
            'modules': {
              'main': 'veckotavla',
              'footer1': 'middag_idag',
              'footer2': 'sysslor_idag',
              'footer3': 'tavlan',
            },
          },
          'kvall': {
            'name': 'Kväll',
            'layout': 'sidebar',
            'modules': {
              'main': 'veckotavla',
              'side': 'middag_vecka',
              'footer1': 'sysslor_idag',
              'footer2': 'tavlan',
              'footer3': 'nedrakning',
            },
          },
          'natt': {
            'name': 'Natt',
            'layout': 'fullscreen',
            'modules': {
              'main': 'natt',
            },
          },
          'foto': {
            'name': 'Foton',
            'layout': 'fullscreen',
            'modules': {
              'main': 'foto',
            },
          },
          'person': {
            'name': 'Person',
            'layout': 'fullscreen',
            'modules': {
              'main': 'persondag',
            },
          },
        },
        'schedule': [
          {'start': '05:30', 'scene': 'morgon', 'days': [1, 2, 3, 4, 5]},
          {'start': '07:30', 'scene': 'standard', 'days': [6, 7]},
          {'start': '08:30', 'scene': 'standard'},
          {'start': '17:00', 'scene': 'kvall'},
          {'start': '22:00', 'scene': 'natt'},
        ],
      };

  /// Parsar konfigurationskarta från Firestore.
  /// Vid allvarliga fel (saknade fält, ogiltig struktur) returneras kodad fallback.
  static DisplayConfig parseWithFallback(
    dynamic data, {
    void Function(String reason)? onFallbackTriggered,
  }) {
    if (data == null || data is! Map) {
      onFallbackTriggered?.call('Data är null eller inte en karta');
      return defaultConfig();
    }

    try {
      final map = Map<String, dynamic>.from(data);
      final version = (map['version'] as num?)?.toInt() ?? 1;

      // 1. Scener
      final rawScenes = map['scenes'];
      if (rawScenes == null || rawScenes is! Map || rawScenes.isEmpty) {
        onFallbackTriggered?.call('Inga scener definierade');
        return defaultConfig();
      }

      final parsedScenes = <String, DisplayScene>{};
      for (final entry in rawScenes.entries) {
        final id = entry.key?.toString().trim() ?? '';
        final sceneData = entry.value;
        if (id.isNotEmpty && sceneData is Map) {
          parsedScenes[id] = DisplayScene.fromMap(
            id,
            Map<String, dynamic>.from(sceneData),
          );
        }
      }

      if (parsedScenes.isEmpty || !parsedScenes.containsKey('standard')) {
        onFallbackTriggered?.call('Scenen "standard" saknas');
        return defaultConfig();
      }

      // 2. Schema
      final rawSchedule = map['schedule'];
      if (rawSchedule == null || rawSchedule is! List || rawSchedule.isEmpty) {
        onFallbackTriggered?.call('Schemat saknas eller är tomt');
        return defaultConfig();
      }

      final parsedSchedule = <DisplayScheduleEntry>[];
      for (final item in rawSchedule) {
        if (item is Map) {
          final entry = DisplayScheduleEntry.fromMap(
            Map<String, dynamic>.from(item),
          );
          parsedSchedule.add(entry);
        }
      }

      if (parsedSchedule.isEmpty) {
        onFallbackTriggered?.call('Inga giltiga schemaposter fanns');
        return defaultConfig();
      }

      // 3. Transit (FAS 5)
      final rawTransit = map['transit'];
      final parsedTransit = rawTransit is Map
          ? DisplayTransitConfig.fromMap(Map<String, dynamic>.from(rawTransit))
          : defaultConfig().transit;

      // 4. Skolmat (FAS 5.1)
      final rawSkolmat = map['skolmat'];
      final parsedSkolmat = rawSkolmat is Map
          ? DisplaySkolmatConfig.fromMap(Map<String, dynamic>.from(rawSkolmat))
          : defaultConfig().skolmat;

      // 5. Foto (FAS 6b)
      final rawFoto = map['foto'];
      final parsedFoto = rawFoto is Map
          ? DisplayFotoConfig.fromMap(Map<String, dynamic>.from(rawFoto))
          : const DisplayFotoConfig();

      // 6. Keymap (FAS 6a)
      final rawKeymap = map['keymap'];
      final Map<String, String> parsedKeymap;
      if (rawKeymap is Map) {
        parsedKeymap = {};
        for (final entry in rawKeymap.entries) {
          final k = entry.key?.toString().trim() ?? '';
          final v = entry.value?.toString().trim() ?? '';
          if (k.isNotEmpty && v.isNotEmpty) {
            parsedKeymap[k] = v;
          }
        }
      } else {
        parsedKeymap = Map.from(defaultConfig().keymap);
      }

      // 7. SeededSceneIds (FAS 6a)
      final rawSeeded = map['seededSceneIds'];
      final List<String> parsedSeeded;
      if (rawSeeded is List) {
        parsedSeeded = rawSeeded
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } else {
        parsedSeeded = List.from(defaultConfig().seededSceneIds);
      }

      // 8. Theme (FAS 6c)
      final rawTheme = map['theme'];
      final parsedTheme = rawTheme is Map
          ? DisplayThemeConfig.fromMap(Map<String, dynamic>.from(rawTheme))
          : const DisplayThemeConfig();

      return DisplayConfig(
        version: version,
        scenes: parsedScenes,
        schedule: parsedSchedule,
        transit: parsedTransit,
        skolmat: parsedSkolmat,
        foto: parsedFoto,
        theme: parsedTheme,
        keymap: parsedKeymap,
        seededSceneIds: parsedSeeded,
      );
    } catch (e, stack) {
      developer.log('DisplayConfig: parsning misslyckades, använder fallback',
          error: e, stackTrace: stack);
      onFallbackTriggered?.call('Parsningsfel: $e');
      return defaultConfig();
    }
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'theme': theme.toMap(),
        'keymap': keymap,
        'seededSceneIds': seededSceneIds,
        'transit': transit.toMap(),
        'skolmat': skolmat.toMap(),
        'foto': foto.toMap(),
        'scenes': scenes.map((k, v) => MapEntry(k, v.toMap())),
        'schedule': schedule.map((e) => e.toMap()).toList(),
      };
}

/// Validerar en kandidatkonfiguration lokalt mot DisplayConfig-reglerna.
/// Returnerar null om konfigurationen är giltig, annars ett felmeddelande.
String? validateDisplayConfig(Map<String, dynamic> candidateRawMap) {
  String? fallbackReason;
  final parsed = DisplayConfig.parseWithFallback(
    candidateRawMap,
    onFallbackTriggered: (reason) {
      fallbackReason = reason;
    },
  );
  if (fallbackReason != null) {
    return fallbackReason;
  }
  if (parsed.scenes.isEmpty) {
    return 'Inga scener definierade.';
  }
  if (!parsed.scenes.containsKey('standard')) {
    return 'Scenen "standard" måste finnas.';
  }
  if (parsed.schedule.isEmpty) {
    return 'Schemat måste innehålla minst en post.';
  }
  return null;
}

/// Cyklisk schemaupplösning över dygnet med veckodagsstöd (FAS 3 & 4).
///
/// Beräknar aktiv scen för tidpunkten [now]:
/// - Sorterar dagens kandidater (där `entry.days` är null/tom eller matchar `now.weekday`) stigande efter starttid.
/// - Aktiv post är posten med störst starttid <= now.
/// - Om ingen sådan finns (klockslaget är före dagens första schemapost):
///   wrap över midnatt gäller, dvs. sista posten från föregående dags kandidater är aktiv.
/// - Om varken idag eller igår gav matchning eller schemat är tomt returneras 'standard'.
String resolveScheduledScene(
  DateTime now,
  List<DisplayScheduleEntry> schedule,
) {
  if (schedule.isEmpty) return 'standard';

  final today = now.weekday; // 1 = måndag .. 7 = söndag
  final nowMinutes = now.hour * 60 + now.minute;

  // 1. Filtrera kandidater för idag
  final todayCandidates = schedule.where((e) {
    return e.days == null || e.days!.isEmpty || e.days!.contains(today);
  }).toList()
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  // 2. Leta efter dagens post med störst startMinutes <= nowMinutes
  final eligibleToday =
      todayCandidates.where((e) => e.startMinutes <= nowMinutes).toList();
  if (eligibleToday.isNotEmpty) {
    return eligibleToday.last.scene;
  }

  // 3. Om klockslaget är före dagens första schemapost:
  // Föregående dags sista schemapost gäller (wrap över midnatt).
  final prevDay = today == 1 ? 7 : today - 1;
  final prevDayCandidates = schedule.where((e) {
    return e.days == null || e.days!.isEmpty || e.days!.contains(prevDay);
  }).toList()
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  if (prevDayCandidates.isNotEmpty) {
    return prevDayCandidates.last.scene;
  }

  // 4. Fallback
  return 'standard';
}
