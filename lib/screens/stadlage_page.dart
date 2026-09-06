import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../data/stadzoner.dart';
import '../services/chore_service.dart';
import '../services/notification_service.dart';
import '../utils/chore_utils.dart';
import '../utils/date_utils.dart';
import '../widgets/trasa_chip.dart';

/// Fullskärms-runner för delsteg i städläge (FAS S1 & S2).
/// NPF-anpassad: max en sak i fokus åt gången, stor knapp, immersivt läge,
/// färgkodad zoninformation (Ronald McDonald Hus-modellen).
class StadlagePage extends StatefulWidget {
  final String choreId;
  final Color? accent;
  final DateTime? targetDay;

  const StadlagePage({
    super.key,
    required this.choreId,
    this.accent,
    this.targetDay,
  });

  @override
  State<StadlagePage> createState() => _StadlagePageState();
}

class _StadlagePageState extends State<StadlagePage> {
  late final ConfettiController _confettiController;
  int? _overrideStepIndex;
  bool _isCompleting = false;
  bool _showSuccessView = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _confettiController.dispose();
    super.dispose();
  }

  Color _parseHexColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return Colors.grey;
  }

  /// Separerar inledande emoji från delstegstiteln om sådan finns.
  ({String emoji, String text}) _parseStep(String rawTitle, String fallbackEmoji) {
    final trimmed = rawTitle.trim();
    if (trimmed.isEmpty) return (emoji: fallbackEmoji, text: '');
    final spaceIdx = trimmed.indexOf(' ');
    if (spaceIdx > 0) {
      final candidate = trimmed.substring(0, spaceIdx).trim();
      final rest = trimmed.substring(spaceIdx + 1).trim();
      final hasAlphaNumeric =
          RegExp(r'[a-zA-Z0-9åäöÅÄÖ]').hasMatch(candidate);
      if (!hasAlphaNumeric && candidate.isNotEmpty) {
        return (emoji: candidate, text: rest);
      }
    }
    return (emoji: fallbackEmoji, text: trimmed);
  }

  Future<void> _handleStepDone({
    required DocumentReference docRef,
    required List<Map<String, dynamic>> substeps,
    required int currentIndex,
    required Map<String, dynamic> choreData,
  }) async {
    if (_isCompleting) return;

    final updatedSubsteps = List<Map<String, dynamic>>.from(
      substeps.map((s) => Map<String, dynamic>.from(s)),
    );
    updatedSubsteps[currentIndex]['isDone'] = true;

    final allDone = updatedSubsteps.every((s) => s['isDone'] == true);

    setState(() {
      _overrideStepIndex = null;
    });

    if (!allDone) {
      // Spara delsteget i Firestore och gå vidare till nästa obockade
      try {
        await docRef.update({'substeps': updatedSubsteps});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kunde inte spara delsteg: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    // Sista steget: bocka klart hela sysslan via callable optimistiskt
    setState(() => _isCompleting = true);
    final target = widget.targetDay ?? DateTime.now();
    final dayKey = dateKey(target);

    try {
      // 1. Skriv uppdaterat substeps först
      await docRef.update({'substeps': updatedSubsteps});

      // 2. Anropa completeChore
      await ChoreService.completeChore(
        choreId: widget.choreId,
        done: true,
        dayKey: dayKey,
      );

      await NotificationService.cancelChoreInstance(widget.choreId, target);

      // 3. Om återkommande: nollställ delsteg-bockarna så nästa tillfälle börjar tomt
      if (choreIsRecurring(choreData)) {
        final resetSubsteps = updatedSubsteps.map((s) => {
              'title': s['title'],
              'isDone': false,
            }).toList();
        await docRef.update({'substeps': resetSubsteps});
      }

      if (mounted) {
        _confettiController.play();
        setState(() {
          _isCompleting = false;
          _showSuccessView = true;
        });
      }
    } catch (e) {
      // Rollback delsteget om slutförandet misslyckades
      updatedSubsteps[currentIndex]['isDone'] = false;
      try {
        await docRef.update({'substeps': updatedSubsteps});
      } catch (_) {}

      if (mounted) {
        setState(() => _isCompleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('permission-denied')
                  ? 'Du kan bara bocka av egna eller otilldelade sysslor.'
                  : 'Kunde inte slutföra sysslan: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultAccent = widget.accent ?? AppTheme.getDayAccentColor();
    final isLowStimulus = AppTheme.lowStimuli;

    return Scaffold(
      backgroundColor: isLowStimulus ? const Color(0xFFF9F9FB) : Colors.white,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chores')
            .doc(widget.choreId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return _buildErrorState(context);
          }

          final doc = snapshot.data!;
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final choreTitle = (data['chore'] as String?) ??
              (data['title'] as String?) ??
              'Syssla';
          final pik = (data['piktogram'] as String?) ?? '🧹';

          // Zoninfo (FAS S2)
          final stadKey = data['stadKey'] as String?;
          final stadFarg = data['stadFarg'] as String?;
          final rawVerktyg = (data['verktyg'] as List? ?? []).cast<String>();
          final knownZon = stadZonByKey(stadKey);
          final farg = stadFarg ?? knownZon?.farg;
          final fargHex = knownZon?.fargHex ??
              (farg == 'gul'
                  ? StadFarger.gulHex
                  : farg == 'vit'
                      ? StadFarger.vitHex
                      : farg == 'bla'
                          ? StadFarger.blaHex
                          : farg == 'rod'
                              ? StadFarger.rodHex
                              : null);
          final trasaLabel = knownZon?.trasaLabel;
          final verktyg = rawVerktyg.isNotEmpty
              ? rawVerktyg
              : (knownZon?.verktyg ?? const <String>[]);

          final zoneColor = (fargHex != null && fargHex.isNotEmpty)
              ? _parseHexColor(fargHex)
              : null;
          final accent = zoneColor ?? defaultAccent;

          final rawSubsteps = (data['substeps'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          final substeps = rawSubsteps
              .map((s) => {
                    'title': s['title'] as String? ?? '',
                    'isDone': s['isDone'] == true,
                  })
              .toList();

          if (_showSuccessView) {
            return _buildSuccessState(
                context, choreTitle, pik, accent, isLowStimulus);
          }

          if (substeps.isEmpty) {
            return _buildNoSubstepsState(context, choreTitle, pik, accent);
          }

          // Räkna klara
          final completedCount =
              substeps.where((s) => s['isDone'] == true).length;
          final totalCount = substeps.length;

          // Hitta aktivt steg
          int activeIndex = -1;
          if (_overrideStepIndex != null &&
              _overrideStepIndex! >= 0 &&
              _overrideStepIndex! < substeps.length &&
              substeps[_overrideStepIndex!]['isDone'] == false) {
            activeIndex = _overrideStepIndex!;
          } else {
            activeIndex = substeps.indexWhere((s) => s['isDone'] == false);
          }

          // Om alla steg redan är klara
          if (activeIndex == -1) {
            return _buildSuccessState(
                context, choreTitle, pik, accent, isLowStimulus);
          }

          final currentStep = substeps[activeIndex];
          final parsedStep =
              _parseStep(currentStep['title'] as String, pik);

          // Kommande steg (exklusive aktuellt, endast obockade)
          final upcoming = <({int index, String title, String emoji})>[];
          for (int i = 0; i < substeps.length; i++) {
            if (i != activeIndex && substeps[i]['isDone'] == false) {
              final parsed =
                  _parseStep(substeps[i]['title'] as String, pik);
              upcoming.add((index: i, title: parsed.text, emoji: parsed.emoji));
            }
          }

          final hasZoneInfo =
              farg != null || verktyg.isNotEmpty || trasaLabel != null || stadKey != null;

          return Stack(
            children: [
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Topprad
                    _buildTopBar(
                      context: context,
                      choreTitle: choreTitle,
                      pik: pik,
                      completedCount: completedCount,
                      totalCount: totalCount,
                      accent: accent,
                      isLowStimulus: isLowStimulus,
                    ),

                    // Zoninfo-banner (FAS S2)
                    if (hasZoneInfo)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: (zoneColor ?? accent)
                              .withValues(alpha: isLowStimulus ? 0.08 : 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (zoneColor ?? accent)
                                .withValues(alpha: isLowStimulus ? 0.2 : 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            TrasaChip(
                              farg: farg,
                              fargHex: fargHex,
                              trasaLabel: trasaLabel,
                              verktyg: verktyg,
                            ),
                            if (farg != null && verktyg.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Verktyg: ${verktyg.join(', ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                    // Mitten: AKTUELLT steg dominerar
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                parsedStep.emoji,
                                style: const TextStyle(fontSize: 64),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                parsedStep.text.isNotEmpty
                                    ? parsedStep.text
                                    : currentStep['title'] as String,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  height: 1.25,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Stor knapp: "KLAR ✓"
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: SizedBox(
                        height: 72,
                        child: FilledButton(
                          onPressed: _isCompleting
                              ? null
                              : () => _handleStepDone(
                                    docRef: doc.reference,
                                    substeps: substeps,
                                    currentIndex: activeIndex,
                                    choreData: data,
                                  ),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            elevation: isLowStimulus ? 0 : 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: _isCompleting
                              ? const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Text(
                                  'KLAR ✓',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // Nederst: Kommande steg
                    _buildUpcomingSection(upcoming, isLowStimulus),
                    const SizedBox(height: 12),
                  ],
                ),
              ),

              // Konfetti-overlay
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  emissionFrequency: 0.1,
                  numberOfParticles: 25,
                  colors: [accent, Colors.amber, Colors.pink, Colors.purple],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar({
    required BuildContext context,
    required String choreTitle,
    required String pik,
    required int completedCount,
    required int totalCount,
    required Color accent,
    required bool isLowStimulus,
  }) {
    final progressFraction = totalCount > 0 ? completedCount / totalCount : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 28),
                color: AppTheme.getTextColor(),
                tooltip: 'Pausa och stäng',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Text(pik, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  choreTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$completedCount av $totalCount',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        // Tunn progressbar i accentfärgen
        Container(
          height: 4,
          width: double.infinity,
          color: isLowStimulus
              ? Colors.grey.shade200
              : accent.withValues(alpha: 0.15),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progressFraction.clamp(0.0, 1.0),
            child: Container(
              color: accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingSection(
    List<({int index, String title, String emoji})> upcoming,
    bool isLowStimulus,
  ) {
    if (upcoming.isEmpty) {
      return const SizedBox(height: 8);
    }

    final visible = upcoming.take(3).toList();
    final remainingCount = upcoming.length - visible.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Kommande steg',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          ...visible.map((step) => Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _overrideStepIndex = step.index),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 8),
                        if (step.emoji.isNotEmpty) ...[
                          Text(step.emoji,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            step.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
          if (remainingCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                '＋$remainingCount kvar',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(
    BuildContext context,
    String choreTitle,
    String pik,
    Color accent,
    bool isLowStimulus,
  ) {
    return Stack(
      children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const Text(
                  '🌟',
                  style: TextStyle(fontSize: 80),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Klart! 🌟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bra jobbat! Du har slutfört alla steg i "$choreTitle" $pik.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      elevation: isLowStimulus ? 0 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Stäng',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.1,
            numberOfParticles: 30,
            colors: [accent, Colors.amber, Colors.pink, Colors.purple],
          ),
        ),
      ],
    );
  }

  Widget _buildNoSubstepsState(
    BuildContext context,
    String choreTitle,
    String pik,
    Color accent,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const Spacer(),
            Text(pik, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              choreTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Den här sysslan har inga delsteg inlagda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const Spacer(),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Tillbaka',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Sysslan kunde inte hittas.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Stäng'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
