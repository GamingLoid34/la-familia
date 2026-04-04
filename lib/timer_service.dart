import 'dart:async';
import 'package:flutter/foundation.dart';

class TimerService {
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
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value > 0) {
        remainingSeconds.value--;
      } else {
        stopTimer();
      }
    });
  }

  void pauseTimer() {
    _timer?.cancel();
    isRunning.value = false;
  }

  void stopTimer() {
    _timer?.cancel();
    isRunning.value = false;
    remainingSeconds.value = totalSeconds.value;
  }
}
