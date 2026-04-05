import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// En statisk lista för att hålla timers levande i minnet under tiden appen är igång
static final List<Map<String, dynamic>> _localTimers = [];

class PersonalCountdownScreen extends StatefulWidget {
  const PersonalCountdownScreen({super.key});

  @override
  State<PersonalCountdownScreen> createState() =>
      _PersonalCountdownScreenState();
}

class _PersonalCountdownScreenState extends State<PersonalCountdownScreen> {
  Timer? _uiTicker;

  // Håller koll på vilken timer vi tittar på
  String? _viewingTimerId;
  Map<String, dynamic>? _viewingTimerData;

  // Helskärmsläge för totalt fokus
  bool _isFullScreen = false;

  // Variabler för "Dra upp tiden" (Input)
  double _dragSeconds = 0;
  int _extraHours = 0;

  @override
  void initState() {
    super.initState();
    // Uppdaterar gränssnittet varje sekund så att nedräkningen syns live
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    super.dispose();
  }

  // --- DAGFÄRGER ---
  BoxDecoration _getDailyBackground() {
    final int weekday = DateTime.now().weekday;
    List<Color> colors;

    switch (weekday) {
      case 1: colors = [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)]; break;
      case 2: colors = [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)]; break;
      case 3: colors = [const Color(0xFFF5F5F5), const Color(0xFFCFD8DC)]; break;
      case 4: colors = [const Color(0xFFFFF3E0), const Color(0xFFFFCC80)]; break;
      case 5: colors = [const Color(0xFFFFFDE7), const Color(0xFFFFF59D)]; break;
      case 6: colors = [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)]; break;
      case 7: colors = [const Color(0xFFFFEBEE), const Color(0xFFFFCDD2)]; break;
      default: colors = [Colors.white, Colors.grey.shade200];
    }

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    );
  }

  void _startTimer() {
    final totalDurationInSeconds = (_extraHours * 3600) + _dragSeconds.toInt();
    if (totalDurationInSeconds <= 0) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dra i klockan för att ställa in tid först!")));
       return;
    }

    final startTime = DateTime.now();
    final targetTime = startTime.add(Duration(seconds: totalDurationInSeconds));
    final newId = DateTime.now().millisecondsSinceEpoch.toString();

    final newTimer = {
      'id': newId,
      'title': 'Fokustid',
      'targetTime': targetTime,
      'startTime': startTime,
    };

    setState(() {
      _localTimers.add(newTimer);
      _dragSeconds = 0;
      _extraHours = 0;
      _viewingTimerId = newId;
      _viewingTimerData = newTimer;
    });
  }

  void _updateTimeFromDrag(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    double dx = localPosition.dx - center.dx;
    double dy = localPosition.dy - center.dy;
    double angle = math.atan2(dy, dx);
    angle += math.pi / 2;

    if (angle < 0) {
      angle += 2 * math.pi;
    }

    double percent = angle / (2 * math.pi);
    double newSeconds = percent * 3600;

    // Snappa till minuter
    newSeconds = (newSeconds / 60).round() * 60.0;
    if (newSeconds >= 3540) newSeconds = 0;

    setState(() {
      _dragSeconds = newSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen && _viewingTimerId != null) {
      return _buildFullScreenFocusMode();
    }
    return _buildStandardView();
  }

  // --- VY 1: HELSKÄRMSLÄGE (FOKUS) ---
  Widget _buildFullScreenFocusMode() {
    return Scaffold(
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
        decoration: _getDailyBackground(),
        child: Stack(
          children: [
            Center(child: _buildClockLogic(isFullScreen: true)),
            Positioned(
              bottom: 30,
              right: 30,
              child: FloatingActionButton(
                backgroundColor: Colors.white.withOpacity(0.8),
                elevation: 0,
                child: const Icon(Icons.fullscreen_exit, color: Colors.black87),
                onPressed: () => setState(() => _isFullScreen = false),
              ),
            ),
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _viewingTimerData?['title'] ?? 'Fokus',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ))),
    );
  }

  // --- VY 2: STANDARDVY (INSTÄLLNINGAR & LISTA) ---
  Widget _buildStandardView() {
    // Sortera listan så att den som är klar först hamnar överst
    _localTimers.sort((a, b) {
      final tA = a['targetTime'] as DateTime;
      final tB = b['targetTime'] as DateTime;
      return tA.compareTo(tB);
    });

    if (_viewingTimerId != null) {
      final found = _localTimers.where((doc) => doc['id'] == _viewingTimerId);
      if (found.isNotEmpty) {
        _viewingTimerData = found.first;
      } else {
        _viewingTimerId = null;
        _viewingTimerData = null;
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Tid & Nedräkning",
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (_viewingTimerId != null)
            TextButton.icon(
              icon: const Icon(
                Icons.add_circle_outline,
                color: Colors.black87,
              ),
              label: const Text(
                "Ny Timer",
                style: TextStyle(color: Colors.black87),
              ),
              onPressed: () {
                setState(() {
                  _viewingTimerId = null;
                  _viewingTimerData = null;
                });
              },
            ),
        ],
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
        decoration: _getDailyBackground(),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _viewingTimerId != null
                      ? "Fokus: ${_viewingTimerData?['title'] ?? 'Timer'}"
                      : "Dra i klockan för att ställa in",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Stack(
                alignment: Alignment.center,
                children: [
                  _buildClockLogic(isFullScreen: false),
                  if (_viewingTimerId != null)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: IconButton(
                        icon: const Icon(
                          Icons.fullscreen,
                          size: 32,
                          color: Colors.black54,
                        ),
                        tooltip: "Helskärm (Fokusläge)",
                        onPressed: () => setState(() => _isFullScreen = true),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              _buildControlButtons(),
              const SizedBox(height: 20),
              const Divider(indent: 40, endIndent: 40),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  "Aktiva timers",
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _localTimers.length,
                  itemBuilder: (context, index) {
                    final timerData = _localTimers[index];
                    final isSelected = (timerData['id'] == _viewingTimerId);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _viewingTimerId = timerData['id'];
                          _viewingTimerData = timerData;
                        });
                      },
                      child: _buildActiveTimerRow(timerData, isSelected),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ))),
    );
  }

  Widget _buildClockLogic({required bool isFullScreen}) {
    double size = isFullScreen
        ? MediaQuery.of(context).size.width * 0.9 
        : 300;

    double secondsToShow = 0;
    bool isInteractive = true;

    if (_viewingTimerId != null && _viewingTimerData != null) {
      isInteractive = false;
      final targetTime = _viewingTimerData!['targetTime'] as DateTime;
      final now = DateTime.now();
      final diff = targetTime.difference(now).inSeconds;

      if (diff <= 0) {
        secondsToShow = 0;
      } else {
        secondsToShow = (diff > 3600) ? 3600 : diff.toDouble();
      }
    } else {
      isInteractive = true;
      secondsToShow = _dragSeconds;
    }

    return GestureDetector(
      onPanStart: isInteractive
          ? (d) => _updateTimeFromDrag(d.localPosition, size)
          : null,
      onPanUpdate: isInteractive
          ? (d) => _updateTimeFromDrag(d.localPosition, size)
          : null,
      onPanEnd: isInteractive ? (d) {} : null,
      onTapUp: isInteractive
          ? (d) => _updateTimeFromDrag(d.localPosition, size)
          : null,

      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isFullScreen ? 60 : 40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
          border: Border.all(
            color: Colors.black87,
            width: isFullScreen ? 12 : 8,
          ),
        ),
        child: CustomPaint(
          painter: InteractiveTimeTimerPainter(seconds: secondsToShow),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    if (_viewingTimerId != null) {
      return ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _localTimers.removeWhere((t) => t['id'] == _viewingTimerId);
            _viewingTimerId = null;
            _viewingTimerData = null;
          });
        },
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text("Avsluta Timer"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[100],
          foregroundColor: Colors.red[900],
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );
    }

    if (_dragSeconds > 0 || _extraHours > 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            onPressed: () =>
                setState(() => _extraHours = (_extraHours + 1) % 4),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.5),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text("+ ${_extraHours}h"),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _startTimer,
            icon: const Icon(Icons.play_arrow),
            label: Text(
              "Starta (${_extraHours > 0 ? '${_extraHours}h ' : ''}${(_dragSeconds / 60).toInt()} min)",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox(height: 48);
  }

  Widget _buildActiveTimerRow(Map<String, dynamic> timerData, bool isSelected) {
    final now = DateTime.now();
    final targetTime = timerData['targetTime'] as DateTime;
    final remainingSeconds = targetTime.difference(now).inSeconds;

    String timeString;
    Color textColor;

    if (remainingSeconds <= 0) {
      timeString = "KLAR!";
      textColor = Colors.green;
    } else {
      final h = remainingSeconds ~/ 3600;
      final m = (remainingSeconds % 3600) ~/ 60;
      final s = remainingSeconds % 60;
      if (h > 0) {
        timeString = "$h tim $m min";
      } else {
        timeString = "$m min $s sek";
      }
      textColor = Colors.black87;
    }

    return Card(
      elevation: isSelected ? 4 : 0,
      color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Colors.blue, width: 2)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.timer,
          color: remainingSeconds <= 0 ? Colors.green : Colors.blueAccent,
        ),
        title: Text(
          timerData['title'] ?? 'Timer',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          timeString,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.grey),
          onPressed: () {
            setState(() {
              _localTimers.removeWhere((t) => t['id'] == timerData['id']);
              if (_viewingTimerId == timerData['id']) {
                _viewingTimerId = null;
                _viewingTimerData = null;
              }
            });
          },
        ),
      ),
    );
  }
}

class InteractiveTimeTimerPainter extends CustomPainter {
  final double seconds;
  InteractiveTimeTimerPainter({required this.seconds});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width / 2) - (size.width * 0.13); 

    // 1. URTAVLA
    final tickPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = size.width * 0.005
      ..strokeCap = StrokeCap.round;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    double fontSize = size.width * 0.08; 

    for (int i = 0; i < 60; i++) {
      final angle = (2 * math.pi * (i / 60)) - (math.pi / 2);
      final isFive = (i % 5 == 0);
      final tickLength = isFive ? size.width * 0.05 : size.width * 0.025;

      final p1 = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final p2 = Offset(
        center.dx + math.cos(angle) * (radius - tickLength),
        center.dy + math.sin(angle) * (radius - tickLength),
      );

      if (isFive) {
        tickPaint.strokeWidth = size.width * 0.01;
        final numberText = i == 0 ? "0" : "$i";
        textPainter.text = TextSpan(
          text: numberText,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();

        final textRadius = radius - (size.width * 0.12);
        final tp = Offset(
          center.dx + math.cos(angle) * textRadius - (textPainter.width / 2),
          center.dy + math.sin(angle) * textRadius - (textPainter.height / 2),
        );
        textPainter.paint(canvas, tp);
      } else {
        tickPaint.strokeWidth = size.width * 0.005;
      }
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 2. TÅRTBIT (RÖD)
    double percent = seconds / 3600;
    if (percent > 1) percent = 1;

    final wedgePaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    final sweepAngle = 2 * math.pi * percent;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - (size.width * 0.02)),
      -math.pi / 2,
      sweepAngle,
      true,
      wedgePaint,
    );

    // 3. MITT-PLUPP (VIT)
    final centerKnobPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      center,
      size.width * 0.07,
      Paint()
        ..color = Colors.black12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(center, size.width * 0.065, centerKnobPaint);
    canvas.drawCircle(
      center,
      size.width * 0.065,
      Paint()
        ..color = Colors.grey[300]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant InteractiveTimeTimerPainter oldDelegate) {
    return oldDelegate.seconds != seconds;
  }
}