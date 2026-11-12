import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../display/display_module_registry.dart';
import '../display/display_scene_models.dart';

/// Genererar en säker scen-slug från ett visningsnamn (t.ex. "Fredagsmys!" -> "fredagsmys").
String generateSlug(String name) {
  var s = name.trim().toLowerCase();
  s = s
      .replaceAll('å', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('é', 'e');
  s = s.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  return s;
}

/// Validerar ett scen-ID (slug).
/// Returnerar null om giltigt, annars ett felmeddelande.
String? validateSceneSlug(
  String slug,
  Iterable<String> existingSlugs, {
  bool isNew = true,
}) {
  if (slug.isEmpty) return 'Scen-ID får inte vara tomt.';
  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(slug)) {
    return 'Scen-ID får endast innehålla små bokstäver (a-z), siffror (0-9) och understreck (_).';
  }
  if (isNew && existingSlugs.contains(slug)) {
    return 'Det finns redan en scen med ID "$slug". Välj ett unikt ID.';
  }
  return null;
}

/// Kontrollerar om en scen får tas bort enligt skyddsreglerna (FAS 6a).
/// Blockerar systemscener ('standard', 'natt'), schemareferenser och keymap-referenser.
String? checkSceneDeletionAllowed(String sceneId, DisplayConfig config) {
  if (sceneId == 'standard' || sceneId == 'natt') {
    return 'Scenerna "standard" och "natt" är systemkritiska och kan inte raderas.';
  }
  final scheduleMatches =
      config.schedule.where((e) => e.scene == sceneId).toList();
  if (scheduleMatches.isNotEmpty) {
    final times = scheduleMatches.map((e) => e.start).join(', ');
    return 'Scenen kan inte raderas eftersom den används i schemat ($times). Ändra schemat först.';
  }
  final keymapMatches =
      config.keymap.entries.where((e) => e.value == sceneId).toList();
  if (keymapMatches.isNotEmpty) {
    final keys = keymapMatches.map((e) => 'knapp ${e.key}').join(', ');
    return 'Scenen kan inte raderas eftersom den är kopplad till $keys. Ändra tangentmappningen först.';
  }
  return null;
}

/// Inställningssida för storskärmens scener (FAS 6a).
///
/// Låter föräldrar skapa, anpassa layouter och välja moduler per zon för scener.
/// Förändringar sparas med merge till `families/{familyId}/display_config/main`.
class DisplayScenesPage extends StatefulWidget {
  final String familyId;
  final Color dayColor;

  const DisplayScenesPage({
    super.key,
    required this.familyId,
    required this.dayColor,
  });

  @override
  State<DisplayScenesPage> createState() => _DisplayScenesPageState();
}

class _DisplayScenesPageState extends State<DisplayScenesPage> {
  bool _isSaving = false;

  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore
      .instance
      .collection('families')
      .doc(widget.familyId)
      .collection('display_config')
      .doc('main');

  Future<void> _saveScene(
    DisplayScene scene,
    Map<String, dynamic> currentDocData,
  ) async {
    final candidateMap = Map<String, dynamic>.from(currentDocData);
    final rawScenes = candidateMap['scenes'] is Map
        ? Map<String, dynamic>.from(candidateMap['scenes'] as Map)
        : <String, dynamic>{};
    rawScenes[scene.id] = scene.toMap();
    candidateMap['scenes'] = rawScenes;

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
        'scenes': {
          scene.id: scene.toMap(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scenen "${scene.name}" sparades!'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara scen: $e'),
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

  Future<void> _deleteScene(String sceneId, String sceneName) async {
    setState(() => _isSaving = true);
    try {
      await _docRef.update({
        'scenes.$sceneId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scenen "$sceneName" raderades.'),
            backgroundColor: Colors.grey.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte radera scen: $e'),
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

  void _openSceneEditor({
    required BuildContext context,
    required DisplayConfig config,
    required Map<String, dynamic> rawDoc,
    DisplayScene? existing,
  }) {
    final isNew = existing == null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final slugController = TextEditingController(text: existing?.id ?? '');
    String layout = existing?.layout ?? 'board';
    final modules = Map<String, String>.from(existing?.modules ?? {
      'main': 'veckotavla',
      'side': 'middag_vecka',
      'footer1': 'middag_idag',
      'footer2': 'sysslor_idag',
      'footer3': 'tavlan',
    });

    // Se till att standardzoner finns för vald layout
    _ensureLayoutModules(layout, modules);

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
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isNew ? 'Ny scen' : 'Redigera "${existing.name}"',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!isNew)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Ta bort scen',
                            onPressed: () {
                              final deletionError = checkSceneDeletionAllowed(
                                existing.id,
                                config,
                              );
                              if (deletionError != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(deletionError),
                                    backgroundColor: Colors.red.shade700,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(bottomSheetCtx);
                              _deleteScene(existing.id, existing.name);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Scennamn
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Scennamn',
                        hintText: 'T.ex. Helgfrukost, Lek & Spel',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (val) {
                        if (isNew) {
                          setSheetState(() {
                            slugController.text = generateSlug(val);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Scen-ID (slug)
                    if (isNew)
                      TextField(
                        controller: slugController,
                        decoration: InputDecoration(
                          labelText: 'Scen-ID (unikt kortnamn)',
                          hintText: 't.ex. helgfrukost',
                          helperText: 'Endast små bokstäver a-z, siffror och _',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'ID: ${existing.id}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Layout-val
                    const Text(
                      'Layoutmall',
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
                          value: layout,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'fullscreen',
                              child: Text('Helskärm (1 stor zon)'),
                            ),
                            DropdownMenuItem(
                              value: 'board',
                              child: Text('Tavla (huvudvy + 3 footer-rutor)'),
                            ),
                            DropdownMenuItem(
                              value: 'sidebar',
                              child: Text('Sidopanel (huvudvy + sidoruta + 3 footer)'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() {
                                layout = val;
                                _ensureLayoutModules(layout, modules);
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Schematisk Wireframe-förhandsvisning
                    const Text(
                      'Layoutskiss',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _buildSchematicPreview(layout, modules),
                    const SizedBox(height: 20),

                    // Modulväljare per zon
                    const Text(
                      'Moduler per zon',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _buildModuleSelectors(layout, modules, setSheetState),
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
                          final name = nameController.text.trim();
                          final slug = slugController.text.trim();

                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ange ett scennamn.')),
                            );
                            return;
                          }

                          final slugError = validateSceneSlug(
                            slug,
                            config.scenes.keys,
                            isNew: isNew,
                          );
                          if (slugError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(slugError),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                            return;
                          }

                          Navigator.pop(bottomSheetCtx);
                          final updatedScene = DisplayScene(
                            id: slug,
                            name: name,
                            layout: layout,
                            modules: modules,
                          );
                          _saveScene(updatedScene, rawDoc);
                        },
                        child: const Text(
                          'Spara scen',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _ensureLayoutModules(String layout, Map<String, String> modules) {
    if (!modules.containsKey('main') || modules['main']!.isEmpty) {
      modules['main'] = 'veckotavla';
    }
    if (layout == 'sidebar') {
      if (!modules.containsKey('side') || modules['side']!.isEmpty) {
        modules['side'] = 'middag_vecka';
      }
    }
    if (layout == 'board' || layout == 'sidebar') {
      if (!modules.containsKey('footer1') || modules['footer1']!.isEmpty) {
        modules['footer1'] = 'middag_idag';
      }
      if (!modules.containsKey('footer2') || modules['footer2']!.isEmpty) {
        modules['footer2'] = 'sysslor_idag';
      }
      if (!modules.containsKey('footer3') || modules['footer3']!.isEmpty) {
        modules['footer3'] = 'tavlan';
      }
    }
  }

  Widget _buildSchematicPreview(String layout, Map<String, String> modules) {
    final registry = DisplayModuleRegistry.instance;

    Widget wireframeBox(String? moduleId, {String label = ''}) {
      final meta = moduleId != null ? registry.metaFor(moduleId) : null;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2330),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (meta != null) ...[
              Icon(meta.icon, size: 14, color: Colors.amberAccent),
              const SizedBox(height: 2),
              Text(
                meta.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else ...[
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: () {
        switch (layout) {
          case 'fullscreen':
            return wireframeBox(modules['main'], label: 'Huvudyta (Helskärm)');
          case 'board':
            return Column(
              children: [
                Expanded(
                  flex: 3,
                  child: wireframeBox(modules['main'], label: 'Huvudyta'),
                ),
                const SizedBox(height: 6),
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Expanded(child: wireframeBox(modules['footer1'], label: 'F1')),
                      const SizedBox(width: 4),
                      Expanded(child: wireframeBox(modules['footer2'], label: 'F2')),
                      const SizedBox(width: 4),
                      Expanded(child: wireframeBox(modules['footer3'], label: 'F3')),
                    ],
                  ),
                ),
              ],
            );
          case 'sidebar':
          default:
            return Column(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 65,
                        child: wireframeBox(modules['main'], label: 'Huvudyta'),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 35,
                        child: wireframeBox(modules['side'], label: 'Sidopanel'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  flex: 1,
                  child: Row(
                    children: [
                      Expanded(child: wireframeBox(modules['footer1'], label: 'F1')),
                      const SizedBox(width: 4),
                      Expanded(child: wireframeBox(modules['footer2'], label: 'F2')),
                      const SizedBox(width: 4),
                      Expanded(child: wireframeBox(modules['footer3'], label: 'F3')),
                    ],
                  ),
                ),
              ],
            );
        }
      }(),
    );
  }

  Widget _buildModuleSelectors(
    String layout,
    Map<String, String> modules,
    void Function(void Function()) setSheetState,
  ) {
    final registry = DisplayModuleRegistry.instance;

    Widget zoneDropdown({
      required String zoneSlot,
      required String zoneType,
      required String label,
    }) {
      final available = registry.modulesForZone(zoneType);
      final currentMod = modules[zoneSlot] ?? available.first.id;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: available.any((m) => m.id == currentMod) ? currentMod : available.first.id,
                  isExpanded: true,
                  items: available.map((m) {
                    return DropdownMenuItem(
                      value: m.id,
                      child: Row(
                        children: [
                          Icon(m.icon, size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setSheetState(() => modules[zoneSlot] = val);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        zoneDropdown(
          zoneSlot: 'main',
          zoneType: 'main',
          label: 'Huvudyta (main)',
        ),
        if (layout == 'sidebar')
          zoneDropdown(
            zoneSlot: 'side',
            zoneType: 'side',
            label: 'Sidopanel (side)',
          ),
        if (layout == 'board' || layout == 'sidebar') ...[
          zoneDropdown(
            zoneSlot: 'footer1',
            zoneType: 'footer',
            label: 'Fotzon 1 (vänster)',
          ),
          zoneDropdown(
            zoneSlot: 'footer2',
            zoneType: 'footer',
            label: 'Fotzon 2 (mitten)',
          ),
          zoneDropdown(
            zoneSlot: 'footer3',
            zoneType: 'footer',
            label: 'Fotzon 3 (höger)',
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Scener')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final rawDoc = snapshot.data?.data() ?? {};
        final config = DisplayConfig.parseWithFallback(rawDoc);
        final scenesList = config.scenes.values.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Storskärmsscener',
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
            onPressed: () => _openSceneEditor(
              context: context,
              config: config,
              rawDoc: rawDoc,
            ),
            backgroundColor: widget.dayColor,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ny scen'),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              for (final scene in scenesList) ...[
                _buildSceneCard(scene: scene, config: config, rawDoc: rawDoc),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSceneCard({
    required DisplayScene scene,
    required DisplayConfig config,
    required Map<String, dynamic> rawDoc,
  }) {
    final isSystem = scene.id == 'standard' || scene.id == 'natt';
    final layoutIcon = scene.layout == 'fullscreen'
        ? Icons.crop_portrait_rounded
        : (scene.layout == 'sidebar'
            ? Icons.view_sidebar_rounded
            : Icons.dashboard_rounded);

    final modulesSummary = scene.modules.values.join(', ');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openSceneEditor(
          context: context,
          config: config,
          rawDoc: rawDoc,
          existing: scene,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.dayColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(layoutIcon, color: widget.dayColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          scene.name,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isSystem) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'System',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Layout: ${scene.layout} • Moduler: $modulesSummary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
}
