import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../widgets/member_avatar.dart';
import '../display/display_scene_models.dart';
import 'manual_school_menu_card.dart';

/// Skolalternativ hämtat från Mateo via Cloud Function displaySchoolMenu (action: "list").
class MateoSchoolItem {
  final String id;
  final String name;
  final String type;

  const MateoSchoolItem({
    required this.id,
    required this.name,
    required this.type,
  });

  factory MateoSchoolItem.fromMap(Map<String, dynamic> map) {
    return MateoSchoolItem(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      type: (map['type'] as String? ?? 'school').trim(),
    );
  }
}

/// Inställningssida för Skolmat på storskärmen (FAS 5.1).
///
/// Låter föräldrar koppla familjens barn till skola och kommun (Tranås / Linköping).
/// Vid sparning skrivs `display_config.skolmat.schools` grupperat per skola till
/// `families/{familyId}/display_config/main`. Storskärmen uppdateras reaktivt
/// via dess snapshot-lyssnare.
class DisplaySkolmatPage extends StatefulWidget {
  final String familyId;
  final Color dayColor;
  final List<UserModel> familyMembers;
  final UserModel? currentUser;

  const DisplaySkolmatPage({
    super.key,
    required this.familyId,
    required this.dayColor,
    required this.familyMembers,
    this.currentUser,
  });

  @override
  State<DisplaySkolmatPage> createState() => _DisplaySkolmatPageState();
}

class _DisplaySkolmatPageState extends State<DisplaySkolmatPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Förvalt och cachat skolregister per kommun
  final Map<String, List<MateoSchoolItem>> _schoolsByMunicipality = {
    'tranas': [
      const MateoSchoolItem(id: '318', name: 'Junkaremålsskolan', type: 'school'),
      const MateoSchoolItem(id: '323', name: 'Fröafallsskolan', type: 'school'),
      const MateoSchoolItem(id: '354', name: 'Granelundsskolan', type: 'school'),
      const MateoSchoolItem(id: '330', name: 'Gripenbergs skola', type: 'school'),
      const MateoSchoolItem(id: '343', name: 'Hubbarpsskolan', type: 'school'),
      const MateoSchoolItem(id: '335', name: 'Linderås skola', type: 'school'),
      const MateoSchoolItem(id: '352', name: 'Restaurang Parkhallen', type: 'school'),
      const MateoSchoolItem(id: '338', name: 'Sommens skola', type: 'school'),
      const MateoSchoolItem(id: '346', name: 'Ängarydsskolan', type: 'school'),
    ],
    'linkoping': [
      const MateoSchoolItem(id: '50', name: 'Anders Ljungstedts Gymnasium', type: 'highschool'),
    ],
  };

  // Håller koll på om en kommun körs på hårdkodad offline-fallback
  final Map<String, bool> _isFallbackByMunicipality = {
    'tranas': true,
    'linkoping': true,
  };

  // Barnens valda inställningar: memberUid -> municipality ('tranas' | 'linkoping')
  final Map<String, String> _selectedMunicipality = {};

  // Barnens valda skola: memberUid -> schoolId (null / tom sträng = Visas inte)
  final Map<String, String?> _selectedSchoolId = {};

  // Manuella skolor skapade för familjen: schoolId -> config (FAS 5.1b)
  final Map<String, DisplaySkolmatSchoolConfig> _manualSchoolsById = {};

  @override
  void initState() {
    super.initState();
    _loadConfigAndSchools();
  }

  /// Hämtar befintlig Firestore-konfiguration och skolligor från Cloud Function
  Future<void> _loadConfigAndSchools() async {
    setState(() => _isLoading = true);

    try {
      // 1. Läs befintlig konfig från Firestore
      final docSnap = await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .collection('display_config')
          .doc('main')
          .get();

      final existingSchools = (docSnap.data()?['skolmat']?['schools'] as List?) ?? [];

      // Mappa memberUid -> befintlig skola och kommun
      for (final s in existingSchools) {
        if (s is Map) {
          final sId = s['id']?.toString() ?? '';
          final sName = s['name']?.toString() ?? '';
          final sSource = (s['source']?.toString() ?? 'mateo').toLowerCase();
          final sMun = (s['municipality']?.toString() ?? 'tranas').toLowerCase();
          final uids = (s['memberUids'] as List?)?.map((u) => u.toString()).toList() ?? [];

          if (sSource == 'manual') {
            _manualSchoolsById[sId] = DisplaySkolmatSchoolConfig(
              id: sId,
              name: sName,
              source: 'manual',
              memberUids: uids,
            );
          }

          for (final uid in uids) {
            _selectedSchoolId[uid] = sId;
            _selectedMunicipality[uid] = sMun;
          }
        }
      }

      // Förval för barn som saknar inställning
      final children = _relevantMembers;
      for (final child in children) {
        _selectedMunicipality.putIfAbsent(child.uid, () => 'tranas');
      }

      // 2. Hämta uppdaterade skolligor via Cloud Function i bakgrunden
      _fetchSchoolsFromProxy('tranas');
      _fetchSchoolsFromProxy('linkoping');
    } catch (e, stack) {
      developer.log('Kunde inte läsa skolmat-konfig: $e', error: e, stackTrace: stack);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchSchoolsFromProxy(String municipality) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('displaySchoolMenu');
      final response = await callable.call<dynamic>({
        'action': 'list',
        'municipality': municipality,
      });

      final data = response.data;
      if (data is Map && data['schools'] is List) {
        final list = (data['schools'] as List)
            .whereType<Map>()
            .map((m) => MateoSchoolItem.fromMap(Map<String, dynamic>.from(m)))
            .toList();

        if (list.isNotEmpty && mounted) {
          setState(() {
            _schoolsByMunicipality[municipality] = list;
            _isFallbackByMunicipality[municipality] = false;
          });
          return;
        }
      }
      developer.log('[displaySchoolMenu] Använder hårdkodad offline-fallbacklista för $municipality');
    } catch (e) {
      developer.log(
        '[displaySchoolMenu] Kunde inte hämta skolor för $municipality ($e), använder hårdkodad offline-fallbacklista.',
      );
    }
  }

  /// Lista på relevanta medlemmar (barn/ungdomar, eller alla om inga barn finns)
  List<UserModel> get _relevantMembers {
    final children = widget.familyMembers.where((m) => !m.isParent).toList();
    if (children.isNotEmpty) return children;
    return widget.familyMembers;
  }

  String _lookupSchoolName(String municipality, String schoolId) {
    if (_manualSchoolsById.containsKey(schoolId)) {
      return _manualSchoolsById[schoolId]!.name;
    }
    final list = _schoolsByMunicipality[municipality] ?? [];
    for (final s in list) {
      if (s.id == schoolId) return s.name;
    }
    return 'Skola $schoolId';
  }

  /// Sparar de grupperade inställningarna till Firestore (fältuppdatering enbart)
  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final children = _relevantMembers;

      // Gruppera per schoolId: { schoolId: { id, name, municipality, source, memberUids } }
      final Map<String, Map<String, dynamic>> grouped = {};

      for (final child in children) {
        final schoolId = _selectedSchoolId[child.uid];
        if (schoolId == null || schoolId.isEmpty) {
          continue; // "Visas inte"
        }

        final mun = _selectedMunicipality[child.uid] ?? 'tranas';
        final isManual = _manualSchoolsById.containsKey(schoolId);
        final schoolName = _lookupSchoolName(mun, schoolId);

        if (!grouped.containsKey(schoolId)) {
          grouped[schoolId] = {
            'id': schoolId,
            'name': schoolName,
            if (!isManual) 'municipality': mun,
            'source': isManual ? 'manual' : 'mateo',
            'memberUids': <String>[],
          };
        }

        (grouped[schoolId]!['memberUids'] as List<String>).add(child.uid);
      }

      // Behåll även manuella skolor som inte har något barn mappat just nu
      for (final ms in _manualSchoolsById.values) {
        if (!grouped.containsKey(ms.id)) {
          grouped[ms.id] = {
            'id': ms.id,
            'name': ms.name,
            'source': 'manual',
            'memberUids': <String>[],
          };
        }
      }

      final schoolsPayload = grouped.values.toList();

      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .collection('display_config')
          .doc('main')
          .set({
        'skolmat': {
          'schools': schoolsPayload,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Skolmat sparad. Storskärmen uppdateras automatiskt.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('Fel vid sparande av skolmat: $e', error: e, stackTrace: stack);
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

  Future<void> _handleSchoolSelection(String childUid, String? newSchoolId) async {
    if (newSchoolId == '__new_manual__') {
      final nameCtrl = TextEditingController();
      final enteredName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ny egen matsedel'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Skolans namn',
              hintText: 'T.ex. Emilios skola (SkolFood)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () {
                final text = nameCtrl.text.trim();
                if (text.isNotEmpty) Navigator.pop(ctx, text);
              },
              child: const Text('Skapa'),
            ),
          ],
        ),
      );

      if (enteredName != null && enteredName.isNotEmpty) {
        final newId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
        final newConfig = DisplaySkolmatSchoolConfig(
          id: newId,
          name: enteredName,
          source: 'manual',
          memberUids: [childUid],
        );
        setState(() {
          _manualSchoolsById[newId] = newConfig;
          _selectedSchoolId[childUid] = newId;
        });
        await _save();
      }
      return;
    }

    setState(() {
      _selectedSchoolId[childUid] = newSchoolId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isParent = widget.currentUser?.isParent ?? true;
    if (!isParent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Skolmat')),
        body: const Center(
          child: Text('Endast föräldrar har behörighet att ändra inställningar för skolmat.'),
        ),
      );
    }

    final children = _relevantMembers;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Skolmat på storskärmen',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Spara',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: widget.dayColor,
                      ),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // Informationsruta
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lunch_dining_rounded, color: widget.dayColor, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dagens lunch på väggen',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Välj skola för varje barn. Dagens lunch visas automatiskt under barnets skolram på storskärmen.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF555566),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (children.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Inga familjemedlemmar hittades.'),
                    ),
                  ),

                // En rad / kort per barn
                ...children.map((child) => _buildChildCard(child)),

                // Sektion med manuella skolor (FAS 5.1b)
                if (_manualSchoolsById.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Egna matsedlar (uppladdade)',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  ..._manualSchoolsById.values.map((school) {
                    final assignedUids = _selectedSchoolId.entries
                        .where((e) => e.value == school.id)
                        .map((e) => e.key)
                        .toList();
                    final activeSchool = DisplaySkolmatSchoolConfig(
                      id: school.id,
                      name: school.name,
                      source: 'manual',
                      memberUids: assignedUids,
                    );
                    return ManualSchoolMenuCard(
                      school: activeSchool,
                      familyId: widget.familyId,
                      dayColor: widget.dayColor,
                      familyMembers: widget.familyMembers,
                    );
                  }),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: widget.dayColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _isSaving ? 'Sparar...' : 'Spara inställningar',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onPressed: (_isLoading || _isSaving) ? null : _save,
          ),
        ),
      ),
    );
  }

  Widget _buildChildCard(UserModel child) {
    final selectedMun = _selectedMunicipality[child.uid] ?? 'tranas';
    final selectedSchool = _selectedSchoolId[child.uid];
    final schoolList = _schoolsByMunicipality[selectedMun] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectedSchool != null
              ? widget.dayColor.withValues(alpha: 0.35)
              : Colors.grey.shade200,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Medlemshuvud
          Row(
            children: [
              FamilyMemberAvatar(member: child, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.name,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      selectedSchool != null
                          ? _lookupSchoolName(selectedMun, selectedSchool)
                          : 'Ingen meny vald (Visas inte)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selectedSchool != null
                            ? widget.dayColor
                            : const Color(0xFF888899),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // 1. Kommunval (Tranås förvalt / Linköping)
          const Text(
            'Kommun',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF666677),
            ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'tranas',
                label: Text('Tranås'),
                icon: Icon(Icons.location_city_rounded, size: 16),
              ),
              ButtonSegment<String>(
                value: 'linkoping',
                label: Text('Linköping'),
                icon: Icon(Icons.school_rounded, size: 16),
              ),
            ],
            selected: {selectedMun},
            onSelectionChanged: (newSelection) {
              if (newSelection.isEmpty) return;
              final mun = newSelection.first;
              setState(() {
                _selectedMunicipality[child.uid] = mun;
                // Återställ skola om den valda skolan inte finns i nya kommunen
                final currentSchool = _selectedSchoolId[child.uid];
                if (currentSchool != null) {
                  final inNewMun = (_schoolsByMunicipality[mun] ?? [])
                      .any((s) => s.id == currentSchool);
                  if (!inNewMun) {
                    _selectedSchoolId[child.uid] = null;
                  }
                }
              });
            },
          ),
          const SizedBox(height: 14),

          // 2. Kök / Skolval
          Row(
            children: [
              const Text(
                'Skola / Kök',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF666677),
                ),
              ),
              if (_isFallbackByMunicipality[selectedMun] ?? false) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: Colors.orange.shade200, width: 0.8),
                  ),
                  child: Text(
                    '(fallback)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            key: ValueKey('${child.uid}_${selectedMun}_$selectedSchool'),
            initialValue: (selectedSchool != null &&
                    (schoolList.any((s) => s.id == selectedSchool) ||
                        _manualSchoolsById.containsKey(selectedSchool)))
                ? selectedSchool
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: widget.dayColor, width: 1.5),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Visas inte (annan skola)',
                  style: TextStyle(
                    color: Color(0xFF888899),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              DropdownMenuItem<String?>(
                value: '__new_manual__',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        size: 18, color: widget.dayColor),
                    const SizedBox(width: 8),
                    Text(
                      'Egen matsedel (ladda upp själv)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.dayColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (_manualSchoolsById.isNotEmpty)
                ..._manualSchoolsById.values.map(
                  (ms) => DropdownMenuItem<String?>(
                    value: ms.id,
                    child: Text(
                      '${ms.name} (Egen matsedel)',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ...schoolList.map(
                (school) => DropdownMenuItem<String?>(
                  value: school.id,
                  child: Text(
                    school.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            onChanged: (newSchoolId) =>
                _handleSchoolSelection(child.uid, newSchoolId),
          ),
        ],
      ),
    );
  }
}
