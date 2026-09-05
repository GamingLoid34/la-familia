import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'display_log.dart';
import 'display_scene_models.dart';

/// Hanterar realtidslyssning, seeding och kodad fallback för storskärmens
/// konfiguration i Firestore (FAS 3 Beslut 3).
class DisplayConfigSource extends ChangeNotifier {
  final String familyId;
  StreamSubscription<DocumentSnapshot>? _subscription;

  DisplayConfig _config = DisplayConfig.defaultConfig();
  bool _seedAttempted = false;
  bool _upgradeAttempted = false;

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
                'Konfigurationsdokument saknas i Firestore — seedar standardkonfiguration (v3)',
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
        final rawData = snap.data();
        var fallbackTriggered = false;
        final parsed = DisplayConfig.parseWithFallback(
          rawData,
          onFallbackTriggered: (reason) {
            fallbackTriggered = true;
            DisplayLog.instance.log(
              'konfig-fallback',
              'Ogiltig Firestore-konfig: $reason — använder kodad fallback',
            );
          },
        );

        // FAS 4.1: Automatisk engångsuppgradering om Firestore-dokumentet har version < 3
        // TODO Storskärmsstudio: uppgraderingar ska MERGA användaranpassningar, inte skriva över
        if (parsed.version < 3 && !_upgradeAttempted) {
          _upgradeAttempted = true;
          try {
            DisplayLog.instance.log(
              'konfig',
              'Konfiguration i Firestore har version ${parsed.version} (< 3) — uppgraderar till v3',
            );
            await docRef.set({
              ...DisplayConfig.defaultRawMap(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            DisplayLog.instance.log(
              'konfig',
              'Uppgraderad till v3 i families/$familyId/display_config/main',
            );
          } catch (e, stack) {
            developer.log(
              'DisplayConfigSource: kunde inte uppgradera konfiguration till v3',
              error: e,
              stackTrace: stack,
            );
            DisplayLog.instance.log(
              'konfig',
              'Kunde inte uppgradera konfiguration till v3 ($e)',
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
