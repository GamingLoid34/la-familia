import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../display/display_scene_models.dart';

/// Beskriver ett tidsblock i 24-timmarsremsan.
class ScheduleTimelineBlock {
  final int startMinutes;
  final int endMinutes;
  final String sceneId;

  const ScheduleTimelineBlock({
    required this.startMinutes,
    required this.endMinutes,
    required this.sceneId,
  });

  double get durationHours => (endMinutes - startMinutes) / 60.0;
}

/// Formaterar en lista med veckodagar (1..7) till en läsbar svensk text.
String formatScheduleDays(List<int>? days) {
  if (days == null || days.isEmpty || days.length == 7) {
    return 'Alla dagar';
  }
  final sorted = List<int>.from(days)..sort();
  if (sorted.length == 5 &&
      sorted[0] == 1 &&
      sorted[1] == 2 &&
      sorted[2] == 3 &&
      sorted[3] == 4 &&
      sorted[4] == 5) {
    return 'Mån–Fre';
  }
  if (sorted.length == 2 && sorted[0] == 6 && sorted[1] == 7) {
    return 'Lör–Sön';
  }
  const dayNames = {
    1: 'Mån',
    2: 'Tis',
    3: 'Ons',
    4: 'Tors',
    5: 'Fre',
    6: 'Lör',
    7: 'Sön',
  };
  return sorted.map((d) => dayNames[d] ?? '$d').join(', ');
}

/// Validerar en lista med schemaposter.
/// Returnerar null om giltigt, annars felmeddelande.
String? validateSchedule(List<DisplayScheduleEntry> entries) {
  if (entries.isEmpty) {
    return 'Schemat måste innehålla minst en post.';
  }

  for (int i = 0; i < entries.length; i++) {
    for (int j = i + 1; j < entries.length; j++) {
      final a = entries[i];
      final b = entries[j];
      if (a.startMinutes == b.startMinutes) {
        final aDays = (a.days == null || a.days!.isEmpty)
            ? {1, 2, 3, 4, 5, 6, 7}
            : a.days!.toSet();
        final bDays = (b.days == null || b.days!.isEmpty)
            ? {1, 2, 3, 4, 5, 6, 7}
            : b.days!.toSet();
        if (aDays.intersection(bDays).isNotEmpty) {
          return 'Två schemaposter kan inte ha samma starttid (${a.start}) på överlappande dagar.';
        }
      }
    }
  }
  return null;
}

/// Beräknar en 24h-tidslinje uppdelad i sammanhängande block för given veckodag (1..7).
/// Återanvänder [resolveScheduledScene] för konsekvent beteende mot väggen.
List<ScheduleTimelineBlock> compute24hTimeline(
  int weekday,
  List<DisplayScheduleEntry> schedule,
) {
  if (schedule.isEmpty) return const [];

  final blocks = <ScheduleTimelineBlock>[];
  String? currentScene;
  int blockStart = 0;

  // Sampla varje minut under dygnet (0..1439)
  // År 2026-01-05 var en måndag (weekday 1)
  final baseDate = DateTime(2026, 1, 4 + weekday);

  for (int m = 0; m < 1440; m++) {
    final sampleTime = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      m ~/ 60,
      m % 60,
    );
    final scene = resolveScheduledScene(sampleTime, schedule);

    if (currentScene == null) {
      currentScene = scene;
      blockStart = m;
    } else if (scene != currentScene) {
      blocks.add(ScheduleTimelineBlock(
        startMinutes: blockStart,
        endMinutes: m,
        sceneId: currentScene,
      ));
      currentScene = scene;
      blockStart = m;
    }
  }

  if (currentScene != null) {
    blocks.add(ScheduleTimelineBlock(
      startMinutes: blockStart,
      endMinutes: 1440,
      sceneId: currentScene,
    ));
  }

  return blocks;
}

/// Inställningssida för storskärmens dygns- och veckoschema (FAS 6a).
///
/// Låter föräldrar redigera när olika scener visas över dygnet och veckodagarna.
/// Förändringar sparas med merge till `families/{familyId}/display_config/main`.
class DisplaySchedulePage extends StatefulWidget {
  final String familyId;
  final Color dayColor;

  const DisplaySchedulePage({
    super.key,
    required this.familyId,
    required this.dayColor,
  });

  @override
  State<DisplaySchedulePage> createState() => _DisplaySchedulePageState();
}

class _DisplaySchedulePageState extends State<DisplaySchedulePage> {
  int _selectedWeekday = DateTime.now().weekday;
  bool _isSaving = false;

  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore
      .instance
      .collection('families')
      .doc(widget.familyId)
      .collection('display_config')
      .doc('main');

  Color _colorForScene(String sceneId) {
    switch (sceneId) {
      case 'morgon':
        return const Color(0xFFF9A825); // Morgonsol
      case 'standard':
        return const Color(0xFF2E7D32); // Grönt/dag
      case 'kvall':
        return const Color(0xFF6A1B9A); // Purpur/kväll
      case 'natt':
        return const Color(0xFF283593); // Mörkblå/natt
      case 'foto':
        return const Color(0xFF00838F); // Teal
      default:
        return const Color(0xFF455A64); // Gråblå för custom
    }
  }

  Future<void> _saveSchedule(
    List<DisplayScheduleEntry> entries,
    Map<String, dynamic> currentDocData,
  ) async {
    final validationError = validateSchedule(entries);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final candidateMap = Map<String, dynamic>.from(currentDocData);
    candidateMap['schedule'] = entries.map((e) => e.toMap()).toList();

    final configError = validateDisplayConfig(candidateMap);
    if (configError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ogiltig konfiguration: $configError'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _docRef.set({
        'schedule': entries.map((e) => e.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schemat sparades och uppdateras på skärmen!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara schema: $e'),
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

  void _openEntryEditor({
    required BuildContext context,
    required DisplayConfig config,
    required Map<String, dynamic> rawDoc,
    DisplayScheduleEntry? existing,
    int? existingIndex,
  }) {
    String startTime = existing?.start ?? '08:00';
    String sceneId = existing?.scene ??
        (config.scenes.containsKey('standard')
            ? 'standard'
            : config.scenes.keys.first);
    final selectedDays = (existing?.days != null && existing!.days!.isNotEmpty)
        ? Set<int>.from(existing.days!)
        : <int>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final parts = startTime.split(':');
            final currentHour = int.tryParse(parts[0]) ?? 8;
            final currentMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        existing != null ? 'Redigera schemapost' : 'Ny schemapost',
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (existing != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Ta bort post',
                          onPressed: () {
                            Navigator.pop(bottomSheetCtx);
                            final updated = List<DisplayScheduleEntry>.from(config.schedule);
                            if (existingIndex != null && existingIndex < updated.length) {
                              updated.removeAt(existingIndex);
                              _saveSchedule(updated, rawDoc);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Starttid
                  const Text(
                    'Starttid',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: currentHour, minute: currentMinute),
                        builder: (pickerCtx, child) {
                          return MediaQuery(
                            data: MediaQuery.of(pickerCtx).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        final h = picked.hour.toString().padLeft(2, '0');
                        final m = picked.minute.toString().padLeft(2, '0');
                        setSheetState(() => startTime = '$h:$m');
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            startTime,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Nunito',
                            ),
                          ),
                          const Icon(Icons.access_time_rounded, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Scenval
                  const Text(
                    'Scen som ska visas',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: config.scenes.containsKey(sceneId) ? sceneId : null,
                        isExpanded: true,
                        items: config.scenes.entries.map((e) {
                          return DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _colorForScene(e.key),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  e.value.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setSheetState(() => sceneId = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Veckodagar
                  const Text(
                    'Gäller dagar (lämna tomt för alla dagar)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (int day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(['Mån', 'Tis', 'Ons', 'Tors', 'Fre', 'Lör', 'Sön'][day - 1]),
                          selected: selectedDays.contains(day),
                          selectedColor: widget.dayColor.withValues(alpha: 0.25),
                          checkmarkColor: widget.dayColor,
                          onSelected: (selected) {
                            setSheetState(() {
                              if (selected) {
                                selectedDays.add(day);
                              } else {
                                selectedDays.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Spara-knapp
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.dayColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(bottomSheetCtx);
                        final newEntry = DisplayScheduleEntry(
                          start: startTime,
                          scene: sceneId,
                          days: (selectedDays.isEmpty || selectedDays.length == 7)
                              ? null
                              : (selectedDays.toList()..sort()),
                        );
                        final updated = List<DisplayScheduleEntry>.from(config.schedule);
                        if (existingIndex != null && existingIndex < updated.length) {
                          updated[existingIndex] = newEntry;
                        } else {
                          updated.add(newEntry);
                        }
                        // Sortera efter starttid
                        updated.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
                        _saveSchedule(updated, rawDoc);
                      },
                      child: const Text(
                        'Klar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Schema')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final rawDoc = snapshot.data?.data() ?? {};
        final config = DisplayConfig.parseWithFallback(rawDoc);
        final schedule = List<DisplayScheduleEntry>.from(config.schedule)
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

        final timelineBlocks = compute24hTimeline(_selectedWeekday, schedule);

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Storskärmsschema',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEntryEditor(
              context: context,
              config: config,
              rawDoc: rawDoc,
            ),
            backgroundColor: widget.dayColor,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ny post'),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 24h Förhandsvisningssektion
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '24-timmarsöversikt',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            ['Mån', 'Tis', 'Ons', 'Tors', 'Fre', 'Lör', 'Sön'][_selectedWeekday - 1],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: widget.dayColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Veckodagsväljare för förhandsvisningen
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int d = 1; d <= 7; d++) ...[
                              ChoiceChip(
                                label: Text(
                                  ['Mån', 'Tis', 'Ons', 'Tors', 'Fre', 'Lör', 'Sön'][d - 1],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedWeekday == d ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                selected: _selectedWeekday == d,
                                selectedColor: widget.dayColor.withValues(alpha: 0.2),
                                onSelected: (sel) {
                                  if (sel) setState(() => _selectedWeekday = d);
                                },
                              ),
                              if (d < 7) const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Tidslinjeremsa
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 28,
                          child: Row(
                            children: timelineBlocks.map((block) {
                              final sceneName =
                                  config.scenes[block.sceneId]?.name ?? block.sceneId;
                              final flex = (block.endMinutes - block.startMinutes).clamp(1, 1440);
                              return Expanded(
                                flex: flex,
                                child: Tooltip(
                                  message:
                                      '$sceneName (${_formatMinutes(block.startMinutes)}–${_formatMinutes(block.endMinutes)})',
                                  child: Container(
                                    color: _colorForScene(block.sceneId),
                                    alignment: Alignment.center,
                                    child: flex > 90
                                        ? Text(
                                            sceneName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('00:00', style: TextStyle(fontSize: 10, color: Colors.black45)),
                          Text('06:00', style: TextStyle(fontSize: 10, color: Colors.black45)),
                          Text('12:00', style: TextStyle(fontSize: 10, color: Colors.black45)),
                          Text('18:00', style: TextStyle(fontSize: 10, color: Colors.black45)),
                          Text('24:00', style: TextStyle(fontSize: 10, color: Colors.black45)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Schemaposter',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),

              // Lista över schemaposter
              for (int idx = 0; idx < schedule.length; idx++) ...[
                _buildScheduleCard(
                  entry: schedule[idx],
                  config: config,
                  rawDoc: rawDoc,
                  index: idx,
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 80), // Luft för FAB
            ],
          ),
        );
      },
    );
  }

  Widget _buildScheduleCard({
    required DisplayScheduleEntry entry,
    required DisplayConfig config,
    required Map<String, dynamic> rawDoc,
    required int index,
  }) {
    final sceneName = config.scenes[entry.scene]?.name ?? entry.scene;
    final sceneColor = _colorForScene(entry.scene);
    final daysText = formatScheduleDays(entry.days);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEntryEditor(
          context: context,
          config: config,
          rawDoc: rawDoc,
          existing: entry,
          existingIndex: index,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.start,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: sceneColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sceneName,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      daysText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
