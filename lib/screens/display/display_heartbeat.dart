import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'display_clock.dart';
import 'display_log.dart';

/// Sköter storskärmens periodiska hjärtslag och statusrapportering (FAS 6b).
///
/// Skriver till `families/{familyId}/display_state/status`:
/// - Vid uppstart
/// - Vid scenbyte
/// - Var 5:e minut via periodisk timer
class DisplayHeartbeat {
  final String familyId;
  final String Function() activeSceneProvider;
  final String Function() sceneSourceProvider;
  final bool Function()? testModeProvider;
  final String? Function()? lastErrorProvider;
  final int Function()? configVersionProvider;
  final bool Function()? syncOkProvider;
  final bool Function()? transitOkProvider;
  final bool Function()? weatherOkProvider;
  final bool Function()? lowStimuliProvider;
  final String Function()? themeProvider;
  final String Function()? themeModeProvider;
  final FirebaseFirestore? _firestore;

  Timer? _heartbeatTimer;
  String? _lastSentScene;
  final DateTime _startedAt = DateTime.now();

  DisplayHeartbeat({
    required this.familyId,
    required this.activeSceneProvider,
    required this.sceneSourceProvider,
    this.testModeProvider,
    this.lastErrorProvider,
    this.configVersionProvider,
    this.syncOkProvider,
    this.transitOkProvider,
    this.weatherOkProvider,
    this.lowStimuliProvider,
    this.themeProvider,
    this.themeModeProvider,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore;

  DateTime get startedAt => _startedAt;

  void start() {
    _sendHeartbeat();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _sendHeartbeat();
    });
  }

  void onSceneChanged() {
    final currentScene = activeSceneProvider();
    if (currentScene != _lastSentScene) {
      _sendHeartbeat();
    }
  }

  Map<String, dynamic> buildPayload({FieldValue? serverTimestamp}) {
    final scene = activeSceneProvider();
    final isTest = testModeProvider?.call() ?? DisplayClock.isTestTime;
    return {
      'lastSeen': serverTimestamp ?? FieldValue.serverTimestamp(),
      'appVersion': DisplayLog.appVersion,
      'buildVersion': DisplayLog.appVersion,
      'configVersion': configVersionProvider?.call() ?? 10,
      'activeScene': scene,
      'activeSceneId': scene,
      'sceneSource': sceneSourceProvider(),
      'startedAt': _startedAt.toIso8601String(),
      'testMode': isTest,
      'syncOk': syncOkProvider?.call() ?? DisplayLog.instance.syncOk,
      'transitOk': transitOkProvider?.call() ?? DisplayLog.instance.transitOk,
      'weatherOk': weatherOkProvider?.call() ?? DisplayLog.instance.weatherOk,
      'lowStimuli': lowStimuliProvider?.call() ?? false,
      'theme': themeProvider?.call() ?? 'light',
      'themeMode': themeModeProvider?.call() ?? 'light',
      'lastError': lastErrorProvider?.call(),
    };
  }

  Future<void> _sendHeartbeat() async {
    if (familyId.isEmpty) return;
    _lastSentScene = activeSceneProvider();

    try {
      final fs = _firestore ?? FirebaseFirestore.instance;
      final payload = buildPayload();
      await fs
          .collection('families')
          .doc(familyId)
          .collection('display_state')
          .doc('status')
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      // Hjärtslag får aldrig störa storskärmens rendering vid nätverksbortfall
      if (kDebugMode) {
        debugPrint('[DisplayHeartbeat] Kunde inte sända hjärtslag: $e');
      }
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}
