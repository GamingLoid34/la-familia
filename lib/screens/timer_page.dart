import 'package:flutter/material.dart';
import '../services/timer_service.dart'; // Hämta vår nya tjänst

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  final TimerService _service = TimerService(); // Koppla upp oss

  String _formatTime(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Vi använder ValueListenableBuilder för att lyssna på ändringar live
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Fokus-Timer", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: _service.remainingSeconds,
          builder: (context, currentSeconds, child) {
            return ValueListenableBuilder<int>(
              valueListenable: _service.totalSeconds,
              builder: (context, maxSeconds, child) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _service.isRunning,
                  builder: (context, running, child) {
                    
                    double progress = maxSeconds > 0 ? currentSeconds / maxSeconds : 0.0;
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
                              width: 300, height: 300,
                              child: CircularProgressIndicator(
                                value: 1.0,
                                color: Colors.grey[200],
                                strokeWidth: 20,
                              ),
                            ),
                            SizedBox(
                              width: 300, height: 300,
                              child: CircularProgressIndicator(
                                value: progress,
                                color: Colors.redAccent,
                                strokeWidth: 20,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(currentSeconds),
                                  style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                ),
                                if (currentSeconds == 0)
                                  const Text("KLART!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20))
                                else if (!running)
                                  const Text("PAUSAD", style: TextStyle(color: Colors.grey))
                              ],
                            ),
                          ],
                        ),
                        
                        const Spacer(),

                        // --- REGLAGE (Bara om ej aktiv) ---
                        if (!running && currentSeconds == maxSeconds) ...[
                          const Text("Ställ in tid (min