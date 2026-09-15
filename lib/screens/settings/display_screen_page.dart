import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../providers/family_provider.dart';
import '../display/display_palette.dart';
import '../display/display_scene_models.dart';

/// Inställningssida för Skärm (tema & tider) under Storskärmsstudion (FAS 6c).
///
/// Låter föräldrar välja skärmens tema:
/// - Ljust: standard ljust tema dygnet runt
/// - Mörkt: mörkt tema dygnet runt
/// - Auto: mörkt tema mellan två valda klockslag (stödjer midnattsvändning)
///
/// Inkluderar miniatyrförhandsvisning med faktiska temafärger och WCAG AA-kontraster.
class DisplayScreenPage extends StatefulWidget {
  final String familyId;
  final Color dayColor;

  const DisplayScreenPage({
    super.key,
    required this.familyId,
    required this.dayColor,
  });

  @override
  State<DisplayScreenPage> createState() => _DisplayScreenPageState();
}

class _DisplayScreenPageState extends State<DisplayScreenPage> {
  DocumentReference<Map<String, dynamic>> get _configDocRef => FirebaseFirestore
      .instance
      .collection('families')
      .doc(widget.familyId)
      .collection('display_config')
      .doc('main');

  String _mode = 'light';
  String _darkFrom = '18:00';
  String _darkTo = '07:00';
  bool _initialized = false;
  bool _isSaving = false;

  void _initFromConfig(DisplayConfig config) {
    if (_initialized) return;
    _mode = config.theme.mode;
    _darkFrom = config.theme.darkFrom;
    _darkTo = config.theme.darkTo;
    _initialized = true;
  }

  Future<void> _pickTime({
    required BuildContext context,
    required bool isFrom,
  }) async {
    final currentStr = isFrom ? _darkFrom : _darkTo;
    final parts = currentStr.split(':');
    final initialTime = TimeOfDay(
      hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 18 : 18,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isFrom) {
          _darkFrom = formatted;
        } else {
          _darkTo = formatted;
        }
      });
    }
  }

  String _formatMidnightExplanation(String from, String to) {
    if (from == to) {
      return 'Start- och sluttid är samma. Skärmen behåller ljust tema.';
    }
    final fromParts = from.split(':');
    final toParts = to.split(':');
    final fromM = (int.tryParse(fromParts.first) ?? 0) * 60 +
        (int.tryParse(fromParts.last) ?? 0);
    final toM = (int.tryParse(toParts.first) ?? 0) * 60 +
        (int.tryParse(toParts.last) ?? 0);

    if (fromM > toM) {
      return 'Mörkt tema aktiveras kl $from på kvällen, fortsätter över midnatt och återgår till ljust kl $to på morgonen.';
    } else {
      return 'Mörkt tema aktiveras kl $from och återgår till ljust kl $to under samma dag.';
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await _configDocRef.set({
        'version': 10,
        'theme': {
          'mode': _mode,
          'darkFrom': _darkFrom,
          'darkTo': _darkTo,
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Skärminställningar sparade!'),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<FamilyProvider>().currentUser;
    final isParent = currentUser?.isParent ?? true;

    if (!isParent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Skärm')),
        body: const Center(
          child: Text('Endast föräldrar har behörighet till skärminställningar.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Skärm',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _configDocRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data();
          final config = DisplayConfig.parseWithFallback(data);
          _initFromConfig(config);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // Info-banner
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.dayColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.palette_outlined,
                        color: widget.dayColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Skärmens utseende & tema',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Styr om väggskärmen ska vara ljus, mörk eller växla automatiskt vid kvällen.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF666677),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Temaväljare (SegmentedButton)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tema',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'light',
                            label: Text('Ljust'),
                            icon: Icon(Icons.light_mode_rounded),
                          ),
                          ButtonSegment<String>(
                            value: 'dark',
                            label: Text('Mörkt'),
                            icon: Icon(Icons.dark_mode_rounded),
                          ),
                          ButtonSegment<String>(
                            value: 'auto',
                            label: Text('Auto'),
                            icon: Icon(Icons.schedule_rounded),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _mode = newSelection.first;
                          });
                        },
                      ),
                    ),
                    if (_mode == 'auto') ...[
                      const SizedBox(height: 18),
                      const Divider(height: 1, color: Color(0xFFE2E5EE)),
                      const SizedBox(height: 16),
                      const Text(
                        'Tidsintervall för mörkt tema',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTimePickerTile(
                              label: 'Mörkt från',
                              timeStr: _darkFrom,
                              onTap: () => _pickTime(
                                context: context,
                                isFrom: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTimePickerTile(
                              label: 'Ljust från',
                              timeStr: _darkTo,
                              onTap: () => _pickTime(
                                context: context,
                                isFrom: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Color(0xFF5C6877),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatMidnightExplanation(_darkFrom, _darkTo),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5C6877),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Miniatyrförhandsvisning
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Förhandsgranskning',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Så här ser veckotavlan och korten ut i ljust och mörkt läge:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF666677)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildThemePreviewCard(
                            title: 'Ljust tema',
                            palette: DisplayPalette.light,
                            weekday: DateTime.now().weekday,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildThemePreviewCard(
                            title: 'Mörkt tema',
                            palette: DisplayPalette.dark,
                            weekday: DateTime.now().weekday,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Spara-knapp
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _isSaving ? 'Sparar…' : 'Spara skärminställningar',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.dayColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTimePickerTile({
    required String label,
    required String timeStr,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E5EE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF5C6877),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 18,
                  color: Color(0xFF1A1A2E),
                ),
                const SizedBox(width: 8),
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemePreviewCard({
    required String title,
    required DisplayPalette palette,
    required int weekday,
  }) {
    final dayPal = AppTheme.dayPalette(weekday);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Mini dagshuvud (IDAG)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              gradient: dayPal.gradient,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              'IDAG',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: dayPal.onColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Mini ramplatta
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            decoration: BoxDecoration(
              color: palette.ramPlateBg(widget.dayColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Text(
                  '🏫 · 08:30',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: palette.ramPlateTextColor(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Mini aktivitetskort
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(color: widget.dayColor, width: 3.5),
                top: BorderSide(color: palette.cardBorder, width: 0.8),
                right: BorderSide(color: palette.cardBorder, width: 0.8),
                bottom: BorderSide(color: palette.cardBorder, width: 0.8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚽ 17:00',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Träning',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.isDark
                        ? palette.textPrimary
                        : const Color(0xFF2C3E50),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
