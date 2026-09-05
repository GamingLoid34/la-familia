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

/// Komplett storskärmskonfiguration från Firestore eller kodad fallback (FAS 3 & 4).
class DisplayConfig {
  final int version;
  final Map<String, DisplayScene> scenes;
  final List<DisplayScheduleEntry> schedule;

  const DisplayConfig({
    required this.version,
    required this.scenes,
    required this.schedule,
  });

  /// Kodad standardkonfiguration v3 (FAS 4.1).
  // TODO Storskärmsstudio: uppgraderingar ska MERGA användaranpassningar, inte skriva över
  static DisplayConfig defaultConfig() {
    return DisplayConfig(
      version: 3,
      scenes: const {
        'morgon': DisplayScene(
          id: 'morgon',
          name: 'Morgon',
          layout: 'board',
          modules: {
            'main': 'idag_nu',
            'footer1': 'middag_idag',
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

  /// Rådata-representation av standardkonfiguration v3 för Firestore-seed / uppgradering.
  static Map<String, dynamic> defaultRawMap() => {
        'version': 3,
        'scenes': {
          'morgon': {
            'name': 'Morgon',
            'layout': 'board',
            'modules': {
              'main': 'idag_nu',
              'footer1': 'middag_idag',
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

      return DisplayConfig(
        version: version,
        scenes: parsedScenes,
        schedule: parsedSchedule,
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
        'scenes': scenes.map((k, v) => MapEntry(k, v.toMap())),
        'schedule': schedule.map((e) => e.toMap()).toList(),
      };
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
