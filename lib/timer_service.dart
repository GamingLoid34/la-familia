import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'services/notification_service.dart';

/// Singleton fokustimer — överlever flikbyte.
class TimerService {
  TimerService._();
  static final TimerService instance = TimerService._();
  factory TimerService() => instance;

  final ValueNotifier<int> remainingSeconds = ValueNotifier(25 * 60);
  final ValueNotifier<int> totalSeconds = ValueNotifier(25 * 60);
  final ValueNotifier<bool> isRunning = ValueNotifier(false);

  Timer? _timer;

  void setTimer(int seconds) {
    totalSeconds.value = seconds;
    remainingSeconds.value = seconds;
    stopTimer();
  }

  void startTimer() {
    if (isRunning.value) return;
    if (remainingSeconds.value <= 0) return;

    isRunning.value = true;
    unawaited(NotificationService.scheduleTimerDone(
      at: DateTime.now().add(Duration(seconds: remainingSeconds.value)),
    ));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value > 1) {
        remainingSeconds.value--;
      } else {
        remainingSeconds.value = 0;
        _onReachedZero();
      }
    });
  }

  void pauseTimer() {
    _timer?.cancel();
    isRunning.value = false;
    unawaited(NotificationService.cancelTimerDone());
  }

  void stopTimer() {
    _timer?.cancel();
    isRunning.value = false;
    remainingSeconds.value = totalSeconds.value;
    unawaited(NotificationService.cancelTimerDone());
  }

  Future<void> _onReachedZero() async {
    _timer?.cancel();
    isRunning.value = false;
    try {
      await HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    await NotificationService.showTimerDoneNow();
  }
}
