import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../display/modules/avgangar_module.dart';
import '../display/display_scene_models.dart';

/// Inställningssida för Tåg & bussar (Kollektivtrafik) under Storskärmsstudion (FAS 6b).
///
/// Låter föräldrar söka hållplatser, ställa in individuell gångtid (0–30 min),
/// filtrera på färdmedel (tåg/buss) och destinationer, samt förhandsgranska
/// nästa avgång med direkt live-uppdatering vid reglageändring.
class DisplayTransitPage extends StatefulWidget {
  final String familyId;
  final Color dayColor;

  const DisplayTransitPage({
    super.key,
    required this.familyId,
    required this.dayColor,
  });

  @override
  State<DisplayTransitPage> createState() => _DisplayTransitPageState();
}

class _DisplayTransitPageState extends State<DisplayTransitPage> {
  DocumentReference<Map<String, dynamic>> get _configDocRef => FirebaseFirestore
      .instance
      .collection('families')
      .doc(widget.familyId)
      .collection('display_config')
      .doc('main');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tåg & bussar',
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
          final stops = config.transit.stops;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // Info-kort
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
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
                            child: Icon(Icons.directions_transit_filled_rounded,
                                color: widget.dayColor, size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hållplatser på storskärmen',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Lägg till stationer eller busskurer. Ställ in gångtid så räknar skärmen ner när du måste gå.',
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF666677)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (stops.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(28),
                        margin: const EdgeInsets.only(top: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.departure_board_rounded,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'Inga hållplatser inlagda än',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tryck på knappen nedan för att söka efter din närmaste tågstation eller busshållplats.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xFF666677)),
                            ),
                          ],
                        ),
                      )
                    else
                      ...stops.map((stop) => _buildStopCard(context, config, stop)),

                    const SizedBox(height: 24),
                    // Trafiklab attribution
                    Center(
                      child: Text(
                        'Tidtabellsdata från Trafiklab.se (ResRobot v2.1)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSearchStopSheet(context),
        backgroundColor: widget.dayColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Lägg till hållplats',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildStopCard(
    BuildContext context,
    DisplayConfig config,
    DisplayTransitStop stop,
  ) {
    final filterModes = stop.filter?.modes ?? const <String>[];
    final filterDest = stop.filter?.destinations ?? const <String>[];
    final hasTrain = filterModes.contains('train');
    final hasBus = filterModes.contains('bus');

    IconData leadIcon = Icons.directions_transit_rounded;
    if (hasTrain && !hasBus) {
      leadIcon = Icons.train_rounded;
    } else if (hasBus && !hasTrain) {
      leadIcon = Icons.directions_bus_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openEditStopSheet(context, config, stop),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.dayColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(leadIcon, color: widget.dayColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hållplats-ID: ${stop.id}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildBadge(
                          icon: Icons.directions_walk_rounded,
                          label: stop.walkMinutes > 0
                              ? '${stop.walkMinutes} min gångtid'
                              : 'Ingen gångtid (0 min)',
                          color: Colors.blue.shade50,
                          textColor: Colors.blue.shade900,
                        ),
                        if (hasTrain)
                          _buildBadge(
                            icon: Icons.train_rounded,
                            label: 'Tåg',
                            color: Colors.green.shade50,
                            textColor: Colors.green.shade900,
                          ),
                        if (hasBus)
                          _buildBadge(
                            icon: Icons.directions_bus_rounded,
                            label: 'Buss',
                            color: Colors.orange.shade50,
                            textColor: Colors.orange.shade900,
                          ),
                        if (filterDest.isNotEmpty)
                          _buildBadge(
                            icon: Icons.filter_alt_outlined,
                            label: filterDest.join(', '),
                            color: Colors.purple.shade50,
                            textColor: Colors.purple.shade900,
                          )
                        else
                          _buildBadge(
                            icon: Icons.check_circle_outline_rounded,
                            label: 'Alla destinationer',
                            color: Colors.grey.shade100,
                            textColor: Colors.grey.shade700,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit_outlined, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // REDIGERA HÅLLPLATS SHEET (MED LIVE FÖRHANDSVISNING)
  // ──────────────────────────────────────────────────────────────────────────

  void _openEditStopSheet(
    BuildContext context,
    DisplayConfig config,
    DisplayTransitStop stop,
  ) {
    int walkMinutes = stop.walkMinutes;
    final modes = stop.filter?.modes ?? const <String>[];
    final selectedModes = Set<String>.from(
      modes.isEmpty ? ['train', 'bus'] : modes,
    );
    final destinations = List<String>.from(stop.filter?.destinations ?? const <String>[]);
    final destTextController = TextEditingController();

    bool isLoadingLive = true;
    List<Map<String, dynamic>> liveDepartures = [];
    String? liveError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          // Hämtning av live-avgångar för förhandsgranskning (endast en gång vid öppning)
          if (isLoadingLive && liveDepartures.isEmpty && liveError == null) {
            FirebaseFunctions.instance
                .httpsCallable('displayTransit')
                .call<Map<String, dynamic>>({
              'stopIds': [stop.id],
              'limit': 15,
            }).then((resp) {
              final rawStops = resp.data['stops'] as List<dynamic>? ?? [];
              if (rawStops.isNotEmpty) {
                final first = rawStops[0] as Map<String, dynamic>;
                final deps = (first['departures'] as List<dynamic>? ?? [])
                    .map((d) => Map<String, dynamic>.from(d as Map))
                    .toList();
                setSheetState(() {
                  liveDepartures = deps;
                  isLoadingLive = false;
                });
              } else {
                setSheetState(() {
                  isLoadingLive = false;
                });
              }
            }).catchError((err) {
              setSheetState(() {
                isLoadingLive = false;
                liveError = 'Kunde inte hämta live-avgångar';
              });
            });
          }

          // Filtrera avgångar baserat på sheetets aktuella lokala tillstånd
          final now = DateTime.now();
          final filteredDeps = liveDepartures.where((dep) {
            final mode = (dep['mode'] ?? '').toString();
            final dest = (dep['destination'] ?? '').toString();

            if (selectedModes.isNotEmpty && !selectedModes.contains(mode)) {
              return false;
            }
            if (destinations.isNotEmpty) {
              final match = destinations.any((d) =>
                  dest.toLowerCase().contains(d.toLowerCase()));
              if (!match) return false;
            }
            return true;
          }).toList();

          // Formatera nästa avgång med samma formaterare som storskärmen
          Widget previewWidget;
          if (isLoadingLive) {
            previewWidget = const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Hämtar live-avgångar för förhandsvisning…',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            );
          } else if (liveError != null) {
            previewWidget = Text(
              liveError!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            );
          } else if (filteredDeps.isEmpty) {
            previewWidget = Text(
              'Inga avgångar matchar valt filter just nu.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            );
          } else {
            final rawDep = filteredDeps.first;
            final nextDep = TransitDeparture.fromMap(
              rawDep,
              stopId: stop.id,
              stopName: stop.name,
              stopIcon: stop.icon,
            );
            final depLabel = formatFooterDeparture(
              nextDep,
              now,
              walkMinutes: walkMinutes,
            );
            final schedDiff = calculateMinutesUntil(nextDep.scheduled, now);
            final gaOm = calculateWalkMinutes(schedDiff, walkMinutes: walkMinutes);
            final walkingLabel = formatWalkingLabel(gaOm, now: now);

            final isWalkNow = walkingLabel == 'GÅ NU';
            previewWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  depLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isWalkNow ? Colors.red.shade100 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    walkingLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isWalkNow ? Colors.red.shade900 : Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            );
          }

          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rubrik & stängknapp
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stop.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              'Hållplats-ID: ${stop.stopId}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // LIVE FÖRHANDSVISNINGSKORT
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.visibility_rounded,
                                size: 16, color: widget.dayColor),
                            const SizedBox(width: 6),
                            const Text(
                              'Förhandsvisning (storskärmens fot)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF666677),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        previewWidget,
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // GÅNGTID REGLAGE (0–30 MIN)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Gångtid från hemmet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        walkMinutes > 0 ? '$walkMinutes min' : '0 min (av)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: widget.dayColor,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: walkMinutes.toDouble(),
                    min: 0,
                    max: 30,
                    divisions: 30,
                    activeColor: widget.dayColor,
                    label: '$walkMinutes min',
                    onChanged: (val) {
                      setSheetState(() => walkMinutes = val.round());
                    },
                  ),
                  Text(
                    'Skärmen visar "Gå om X min" baserat på gångtiden du anger här.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 20),

                  // FÄRDMEDEL (MODES)
                  const Text(
                    'Färdmedel som visas',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilterChip(
                        avatar: const Icon(Icons.train_rounded, size: 16),
                        label: const Text('Tåg'),
                        selected: selectedModes.contains('train'),
                        selectedColor: widget.dayColor.withValues(alpha: 0.2),
                        checkmarkColor: widget.dayColor,
                        onSelected: (sel) {
                          setSheetState(() {
                            if (sel) {
                              selectedModes.add('train');
                            } else if (selectedModes.length > 1) {
                              selectedModes.remove('train');
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.directions_bus_rounded, size: 16),
                        label: const Text('Buss'),
                        selected: selectedModes.contains('bus'),
                        selectedColor: widget.dayColor.withValues(alpha: 0.2),
                        checkmarkColor: widget.dayColor,
                        onSelected: (sel) {
                          setSheetState(() {
                            if (sel) {
                              selectedModes.add('bus');
                            } else if (selectedModes.length > 1) {
                              selectedModes.remove('bus');
                            }
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // DESTINATIONSFILTER
                  const Text(
                    'Filter: destinationer',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lämna tomt för att visa alla avgångar, eller lägg till destinationer att filtrera på.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  if (destinations.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: destinations
                          .map(
                            (dest) => Chip(
                              label: Text(dest),
                              deleteIcon: const Icon(Icons.close_rounded, size: 16),
                              onDeleted: () {
                                setSheetState(() => destinations.remove(dest));
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: destTextController,
                          decoration: InputDecoration(
                            hintText: 'T.ex. Linköping C eller Eksjö',
                            hintStyle: TextStyle(
                                fontSize: 13, color: Colors.grey.shade400),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onSubmitted: (val) {
                            final trimmed = val.trim();
                            if (trimmed.isNotEmpty &&
                                !destinations.contains(trimmed)) {
                              setSheetState(() {
                                destinations.add(trimmed);
                                destTextController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final trimmed = destTextController.text.trim();
                          if (trimmed.isNotEmpty &&
                              !destinations.contains(trimmed)) {
                            setSheetState(() {
                              destinations.add(trimmed);
                              destTextController.clear();
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.dayColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Lägg till'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // KNAPPAR: TA BORT & SPARA
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Ta bort'),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (dCtx) => AlertDialog(
                              title: const Text('Ta bort hållplats?'),
                              content: Text(
                                'Vill du ta bort ${stop.name} från storskärmen?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dCtx, false),
                                  child: const Text('Avbryt'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => Navigator.pop(dCtx, true),
                                  child: const Text('Ta bort'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            final updatedStops = config.transit.stops
                                .where((s) => s.stopId != stop.stopId)
                                .toList();
                            await _saveStops(updatedStops);
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('${stop.name} togs bort')),
                              );
                            }
                          }
                        },
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.dayColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final updatedStop = stop.copyWith(
                            walkMinutes: walkMinutes,
                            filter: DisplayTransitFilter(
                              modes: selectedModes.toList(),
                              destinations: destinations,
                            ),
                          );

                          final updatedStops = config.transit.stops.map((s) {
                            return s.stopId == stop.stopId ? updatedStop : s;
                          }).toList();

                          await _saveStops(updatedStops);
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Hållplatsen sparades')),
                            );
                          }
                        },
                        child: const Text(
                          'Spara ändringar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SÖK HÅLLPLATS SHEET (VIA BACKEND SEARCHSTOPS)
  // ──────────────────────────────────────────────────────────────────────────

  void _openSearchStopSheet(BuildContext context) {
    final searchController = TextEditingController();
    bool isSearching = false;
    List<Map<String, dynamic>> searchResults = [];
    String? searchError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> performSearch() async {
            final query = searchController.text.trim();
            if (query.length < 2) {
              setSheetState(() {
                searchError = 'Skriv minst 2 tecken för att söka';
                searchResults = [];
              });
              return;
            }

            setSheetState(() {
              isSearching = true;
              searchError = null;
            });

            try {
              final resp = await FirebaseFunctions.instance
                  .httpsCallable('displayTransit')
                  .call<Map<String, dynamic>>({
                'action': 'searchStops',
                'query': query,
              });

              final rawList = resp.data['stops'] as List<dynamic>? ?? [];
              final stops = rawList
                  .map((s) => Map<String, dynamic>.from(s as Map))
                  .toList();

              setSheetState(() {
                isSearching = false;
                searchResults = stops;
                if (stops.isEmpty) {
                  searchError = 'Inga hållplatser hittades för "$query"';
                }
              });
            } catch (e) {
              setSheetState(() {
                isSearching = false;
                searchError = 'Kunde inte söka just nu. Kontrollera anslutningen.';
              });
            }
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sök hållplats',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'T.ex. Tranås station eller Storgatan',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => performSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.dayColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isSearching ? null : performSearch,
                      child: isSearching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sök'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (searchError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      searchError!,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ),

                Expanded(
                  child: ListView.builder(
                    itemCount: searchResults.length,
                    itemBuilder: (context, i) {
                      final s = searchResults[i];
                      final name = (s['name'] ?? '').toString();
                      final stopId = (s['stopId'] ?? '').toString();
                      final modes = List<String>.from(s['modes'] ?? []);

                      IconData icon = Icons.location_on_outlined;
                      if (modes.contains('train') && !modes.contains('bus')) {
                        icon = Icons.train_rounded;
                      } else if (modes.contains('bus') && !modes.contains('train')) {
                        icon = Icons.directions_bus_rounded;
                      } else if (modes.contains('train') && modes.contains('bus')) {
                        icon = Icons.directions_transit_rounded;
                      }

                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: widget.dayColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, size: 20, color: widget.dayColor),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('ID: $stopId · ${modes.join(', ')}'),
                        trailing: Icon(Icons.add_circle_outline_rounded,
                            color: widget.dayColor),
                        onTap: () async {
                          final doc = await _configDocRef.get();
                          final currentConfig =
                              DisplayConfig.parseWithFallback(doc.data());
                          final existing = currentConfig.transit.stops;

                          if (existing.any((st) => st.stopId == stopId)) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Hållplatsen finns redan i listan'),
                                ),
                              );
                            }
                            return;
                          }

                          // Standard: 5 minuter gångtid, färdmedel från sökresultatet
                          final isTrain = modes.contains('train');
                          final newStop = DisplayTransitStop(
                            id: stopId,
                            name: name,
                            icon: isTrain ? '🚆' : '🚌',
                            walkMinutes: 5,
                            filter: DisplayTransitFilter(
                              modes: modes.where((m) => m != 'unknown').toList(),
                              destinations: const [],
                            ),
                          );

                          final updated = [...existing, newStop];
                          await _saveStops(updated);

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$name lades till!')),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveStops(List<DisplayTransitStop> stops) async {
    await _configDocRef.set({
      'transit': {
        'stops': stops.map((s) => s.toMap()).toList(),
      },
    }, SetOptions(merge: true));
  }
}
