import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/user_model.dart';
import '../display/display_scene_models.dart';

/// Genererar fullständig text för Stream Deck-lathunden (FAS 6a).
String generateCheatSheetText({
  required Map<String, String> keymap,
  required Map<String, DisplayScene> scenes,
  required List<UserModel> familyMembers,
}) {
  final buffer = StringBuffer();
  buffer.writeln('══════════════════════════════════════════════════');
  buffer.writeln('  LATHUND: TANGENTER & STREAM DECK — STORSKÄRM    ');
  buffer.writeln('══════════════════════════════════════════════════\n');

  buffer.writeln('--- SCENER (SIFFROR 1–9) ---');
  for (int d = 1; d <= 9; d++) {
    final digit = '$d';
    final sceneId = keymap[digit];
    if (sceneId != null && sceneId.isNotEmpty) {
      final sceneName = scenes[sceneId]?.name ?? sceneId;
      buffer.writeln('[$digit] $sceneName ($sceneId)');
    } else {
      buffer.writeln('[$digit] — Omappad');
    }
  }
  buffer.writeln();

  buffer.writeln('--- SPOTLIGHT MEDLEMMAR (SHIFT + 1..8) ---');
  if (familyMembers.isEmpty) {
    buffer.writeln('(Inga familjemedlemmar inlästa)');
  } else {
    for (int i = 0; i < familyMembers.length && i < 8; i++) {
      final key = i + 1;
      final m = familyMembers[i];
      buffer.writeln('[Shift+$key] ${m.name}');
    }
  }
  buffer.writeln();

  buffer.writeln('--- KOMMANDON & STYRNING ---');
  buffer.writeln('[H]      Hem — återställer till aktuell vecka och schemastyrd scen');
  buffer.writeln('[N]      Natt — växlar nattläge (dämpad nattklocka)');
  buffer.writeln('[L]      Lågstimuli — dämpar färger och kontraster');
  buffer.writeln('[D]      Debug — visar/döljer felsökningspanel');
  buffer.writeln('[T]      Testtid — simulerar dygnets timmar och nattläge');
  buffer.writeln('[R]      Ladda om — uppdaterar webbsidan');
  buffer.writeln('[← / →]  Bläddra — stegar en vecka bakåt eller framåt');

  return buffer.toString();
}

/// Inställningssida för storskärmens snabbknappar och tangentmappning (FAS 6a).
///
/// Låter föräldrar koppla siffertangenter 1–9 till valfria scener, samt
/// visar och exporterar Stream Deck-lathunden.
class DisplayKeymapPage extends StatefulWidget {
  final String familyId;
  final Color dayColor;
  final List<UserModel> familyMembers;

  const DisplayKeymapPage({
    super.key,
    required this.familyId,
    required this.dayColor,
    required this.familyMembers,
  });

  @override
  State<DisplayKeymapPage> createState() => _DisplayKeymapPageState();
}

class _DisplayKeymapPageState extends State<DisplayKeymapPage> {
  bool _isSaving = false;

  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore
      .instance
      .collection('families')
      .doc(widget.familyId)
      .collection('display_config')
      .doc('main');

  Future<void> _updateKey(
    String digit,
    String? sceneId,
    DisplayConfig config,
    Map<String, dynamic> rawDoc,
  ) async {
    final updatedKeymap = Map<String, String>.from(config.keymap);
    if (sceneId == null || sceneId.isEmpty) {
      updatedKeymap.remove(digit);
    } else {
      updatedKeymap[digit] = sceneId;
    }

    final candidateMap = Map<String, dynamic>.from(rawDoc);
    candidateMap['keymap'] = updatedKeymap;

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
        'keymap': updatedKeymap,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        final name = (sceneId != null && sceneId.isNotEmpty)
            ? (config.scenes[sceneId]?.name ?? sceneId)
            : 'omappad';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Knapp $digit kopplad till $name.'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte uppdatera knapp: $e'),
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

  void _copyCheatSheet(DisplayConfig config) {
    final text = generateCheatSheetText(
      keymap: config.keymap,
      scenes: config.scenes,
      familyMembers: widget.familyMembers,
    );

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stream Deck-lathund kopierad till urklipp!'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Knappar')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final rawDoc = snapshot.data?.data() ?? {};
        final config = DisplayConfig.parseWithFallback(rawDoc);

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Snabbknappar & Tangenter',
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
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Info-banner
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                        child: const Text('⌨️', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Styrning via tangentbord',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Siffertangenter 1–9 och Stream Deck-knappar växlar scen direkt på väggskärmen.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF666677)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Siffertangenter (1–9)',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),

              // Lista över 9 siffertangenter
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      for (int d = 1; d <= 9; d++) ...[
                        _buildDigitRow(
                          digit: '$d',
                          config: config,
                          rawDoc: rawDoc,
                        ),
                        if (d < 9) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Stream Deck Lathund
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Stream Deck-lathund',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyCheatSheet(config),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Kopiera'),
                    style: TextButton.styleFrom(
                      foregroundColor: widget.dayColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                color: const Color(0xFF141923),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    generateCheatSheetText(
                      keymap: config.keymap,
                      scenes: config.scenes,
                      familyMembers: widget.familyMembers,
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFCDD6F4),
                      height: 1.45,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDigitRow({
    required String digit,
    required DisplayConfig config,
    required Map<String, dynamic> rawDoc,
  }) {
    final mappedSceneId = config.keymap[digit];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            alignment: Alignment.center,
            child: Text(
              digit,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: (mappedSceneId != null && config.scenes.containsKey(mappedSceneId))
                    ? mappedSceneId
                    : '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text(
                      '— Ingen (omappad)',
                      style: TextStyle(color: Colors.black45, fontStyle: FontStyle.italic),
                    ),
                  ),
                  ...config.scenes.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        '${e.value.name} (${e.key})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  _updateKey(digit, val, config, rawDoc);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
