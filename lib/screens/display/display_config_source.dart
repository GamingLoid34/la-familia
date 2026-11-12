import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'display_log.dart';
import 'display_scene_models.dart';

/// Sammanfogar befintlig Firestore-konfiguration med standardvärden (v8).
///
/// Ren funktion som garanterar:
/// 1. Version sätts till defaultRawMap['version'] (8).
/// 2. Saknade toppnivånycklar i rawDoc (t.ex. keymap, seededSceneIds, transit, skolmat, schedule) fylls på från defaultRawMap.
/// 3. För scenes: Lägger endast till standardscener vars id saknas i rawDoc['scenes']
///    OCH som inte finns i rawDoc['seededSceneIds'] (förhindrar att användarborttagna scener återuppstår).
/// 4. Befintliga scener i rawDoc rörs inte.
/// 5. Befintliga poster i schedule, transit, skolmat rörs aldrig om de finns i rawDoc.
/// 6. Returnerar den sammanfogade kartan redo att sparas via merge.
Map<String, dynamic> mergeDefaults(
  Map<String, dynamic> rawDoc,
  Map<String, dynamic> defaultRawMap,
) {
  final merged = Map<String, dynamic>.from(rawDoc);

  // 1. Version
  merged['version'] = defaultRawMap['version'] ?? 10;

  // 2. seededSceneIds
  final rawSeeded = rawDoc['seededSceneIds'];
  final List<String> seededList = rawSeeded is List
      ? List<String>.from(rawSeeded
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty))
      : [];

  // 3. Scener
  final defaultScenes = defaultRawMap['scenes'] is Map
      ? Map<String, dynamic>.from(defaultRawMap['scenes'] as Map)
      : <String, dynamic>{};
  final rawScenes = rawDoc['scenes'] is Map
      ? Map<String, dynamic>.from(rawDoc['scenes'] as Map)
      : <String, dynamic>{};
  final mergedScenes = Map<String, dynamic>.from(rawScenes);

  for (final entry in defaultScenes.entries) {
    final sceneId = entry.key;
    if (!rawScenes.containsKey(sceneId) && !seededList.contains(sceneId)) {
      mergedScenes[sceneId] = entry.value;
      if (!seededList.contains(sceneId)) {
        seededList.add(sceneId);
      }
    }
  }

  // Om rawDoc saknade seededSceneIds helt, se till att alla standardscener finns i seededList
  if (rawSeeded == null) {
    final defaultSeeded = defaultRawMap['seededSceneIds'];
    if (defaultSeeded is List) {
      for (final id in defaultSeeded) {
        final strId = id?.toString().trim() ?? '';
        if (strId.isNotEmpty && !seededList.contains(strId)) {
          seededList.add(strId);
        }
      }
    }
  }

  merged['scenes'] = mergedScenes;
  merged['seededSceneIds'] = seededList;

  // 4. Övriga toppnivånycklar
  for (final entry in defaultRawMap.entries) {
    final key = entry.key;
    if (key == 'version' || key == 'scenes' || key == 'seededSceneIds') {
      continue;
    }
    if (!merged.containsKey(key) || merged[key] == null) {
      merged[key] = entry.value;
    }
  }

  return merged;
}

/// Idempotent transform från v8 till v9 för Firestore-konfigurationen (FAS 6b).
///
/// Ren funktion som:
/// 1. Sätter version till 9.
/// 2. För varje stop i transit.stops:
///    - Om stop.walkMinutes saknas kopieras transit.walkMinutes (fallback 5).
///    - Om stop.filter saknas kopieras transit.modes (fallback ['train']) och transit.destinations (fallback ['Mjölby', 'Linköping', 'Norrköping']).
///    - Rotnycklarna lämnas kvar i dokumentet för bakåtkompatibilitet.
/// 3. Om foto saknas sätts foto: { intervalSec: 45 }.
/// 4. Är strikt idempotent: körs den flera gånger ger den identiskt resultat
///    och rör aldrig redan anpassade per-stop-värden.
Map<String, dynamic> transformV8ToV9(Map<String, dynamic> rawDoc) {
  final result = Map<String, dynamic>.from(rawDoc);

  // 1. Version
  result['version'] = 9;

  // 2. Foto-sektion (FAS 6b)
  if (!result.containsKey('foto') || result['foto'] == null || result['foto'] is! Map) {
    result['foto'] = {'intervalSec': 45};
  } else {
    final foto = Map<String, dynamic>.from(result['foto'] as Map);
    if (!foto.containsKey('intervalSec') || foto['intervalSec'] == null) {
      foto['intervalSec'] = 45;
    }
    result['foto'] = foto;
  }

  // 3. Transit per-stop migration (FAS 6b)
  if (result.containsKey('transit') && result['transit'] is Map) {
    final transit = Map<String, dynamic>.from(result['transit'] as Map);

    final rootWalk = (transit['walkMinutes'] as num?)?.toInt() ?? 5;
    final rootModes = transit['modes'] is List
        ? List<String>.from((transit['modes'] as List)
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty))
        : const ['train'];
    final rootDestinations = transit['destinations'] is List
        ? List<String>.from((transit['destinations'] as List)
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty))
        : const ['Mjölby', 'Linköping', 'Norrköping'];

    final rawStops = transit['stops'];
    if (rawStops is List) {
      final updatedStops = <Map<String, dynamic>>[];
      for (final s in rawStops) {
        if (s is Map) {
          final stopMap = Map<String, dynamic>.from(s);
          if (!stopMap.containsKey('walkMinutes') || stopMap['walkMinutes'] == null) {
            stopMap['walkMinutes'] = rootWalk;
          }
          if (!stopMap.containsKey('filter') ||
              stopMap['filter'] == null ||
              stopMap['filter'] is! Map) {
            stopMap['filter'] = {
              'modes': List<String>.from(rootModes),
              'destinations': List<String>.from(rootDestinations),
            };
          }
          updatedStops.add(stopMap);
        }
      }
      transit['stops'] = updatedStops;
    }

    result['transit'] = transit;
  }

  return result;
}

/// Idempotent transform från v9 till v10 för Firestore-konfigurationen (FAS 6c).
///
/// Ren funktion som:
/// 1. Sätter version till 10.
/// 2. Om 'theme' saknas sätts default: { "mode": "light", "darkFrom": "18:00", "darkTo": "07:00" }.
/// 3. Om 'theme' finns men saknar fält fylls de i med standardvärden.
/// 4. Är strikt idempotent: förändrar inga befintliga nycklar.
Map<String, dynamic> transformV9ToV10(Map<String, dynamic> rawDoc) {
  final v9 = transformV8ToV9(rawDoc);
  final result = Map<String, dynamic>.from(v9);

  // 1. Version
  result['version'] = 10;

  // 2. Tema-sektion (FAS 6c)
  if (!result.containsKey('theme') ||
      result['theme'] == null ||
      result['theme'] is! Map) {
    result['theme'] = {
      'mode': 'light',
      'darkFrom': '18:00',
      'darkTo': '07:00',
    };
  } else {
    final theme = Map<String, dynamic>.from(result['theme'] as Map);
    if (!theme.containsKey('mode') || theme['mode'] == null) {
      theme['mode'] = 'light';
    }
    if (!theme.containsKey('darkFrom') || theme['darkFrom'] == null) {
      theme['darkFrom'] = '18:00';
    }
    if (!theme.containsKey('darkTo') || theme['darkTo'] == null) {
      theme['darkTo'] = '07:00';
    }
    result['theme'] = theme;
  }

  return result;
}

/// Hanterar realtidslyssning, seeding och kodad fallback för storskärmens
/// konfiguration i Firestore (FAS 3 Beslut 3 & FAS 6a).
class DisplayConfigSource extends ChangeNotifier {
  final String familyId;
  StreamSubscription<DocumentSnapshot>? _subscription;

  DisplayConfig _config = DisplayConfig.defaultConfig();
  bool _seedAttempted = false;
  bool _upgradeAttempted = false;
  Map<String, dynamic>? _lastRawData;

  DisplayConfig get config => _config;

  DisplayConfigSource({required this.familyId}) {
    _startListening();
  }

  void _startListening() {
    if (familyId.isEmpty) {
      _config = DisplayConfig.defaultConfig();
      return;
    }

    final docRef = FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .collection('display_config')
        .doc('main');

    _subscription?.cancel();
    _subscription = docRef.snapshots().listen(
      (snap) async {
        if (!snap.exists) {
          // Dokumentet saknas: utför engångs-seed av standardkonfigurationen
          if (!_seedAttempted) {
            _seedAttempted = true;
            try {
              DisplayLog.instance.log(
                'konfig',
                'Konfigurationsdokument saknas i Firestore — seedar standardkonfiguration (v8)',
              );
              await docRef.set({
                ...DisplayConfig.defaultRawMap(),
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              DisplayLog.instance.log(
                'konfig',
                'Standardkonfiguration seedad till families/$familyId/display_config/main',
              );
            } catch (e, stack) {
              developer.log(
                'DisplayConfigSource: kunde inte seeda standardkonfiguration',
                error: e,
                stackTrace: stack,
              );
              DisplayLog.instance.log(
                'konfig',
                'Kunde inte seeda standardkonfiguration ($e) — använder kodad fallback',
              );
            }
          }
          _config = DisplayConfig.defaultConfig();
          notifyListeners();
          return;
        }

        // Dokumentet finns: parsa data med fallback-skydd
        final rawMap = snap.data();
        final rawVersion = (rawMap?['version'] as num?)?.toInt() ?? 1;

        // Telemetri för ändrade sektioner vid mottagen fjärruppdatering
        if (_lastRawData != null && rawMap != null) {
          final changedSections = <String>[];
          for (final key in [
            'schedule',
            'scenes',
            'keymap',
            'transit',
            'skolmat',
            'foto',
            'theme',
            'seededSceneIds',
            'version',
          ]) {
            final oldVal = _lastRawData![key];
            final newVal = rawMap[key];
            if (oldVal.toString() != newVal.toString()) {
              changedSections.add(key);
            }
          }
          if (changedSections.isNotEmpty) {
            DisplayLog.instance.log(
              'konfig',
              'Konfigurationsändring mottagen: ${changedSections.join(", ")}',
            );
          }
        }
        _lastRawData = rawMap != null ? Map<String, dynamic>.from(rawMap) : null;

        var fallbackTriggered = false;
        final parsed = DisplayConfig.parseWithFallback(
          rawMap,
          onFallbackTriggered: (reason) {
            fallbackTriggered = true;
            DisplayLog.instance.log(
              'konfig-fallback',
              'Ogiltig Firestore-konfig: $reason — använder kodad fallback',
            );
          },
        );

        // FAS 6c: Automatisk icke-destruktiv uppgradering om Firestore-dokumentet har version < 10.
        // Använder mergeDefaults + transformV9ToV10 och SetOptions(merge: true) så att användarredigerat
        // innehåll aldrig skrivs över.
        if (rawVersion < 10 && !_upgradeAttempted) {
          _upgradeAttempted = true;
          try {
            DisplayLog.instance.log(
              'konfig',
              'Konfiguration i Firestore har version $rawVersion (< 10) — uppgraderar med merge till v10',
            );
            final mergedMap = mergeDefaults(
              rawMap ?? {},
              DisplayConfig.defaultRawMap(),
            );
            final transformedMap = transformV9ToV10(mergedMap);
            await docRef.set({
              ...transformedMap,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            DisplayLog.instance.log(
              'konfig',
              'Uppgraderad till v10 i families/$familyId/display_config/main',
            );
          } catch (e, stack) {
            _upgradeAttempted = false; // Tillåt nytt försök vid nästa snapshot / omladdning
            developer.log(
              'DisplayConfigSource: kunde inte uppgradera konfiguration till v10',
              error: e,
              stackTrace: stack,
            );
            DisplayLog.instance.log(
              'konfig',
              'Kunde inte uppgradera konfiguration till v10 ($e)',
            );
          }
        }

        _config = parsed;
        if (!fallbackTriggered) {
          DisplayLog.instance.log(
            'konfig',
            'Konfigurationsuppdatering mottagen (v${parsed.version}, ${parsed.scenes.length} scener, ${parsed.schedule.length} schemaposter)',
          );
        }
        notifyListeners();
      },
      onError: (e, stack) {
        developer.log(
          'DisplayConfigSource: fel vid lyssning på display_config',
          error: e,
          stackTrace: stack,
        );
        DisplayLog.instance.log(
          'konfig-fallback',
          'Strömfel vid hämtning av display_config: $e — behåller aktuell konfiguration',
        );
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
