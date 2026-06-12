import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../timer_service.dart'; // Hämta vår nya tjänst

class TimerPage extends StatefulWidget {
  /// Förinställd tid (t.ex. nedräkning till nästa aktivitet).
  final int? initialSeconds;
  /// Vad nedräkningen gäller — visas under klockan.
  final String? label;

  const TimerPage({super.key, this.initialSeconds, this.label});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  final TimerService _service = TimerService(); // Koppla upp oss

  @override
  void initState() {
    super.initState();
    final s = widget.initialSeconds;
    if (s != null && s > 0) {
      _service.setTimer(s);
      _service.startTimer();
    }
  }

  String _formatTime(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Vi använder ValueListenableBuilder för att lyssna på ändringar live
    return Scaffold(
      backgroundColor: AppTheme.dayPalette().tint,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Fokus-Timer",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: _service.remainingSeconds,
          builder: (context, currentSeconds, child) {
            return ValueListenableBuilder<int>(
              valueListenable: _service.totalSeconds,
              builder: (context, maxSeconds, child) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _service.isRunning,
                  builder: (context, running, child) {
                    double progress = maxSeconds > 0
                        ? currentSeconds / maxSeconds
                        : 0.0;
                    double minutesSet = maxSeconds / 60;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),

                        // --- DEN STORA VISUELLA KLOCKAN ---
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 300,
                              height: 300,
                              child: CircularProgressIndicator(
                                value: 1.0,
                                color: Colors.grey[200],
                                strokeWidth: 20,
                              ),
                            ),
                            SizedBox(
                              width: 300,
                              height: 300,
                              child: CircularProgressIndicator(
                                value: progress,
                                color: AppTheme.getDayAccentColor(),
                                strokeWidth: 20,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(currentSeconds),
                                  style: TextStyle(
                                    fontSize: 60,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.getDayAccentColor(),
                                  ),
                                ),
                                if (currentSeconds == 0)
                                  const Text(
                                    "KLART!",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  )
                                else if (!running)
                                  const Text(
                                    "PAUSAD",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                if (widget.label != null &&
                                    widget.label!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      widget.label!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        const Spacer(),

                        if (!running && currentSeconds == maxSeconds) ...[
                          const Text(
                            "Ställ in tid (minuter)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          Slider(
                            value: minutesSet.clamp(5, 120),
                            min: 5,
                            max: 120,
                            divisions: 23,
                            activeColor: AppTheme.getDayAccentColor(),
                            onChanged: (val) {
                              _service.setTimer(val.toInt() * 60);
                            },
                          ),
                        ],

                        // --- KNAPPAR ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!running)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.getDayAccentColor(),
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(20),
                                ),
                                onPressed: () => _service.startTimer(),
                                child: const Icon(
                                  Icons.play_arrow,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              )
                            else ...[
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(20),
                                ),
                                onPressed: () => _service.pauseTimer(),
                                child: const Icon(
                                  Icons.pause,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 20),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey,
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(20),
                                ),
                                onPressed: () => _service.stopTimer(),
                                child: const Icon(
                                  Icons.stop,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 50),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ))),
    );
  }
}
