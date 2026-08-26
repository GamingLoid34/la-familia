import 'dart:async';
import 'package:flutter/foundation.dart';

/// Central minutpuls (Fas 2½) — uppdaterar [now] när minuten byts.
/// Wrappa tidskänsliga texter i ValueListenableBuilder så bara de byggs om.
class MinuteTicker {
  MinuteTicker._();

  static final ValueNotifier<DateTime> now = ValueNotifier(DateTime.now());
  static Timer? _t;

  static void ensureRunning() {
    _t ??= Timer.periodic(const Duration(seconds: 20), (_) {
      final n = DateTime.now();
      if (n.minute != now.value.minute) now.value = n;
    });
  }
}
