import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/notification_service.dart';
import '../services/schedule_scan_service.dart';
import '../utils/date_utils.dart';
import '../utils/quick_add_parser.dart';
import '../widgets/member_avatar.dart';

enum _ScanStep { pick, scanning, review }

/// Skanna och importera ett utskrivet veckoschema (rehab, skola, sport).
class ScheduleScanPage extends StatefulWidget {
  const ScheduleScanPage({super.key});

  @override
  State<ScheduleScanPage> createState() => _ScheduleScanPageState();
}

class _ScheduleScanPageState extends State<ScheduleScanPage> {
  _ScanStep _step = _ScanStep.pick;

  Uint8List? _imageBytes;
  String _mediaType = 'image/jpeg';
  String? _errorMsg;

  late TextEditingController _titleCtrl;
  UserModel? _selectedMember;
  String _selectedSchemaKind = 'Skola';
  List<ParsedScheduleEvent> _events = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  /// Förval av medlem baserat på AI:s personHint med fuzzy Levenshtein-matchning.
  UserModel? _matchPersonHint(String? hint, List<UserModel> members) {
    if (hint == null || hint.trim().isEmpty || members.isEmpty) {
      return members.isNotEmpty ? members.first : null;
    }
    final foldedHint = foldName(hint.trim());

    // 1. Exakt matchning på foldat namn
    for (final m in members) {
      final first = m.name.split(' ').first;
      if (foldName(first) == foldedHint) return m;
    }

    // 2. Fuzzy matchning
    UserModel? bestMember;
    int? bestDist;
    int candidateCount = 0;

    for (final m in members) {
      final first = m.name.split(' ').first;
      if (first.isEmpty) continue;
      final foldedFirst = foldName(first);
      final threshold = foldedFirst.length >= 5
          ? 2
          : (foldedFirst.length >= 3 ? 1 : 0);

      final d = levenshtein(foldedHint, foldedFirst);
      if (d <= threshold) {
        if (bestDist == null || d < bestDist) {
          bestDist = d;
          bestMember = m;
          candidateCount = 1;
        } else if (d == bestDist) {
          candidateCount++;
        }
      }
    }

    if (bestMember != null && candidateCount == 1) {
      return bestMember;
    }

    return members.isNotEmpty ? members.first : null;
  }

  /// Beräknar måndagen i innevarande vecka som YYYY-MM-DD.
  String _currentWeekMonday() {
    final now = DateTime.now();
    final dayOfWeek = now.weekday; // 1 = mån, 7 = sön
    final monday = now.subtract(Duration(days: dayOfWeek - 1));
    return dateKey(monday);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1568,
        maxHeight: 1568,
        imageQuality: 80,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final name = picked.name.toLowerCase();
      String mediaType = 'image/jpeg';
      if (name.endsWith('.png')) {
        mediaType = 'image/png';
      } else if (name.endsWith('.webp')) {
        mediaType = 'image/webp';
      }

      setState(() {
        _imageBytes = bytes;
        _mediaType = mediaType;
        _step = _ScanStep.scanning;
        _errorMsg = null;
      });

      await _runScan();
    } catch (e, stack) {
      developer.log('Kunde inte välja/fota bild', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _errorMsg = 'Kunde inte läsa bilden. Försök igen.';
          _step = _ScanStep.pick;
        });
      }
    }
  }

  Future<void> _runScan() async {
    if (_imageBytes == null) return;
    try {
      final base64Str = base64Encode(_imageBytes!);
      final weekStart = _currentWeekMonday();

      final result = await ScheduleScanService.parseScheduleImage(
        imageBase64: base64Str,
        mediaType: _mediaType,
        weekStartHint: weekStart,
      );

      if (!mounted) return;

      final provider = context.read<FamilyProvider>();
      final members = provider.familyMembers;
      final matched = _matchPersonHint(result.personHint, members);

      // Bestäm veckonummer från första eventdatumet om möjligt
      int? weekNum;
      if (result.events.isNotEmpty) {
        final d = parseDate(result.events.first.date);
        if (d != null) weekNum = isoWeekNumber(d);
      }
      final weekSuffix = weekNum != null ? ' v.$weekNum' : '';
      final defaultTitle = (result.scheduleTitle.isNotEmpty
              ? result.scheduleTitle
              : 'Skannat schema') +
          weekSuffix;

      final titleLow = result.scheduleTitle.toLowerCase();
      final defaultKind =
          (titleLow.contains('rehab') || titleLow.contains('klinik'))
              ? 'Rehab'
              : 'Skola';

      setState(() {
        _titleCtrl.text = defaultTitle;
        _selectedMember = matched;
        _selectedSchemaKind = defaultKind;
        _events = result.events;
        _step = _ScanStep.review;
        _errorMsg = null;
      });
    } catch (e, stack) {
      developer.log('AI-tolkning av schema misslyckades',
          error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _errorMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
          _step = _ScanStep.scanning;
        });
      }
    }
  }

  void _shiftWeeks(int deltaWeeks) {
    setState(() {
      for (final ev in _events) {
        final d = parseDate(ev.date);
        if (d != null) {
          final shifted = d.add(Duration(days: 7 * deltaWeeks));
          ev.date = dateKey(shifted);
        }
      }

      // Uppdatera eventuellt veckonummer i titelfältet
      if (_events.isNotEmpty) {
        final d = parseDate(_events.first.date);
        if (d != null) {
          final newW = isoWeekNumber(d);
          final clean = _titleCtrl.text
              .replaceAll(RegExp(r'\s+v\.\d+'), '')
              .trim();
          _titleCtrl.text = '$clean v.$newW';
        }
      }
    });
  }

  String _formatDateSpan() {
    if (_events.isEmpty) return '';
    final dates = _events
        .map((e) => parseDate(e.date))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (dates.isEmpty) return '';
    final first = dates.first;
    final last = dates.last;
    if (first.month == last.month) {
      return '${first.day}–${last.day} ${DateFormat('MMM', 'sv').format(last)}';
    }
    return '${first.day} ${DateFormat('MMM', 'sv').format(first)} – ${last.day} ${DateFormat('MMM', 'sv').format(last)}';
  }

  Future<void> _editEvent(ParsedScheduleEvent ev) async {
    final titleCtrl = TextEditingController(text: ev.title);
    final timeCtrl = TextEditingController(text: ev.time);
    final endTimeCtrl = TextEditingController(text: ev.endTime ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Redigera schemahändelse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titel',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: timeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Starttid (HH:mm)',
                      hintText: '08:00',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: endTimeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sluttid (valfritt)',
                      hintText: '09:00',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Klar'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      setState(() {
        ev.title = titleCtrl.text.trim();
        ev.time = timeCtrl.text.trim();
        ev.endTime = endTimeCtrl.text.trim().isNotEmpty
            ? endTimeCtrl.text.trim()
            : null;
      });
    }
  }

  Future<void> _saveImport() async {
    final selectedEvents = _events.where((e) => e.selected).toList();
    if (selectedEvents.isEmpty || _selectedMember == null || _saving) return;

    setState(() => _saving = true);
    try {
      final name = _titleCtrl.text.trim().isNotEmpty
          ? _titleCtrl.text.trim()
          : 'Skannat schema';
      final person = _selectedMember!;

      final schemaLabel = _selectedSchemaKind;
      final piktogram = switch (_selectedSchemaKind) {
        'Rehab' => '🏥',
        'Jobb' => '💼',
        'Schema' => '📋',
        _ => '🏫',
      };

      final result = await ScheduleScanService.saveScheduleImport(
        name: name,
        personName: person.name,
        personUid: person.uid,
        events: selectedEvents,
        schemaLabel: schemaLabel,
        piktogram: piktogram,
      );

      if (person.familyId != null && person.familyId!.isNotEmpty) {
        unawaited(NotificationService.rescheduleAllForFamily(person.familyId!));
      }

      if (!mounted) return;

      final firstName = person.name.split(' ').first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${result.eventCount} händelser importerade till $firstName ✅'),
          backgroundColor: const Color(0xFF6BAE75),
          duration: const Duration(seconds: 4),
        ),
      );

      Navigator.pop(context);
    } catch (e, stack) {
      developer.log('Kunde inte spara schemaimport',
          error: e, stackTrace: stack);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara importen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final currentUser = provider.currentUser;
    final dayColor = AppTheme.getDayAccentColor();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    // Endast föräldrar/admins får använda denna sida
    if (currentUser != null && !currentUser.isParent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          Container(
            decoration: AppTheme.headerDecoration(),
            padding: AppTheme.paddingBelowStatusBar(context, bottom: 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'Skanna schema 📷',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (_step) {
              _ScanStep.pick => _buildPickStep(dayColor),
              _ScanStep.scanning => _buildScanningStep(dayColor),
              _ScanStep.review => _buildReviewStep(dayColor, provider.familyMembers),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPickStep(Color dayColor) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: dayColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.document_scanner_rounded,
                  size: 56, color: dayColor),
            ),
            const SizedBox(height: 20),
            const Text(
              'Importera schema med AI',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Fota ett utskrivet rehabschema, skolschema eller aktivitetsschema.\n'
              'AI tolkar datum, tider och händelser automatiskt.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildActionCard(
              title: 'Ta foto med kameran',
              subtitle: 'Håll kameran stadigt över schemat',
              icon: Icons.camera_alt_rounded,
              color: dayColor,
              onTap: () => _pickImage(ImageSource.camera),
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              title: 'Välj bild från galleriet',
              subtitle: 'Välj ett sparat foto på schemat',
              icon: Icons.photo_library_rounded,
              color: const Color(0xFF5A7D9A),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanningStep(Color dayColor) {
    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 56, color: Colors.red.shade400),
              const SizedBox(height: 16),
              const Text(
                'Kunde inte tolka schemat',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMsg!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _step = _ScanStep.pick),
                    child: const Text('Välj annan bild'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() => _errorMsg = null);
                      _runScan();
                    },
                    style: FilledButton.styleFrom(backgroundColor: dayColor),
                    child: const Text('Försök igen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  _imageBytes!,
                  height: 180,
                  width: 240,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 28),
            CircularProgressIndicator(color: dayColor),
            const SizedBox(height: 20),
            const Text(
              'Läser schemat… 🔍',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'AI analyserar rader, kolumner, tider och händelser.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewStep(Color dayColor, List<UserModel> familyMembers) {
    // Gruppera händelser per datum
    final grouped = <String, List<ParsedScheduleEvent>>{};
    for (final ev in _events) {
      grouped.putIfAbsent(ev.date, () => []).add(ev);
    }
    final sortedDates = grouped.keys.toList()..sort();
    final selectedCount = _events.where((e) => e.selected).length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            physics: const BouncingScrollPhysics(),
            children: [
              // 1. Rubrikfält
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kalendernamn',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        hintText: 'T.ex. Rehab Noomi v.35',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Vad är det för schema?
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Vad är det för schema?',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ('Skola', '🏫 Skola'),
                        ('Rehab', '🏥 Rehab'),
                        ('Jobb', '💼 Jobb'),
                        ('Schema', '📋 Annat'),
                      ].map((t) {
                        final isSel = _selectedSchemaKind == t.$1;
                        return ChoiceChip(
                          label: Text(t.$2),
                          selected: isSel,
                          selectedColor: dayColor.withValues(alpha: 0.25),
                          onSelected: (_) =>
                              setState(() => _selectedSchemaKind = t.$1),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Personväljare
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gäller familjemedlem:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: familyMembers.map((m) {
                        final isSel = _selectedMember?.uid == m.uid;
                        final color = AppTheme.colorFromHex(m.color);
                        return ChoiceChip(
                          avatar: FamilyMemberAvatar(
                            member: m,
                            size: 24,
                          ),
                          label: Text(m.name),
                          selected: isSel,
                          selectedColor: color.withValues(alpha: 0.25),
                          onSelected: (_) => setState(() => _selectedMember = m),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Veckoflytt
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => _shiftWeeks(-1),
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      label: const Text('‹ 1 vecka'),
                    ),
                    Text(
                      _formatDateSpan(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    TextButton.icon(
                      onPressed: () => _shiftWeeks(1),
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      label: const Text('1 vecka ›'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Snabbval Alla / Inga
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_events.length} händelser ($selectedCount valda)',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            for (final e in _events) {
                              e.selected = true;
                            }
                          });
                        },
                        child: const Text('Alla', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            for (final e in _events) {
                              e.selected = false;
                            }
                          });
                        },
                        child: const Text('Inga', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 4. Händelselista grupperad per dag
              for (final dateKey in sortedDates) ...[
                _buildDayGroup(
                    dateKey, grouped[dateKey] ?? const [], dayColor),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),

        // Sticky Bottom Save Button
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (selectedCount == 0 ||
                        _selectedMember == null ||
                        _saving)
                    ? null
                    : _saveImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: dayColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'Importera $selectedCount händelser',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayGroup(
      String dateStr, List<ParsedScheduleEvent> events, Color dayColor) {
    String dayHeader = dateStr;
    final dt = parseDate(dateStr);
    if (dt != null) {
      try {
        final formatted = DateFormat('EEEE d/M', 'sv').format(dt);
        dayHeader = formatted[0].toUpperCase() + formatted.substring(1);
      } catch (_) {
        dayHeader = DateFormat('EEEE d/M').format(dt);
      }
    }

    return Container(
      decoration: AppTheme.cardDecoration(radius: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 15, color: dayColor),
              const SizedBox(width: 6),
              Text(
                dayHeader,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: dayColor,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          for (final ev in events)
            InkWell(
              onTap: () => _editEvent(ev),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: ev.selected,
                      activeColor: dayColor,
                      onChanged: (v) => setState(() => ev.selected = v ?? false),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ev.endTime != null && ev.endTime!.isNotEmpty
                            ? '${ev.time}–${ev.endTime}'
                            : ev.time,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ev.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              decoration: ev.selected
                                  ? null
                                  : TextDecoration.lineThrough,
                              color: ev.selected
                                  ? Colors.black87
                                  : Colors.grey.shade400,
                            ),
                          ),
                          if (ev.location != null && ev.location!.isNotEmpty)
                            Text(
                              '📍 ${ev.location!}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined,
                        size: 16, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
