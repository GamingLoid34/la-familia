import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/calendar_feed_service.dart';
import '../services/family_service.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';

/// Kalenderimport (ICS) — hanteras under Planering, inte Inställningar.
class CalendarImportPage extends StatefulWidget {
  const CalendarImportPage({super.key});

  @override
  State<CalendarImportPage> createState() => _CalendarImportPageState();
}

class _CalendarImportPageState extends State<CalendarImportPage> {
  UserModel? _currentUser;
  List<UserModel> _familyMembers = [];
  List<Map<String, dynamic>> _calendarImports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await FamilyService.getCurrentUserModel()
          .timeout(const Duration(seconds: 6));
      final members = <UserModel>[];
      final calendarImports = <Map<String, dynamic>>[];
      if (user?.familyId != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('familyId', isEqualTo: user!.familyId)
            .get()
            .timeout(const Duration(seconds: 6));
        for (final d in snap.docs) {
          members.add(UserModel.fromMap(d.id, d.data()));
        }
        try {
          final impsSnap = await FirebaseFirestore.instance
              .collection('calendar_imports')
              .where('familyId', isEqualTo: user.familyId)
              .get()
              .timeout(const Duration(seconds: 4));
          for (final d in impsSnap.docs) {
            calendarImports.add({...d.data(), 'id': d.id});
          }
        } catch (e, stack) {
          developer.log('Misslyckades hämta kalendrar', error: e, stackTrace: stack);
        }
      }
      if (mounted) {
        setState(() {
          _currentUser = user;
          _familyMembers = members;
          _calendarImports = calendarImports;
          _loading = false;
        });
        if (user != null && !user.isParent) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
        }
      }
    } catch (e, stack) {
      developer.log('CalendarImportPage _loadData', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _loading = false;
          _calendarImports = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
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
                      'Kalenderimport',
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
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            SliverToBoxAdapter(child: _buildBody(dayColor)),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildBody(Color dayColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: _ImportCard(
        dayColor: dayColor,
        calendarImports: _calendarImports,
        onAddTap: _showAddCalendarDialog,
        onPurgeTap: _currentUser?.familyId == null
            ? null
            : _confirmPurgeAllCalendarImports,
        onDeleteImport: _confirmDeleteCalendarImport,
        onToggleAutoSync: _toggleAutoSync,
        onSyncNow: _syncNow,
      ),
    );
  }

  Future<void> _toggleAutoSync(String docId, bool value) async {
    try {
      await FirebaseFirestore.instance
          .collection('calendar_imports')
          .doc(docId)
          .update({'autoSync': value});
      await _loadData();
    } catch (e, stack) {
      developer.log('autoSync-toggle misslyckades', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _syncNow(String docId) async {
    Map<String, dynamic>? imp;
    for (final m in _calendarImports) {
      if (m['id'] == docId) {
        imp = m;
        break;
      }
    }
    if (imp == null) return;
    final url = (imp['feedUrl'] as String?)?.trim().isNotEmpty == true
        ? (imp['feedUrl'] as String).trim()
        : ((imp['url'] as String?) ?? '').trim();
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Denna import har ingen URL att synka.'),
          ),
        );
      }
      return;
    }

    final name = imp['name'] as String? ?? 'Kalender';
    final person = (imp['person'] as String?) ??
        (imp['assignedMember'] as String?);
    final personUid = imp['personUid'] as String?;
    final kind = (imp['planningImportKind'] as String?) ??
        (imp['targetType'] as String?) ??
        'schedule';

    try {
      final result = await CalendarFeedService.subscribe(
        url: url,
        name: name,
        person: person,
        personUid: personUid,
        targetType: kind,
        importId: docId,
      );
      if (!mounted) return;
      _showImportResult(result.eventCount, name);
      await _loadData();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Synkning misslyckades'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e, stack) {
      developer.log('Synka nu misslyckades', error: e, stackTrace: stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synkning misslyckades: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _showAddCalendarDialog() {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String? selectedMember;
    var planningImportKind = 'schedule';
    bool loading = false;
    String? errorMsg;

    showDialog(
      context: context,
      barrierDismissible: !loading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Lägg till kalender'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Kalendernamn',
                      hintText: 'T.ex. Ebba skolschema',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final guessed = memberMatchingText(_familyMembers, v);
                      if (guessed != null && selectedMember == null) {
                        setS(() => selectedMember = guessed.name);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Vem gäller kalendern?',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: Text(planningImportKind == 'schedule'
                            ? 'Välj familjemedlem (krävs för schema)'
                            : 'Välj familjemedlem (frivilligt)'),
                        value: selectedMember,
                        items: [
                          if (planningImportKind != 'schedule')
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Gemensam kalender / Ingen specifik'),
                            ),
                          ..._familyMembers.map((m) => DropdownMenuItem(
                                value: m.name,
                                child: Text(m.name),
                              ))
                        ],
                        onChanged: (val) => setS(() => selectedMember = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Var ska importen synas?',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment<String>(
                        value: 'schedule',
                        label: Text('Schema / skola',
                            style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.school_outlined, size: 16),
                      ),
                      ButtonSegment<String>(
                        value: 'activity',
                        label:
                            Text('Aktivitet', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.sports_soccer_outlined, size: 16),
                      ),
                    ],
                    selected: {planningImportKind},
                    onSelectionChanged: (s) {
                      if (s.isNotEmpty) {
                        setS(() => planningImportKind = s.first);
                      }
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    planningImportKind == 'activity'
                        ? 'Syns i planering och hem — som vanliga aktiviteter.'
                        : 'Syns under Scheman, inte i planeringslistan.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  const Text('Alternativ 1 — ICS-länk:',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: urlCtrl,
                    decoration: InputDecoration(
                      labelText: 'ICS-URL',
                      hintText:
                          'https://calendar.google.com/calendar/ical/...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Hämta från URL'),
                      onPressed: loading
                          ? null
                          : () async {
                              final url = urlCtrl.text.trim();
                              final name = nameCtrl.text.trim().isEmpty
                                  ? 'Importerad kalender'
                                  : nameCtrl.text.trim();
                              if (url.isEmpty) return;
                              final member = selectedMember ??
                                  memberMatchingText(_familyMembers, name)?.name;
                              if (planningImportKind == 'schedule' &&
                                  (member == null || member.isEmpty)) {
                                setS(() {
                                  errorMsg =
                                      'Välj vem schemat gäller, annars syns det inte i kalendern.';
                                });
                                return;
                              }
                              setS(() {
                                loading = true;
                                errorMsg = null;
                                if (member != null) selectedMember = member;
                              });
                              try {
                                final personUid = member == null
                                    ? null
                                    : uidForName(_familyMembers, member);
                                final result = await CalendarFeedService.subscribe(
                                  url: url,
                                  name: name,
                                  person: member,
                                  personUid: (personUid == null || personUid.isEmpty)
                                      ? null
                                      : personUid,
                                  targetType: planningImportKind,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _showImportResult(result.eventCount, name);
                                await _loadData();
                              } on FirebaseFunctionsException catch (e) {
                                setS(() {
                                  loading = false;
                                  errorMsg = e.message ??
                                      'Kunde inte hämta URL. Prova att ladda upp filen direkt istället.';
                                });
                              } catch (e, stack) {
                                developer.log(
                                    'Fel vid hämtning/tolkning av ICS URL',
                                    error: e,
                                    stackTrace: stack);
                                setS(() {
                                  loading = false;
                                  errorMsg =
                                      'Kunde inte hämta URL. Prova att ladda upp filen direkt istället.';
                                });
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Alternativ 2 — Ladda upp .ics-fil:',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Välj .ics-fil'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.getDayAccentColor(),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: loading
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim().isEmpty
                                  ? 'Importerad kalender'
                                  : nameCtrl.text.trim();
                              final member = selectedMember ??
                                  memberMatchingText(
                                          _familyMembers, nameCtrl.text)
                                      ?.name;
                              if (planningImportKind == 'schedule' &&
                                  (member == null || member.isEmpty)) {
                                setS(() {
                                  errorMsg =
                                      'Välj vem schemat gäller, annars syns det inte i kalendern.';
                                });
                                return;
                              }
                              setS(() {
                                loading = true;
                                errorMsg = null;
                                if (member != null) selectedMember = member;
                              });
                              try {
                                final result =
                                    await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['ics'],
                                  withData: true,
                                );
                                if (result == null || result.files.isEmpty) {
                                  setS(() => loading = false);
                                  return;
                                }
                                final bytes = result.files.first.bytes;
                                if (bytes == null) {
                                  setS(() {
                                    loading = false;
                                    errorMsg = 'Kunde inte läsa filen.';
                                  });
                                  return;
                                }
                                final content = utf8.decode(
                                  bytes,
                                  allowMalformed: true,
                                );
                                final count = await _parseAndSaveIcs(
                                  content,
                                  name,
                                  '',
                                  member,
                                  planningImportKind,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _showImportResult(count, name);
                                await _loadData();
                              } catch (e, stack) {
                                developer.log(
                                    'Fel vid uppladdning av lokal ICS fil',
                                    error: e,
                                    stackTrace: stack);
                                setS(() {
                                  loading = false;
                                  errorMsg = 'Fel: $e';
                                });
                              }
                            },
                    ),
                  ),
                  if (loading) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(errorMsg!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportResult(int count, String name) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count > 0
          ? '$count händelser importerade från "$name".'
          : 'Inga kommande händelser hittades i "$name".'),
      backgroundColor: count > 0 ? const Color(0xFF6BAE75) : Colors.orange,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _confirmDeleteCalendarImport(String docId) async {
    String label = 'denna kalender';
    for (final m in _calendarImports) {
      if (m['id'] == docId) {
        label = m['name'] as String? ?? label;
        break;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort kalenderimport?'),
        content: Text(
          'Alla händelser från "$label" som importerats till planeringen tas bort. '
          'Detta går inte att ångra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _deleteCalendarImport(docId, label);
  }

  Future<void> _deleteCalendarImport(String docId, String displayName) async {
    try {
      final impRef =
          FirebaseFirestore.instance.collection('calendar_imports').doc(docId);
      final impDoc = await impRef.get();
      if (!impDoc.exists) {
        if (mounted) {
          setState(() => _calendarImports.removeWhere((m) => m['id'] == docId));
        }
        return;
      }
      final data = impDoc.data()!;
      final familyId = data['familyId'] as String? ?? '';
      final calendarName = data['name'] as String? ?? '';

      final eventsSnap = await FirebaseFirestore.instance
          .collection('planner_events')
          .where('familyId', isEqualTo: familyId)
          .get();

      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      for (final d in eventsSnap.docs) {
        final m = d.data();
        if (m['source'] != 'calendar') continue;
        final byId = m['calendarImportId'] == docId;
        final legacy = m['calendarImportId'] == null &&
            m['calendarName'] == calendarName;
        if (!byId && !legacy) continue;
        batch.delete(d.reference);
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();

      await impRef.delete();

      if (mounted) {
        setState(() => _calendarImports.removeWhere((m) => m['id'] == docId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Kalender "$displayName" och importerade händelser är borttagna.'),
            backgroundColor: const Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('deleteCalendarImport', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte ta bort kalendern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmPurgeAllCalendarImports() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rensa alla kalenderimporter?'),
        content: const Text(
          'Alla importerade kalenderhändelser i planeringen tas bort, och alla '
          'sparade kalenderkällor i denna lista. Aktiviteter du lagt in manuellt '
          'påverkas inte. Detta går inte att ångra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rensa allt'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _purgeAllCalendarImportsForFamily();
  }

  Future<void> _purgeAllCalendarImportsForFamily() async {
    final familyId = _currentUser?.familyId;
    if (familyId == null) return;
    try {
      final eventsSnap = await FirebaseFirestore.instance
          .collection('planner_events')
          .where('familyId', isEqualTo: familyId)
          .get()
          .timeout(const Duration(seconds: 45));

      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      var deletedEvents = 0;
      for (final d in eventsSnap.docs) {
        final m = d.data();
        if (m['source'] != 'calendar') continue;
        batch.delete(d.reference);
        deletedEvents++;
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();

      final importsSnap = await FirebaseFirestore.instance
          .collection('calendar_imports')
          .where('familyId', isEqualTo: familyId)
          .get()
          .timeout(const Duration(seconds: 15));

      batch = FirebaseFirestore.instance.batch();
      ops = 0;
      var deletedImports = 0;
      for (final d in importsSnap.docs) {
        batch.delete(d.reference);
        deletedImports++;
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();

      if (mounted) {
        setState(() => _calendarImports = []);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rensat: $deletedEvents importerade händelser och $deletedImports kalenderkällor.',
            ),
            backgroundColor: const Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('purgeAllCalendarImports', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte rensa: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<int> _parseAndSaveIcs(
    String icsContent,
    String name,
    String url,
    String? assignedMember,
    String planningImportKind,
  ) async {
    final kind =
        planningImportKind == 'activity' ? 'activity' : 'schedule';
    final raw =
        icsContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final lines = <String>[];
    for (final line in raw) {
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          lines.isNotEmpty) {
        lines[lines.length - 1] += line.substring(1);
      } else {
        lines.add(line);
      }
    }

    final events = <Map<String, String>>[];
    Map<String, String>? current;
    for (final line in lines) {
      final t = line.trim();
      if (t == 'BEGIN:VEVENT') {
        current = {};
      } else if (t == 'END:VEVENT' && current != null) {
        events.add(current);
        current = null;
      } else if (current != null) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          final keyRaw = line.substring(0, idx);
          final val = line.substring(idx + 1).trim();
          final key = keyRaw.split(';')[0].toUpperCase();
          current[key] = val;
        }
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final familyId = _currentUser?.familyId ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final importRef =
        FirebaseFirestore.instance.collection('calendar_imports').doc();
    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (final ev in events) {
      final title = _decodeIcsText(ev['SUMMARY'] ?? '');
      if (title.isEmpty) continue;
      final dtStart = _parseDtstart(ev['DTSTART']);
      if (dtStart == null) continue;
      if (dtStart.isBefore(today)) continue;
      if (count >= 200) break;

      final startHm = dtStart.hour == 0 && dtStart.minute == 0
          ? ''
          : '${dtStart.hour.toString().padLeft(2, '0')}:${dtStart.minute.toString().padLeft(2, '0')}';
      final endHm = _icsEndTimeHm(ev, dtStart);

      final ref = FirebaseFirestore.instance.collection('planner_events').doc();
      final fields = <String, dynamic>{
        'title': title,
        'piktogram': kind == 'activity' ? '📋' : '📚',
        'type': 'activity',
        'date': dateKey(dtStart),
        'time': startHm,
        'persons': assignedMember != null ? [assignedMember] : <String>[],
        'personUids': assignedMember != null
            ? uidsForNames(_familyMembers, [assignedMember])
            : <String>[],
        'checklist': <dynamic>[],
        'source': 'calendar',
        'planningImportKind': kind,
        'calendarName': name,
        'calendarImportId': importRef.id,
        'createdBy': uid,
        'createdByUid': uid,
        'isPending': false,
        'familyId': familyId,
      };
      if (endHm != null && endHm.isNotEmpty) {
        fields['endTime'] = endHm;
      }

      final desc = _sanitizeIcsBody(ev['DESCRIPTION'] ?? '');
      if (desc.isNotEmpty) {
        fields['calendarDescription'] = desc.length > _maxIcsDescriptionChars
            ? '${desc.substring(0, _maxIcsDescriptionChars)}…'
            : desc;
      }

      final loc = _sanitizeIcsBody(ev['LOCATION'] ?? '');
      if (loc.isNotEmpty) {
        fields['location'] = loc.length > 2000
            ? '${loc.substring(0, 2000)}…'
            : loc;
      }

      final calUrl = _decodeIcsText(ev['URL'] ?? '').trim();
      if (calUrl.isNotEmpty) {
        fields['calendarUrl'] = calUrl.length > 2000
            ? calUrl.substring(0, 2000)
            : calUrl;
      }

      final extras = _icsExtendedProps(ev);
      if (extras.isNotEmpty) {
        fields['calendarExtendedProps'] = extras;
      }

      batch.set(ref, fields);
      count++;
    }

    if (count > 0) {
      batch.set(importRef, {
        'name': name,
        'url': url,
        'feedUrl': '',
        'familyId': familyId,
        'lastSync': FieldValue.serverTimestamp(),
        'eventCount': count,
        'source': url.isEmpty ? 'file' : 'url',
        'autoSync': false,
        'planningImportKind': kind,
        'targetType': kind,
        'assignedMember': ?assignedMember,
        'person': ?assignedMember,
        'personUid': assignedMember == null
            ? null
            : uidForName(_familyMembers, assignedMember),
        'createdByUid': uid,
      });
      await batch.commit();
    }

    return count;
  }

  static const int _maxIcsDescriptionChars = 15000;

  /// För DESCRIPTION/LOCATION: avkoda ICS, enkel HTML → radbrytningar, rensa taggar.
  String _sanitizeIcsBody(String raw) {
    if (raw.isEmpty) return '';
    var t = _decodeIcsText(raw);
    t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    t = t.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    t = t.replaceAll(RegExp(r'<[^>]*>'), '');
    t = t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return t;
  }

  /// Egna ICS-fält (t.ex. Sportadmin) som X-…
  Map<String, String> _icsExtendedProps(Map<String, String> ev) {
    final out = <String, String>{};
    for (final e in ev.entries) {
      final k = e.key;
      if (!k.startsWith('X-')) continue;
      final v = _sanitizeIcsBody(e.value);
      if (v.isEmpty) continue;
      out[k] = v.length > 2000 ? '${v.substring(0, 2000)}…' : v;
    }
    return out;
  }

  String _decodeIcsText(String text) => text
      .replaceAll('\\n', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  DateTime? _parseDtstart(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final clean = value.replaceAll('Z', '').trim();
      if (clean.length < 8) return null;
      final y = int.parse(clean.substring(0, 4));
      final m = int.parse(clean.substring(4, 6));
      final d = int.parse(clean.substring(6, 8));
      int h = 0, min = 0;
      if (clean.length >= 15 && clean[8] == 'T') {
        h = int.parse(clean.substring(9, 11));
        min = int.parse(clean.substring(11, 13));
      }
      return DateTime(y, m, d, h, min);
    } catch (e, stack) {
      developer.log('Fel vid tolkning av ICS-datum', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Sluttid som `HH:mm` från DTEND eller DURATION, om det finns och ligger efter start.
  String? _icsEndTimeHm(Map<String, String> ev, DateTime dtStart) {
    final dur = _parseIcsDuration(ev['DURATION']);
    if (dur != null && dur > Duration.zero) {
      final end = dtStart.add(dur);
      if (!end.isAfter(dtStart)) return null;
      return _formatHm(end);
    }
    final dtEnd = _parseDtstart(ev['DTEND']);
    if (dtEnd == null || !dtEnd.isAfter(dtStart)) return null;
    return _formatHm(dtEnd);
  }

  String _formatHm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Duration? _parseIcsDuration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var s = raw.trim().toUpperCase();
    if (!s.startsWith('P')) return null;
    int days = 0;
    final dm = RegExp(r'(\d+)D').firstMatch(s);
    if (dm != null) days = int.parse(dm.group(1)!);
    final wm = RegExp(r'(\d+)W').firstMatch(s);
    if (wm != null) days += int.parse(wm.group(1)!) * 7;
    var tp = '';
    final tIdx = s.indexOf('T');
    if (tIdx >= 0) tp = s.substring(tIdx + 1);
    var hours = 0, minutes = 0, seconds = 0;
    final hm = RegExp(r'(\d+)H').firstMatch(tp);
    if (hm != null) hours = int.parse(hm.group(1)!);
    final mm = RegExp(r'(\d+)M').firstMatch(tp);
    if (mm != null) minutes = int.parse(mm.group(1)!);
    final sm = RegExp(r'(\d+)S').firstMatch(tp);
    if (sm != null) seconds = int.parse(sm.group(1)!);
    if (days == 0 && hours == 0 && minutes == 0 && seconds == 0) return null;
    return Duration(days: days, hours: hours, minutes: minutes, seconds: seconds);
  }
}

class _ImportCard extends StatelessWidget {
  final Color dayColor;
  final List<Map<String, dynamic>> calendarImports;
  final VoidCallback onAddTap;
  final VoidCallback? onPurgeTap;
  final void Function(String id) onDeleteImport;
  final void Function(String id, bool value) onToggleAutoSync;
  final void Function(String id) onSyncNow;

  const _ImportCard({
    required this.dayColor,
    required this.calendarImports,
    required this.onAddTap,
    required this.onPurgeTap,
    required this.onDeleteImport,
    required this.onToggleAutoSync,
    required this.onSyncNow,
  });

  String _formatLastSync(dynamic raw) {
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (dt == null) return 'Aldrig synkad';
    try {
      return 'Senast synkad ${DateFormat('d MMM HH:mm', 'sv').format(dt)}';
    } catch (_) {
      return 'Senast synkad ${DateFormat('d MMM HH:mm').format(dt)}';
    }
  }

  bool _hasFeedUrl(Map<String, dynamic> imp) {
    final feed = (imp['feedUrl'] as String?)?.trim() ?? '';
    final url = (imp['url'] as String?)?.trim() ?? '';
    return feed.isNotEmpty || url.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.calendar_month_rounded, color: dayColor, size: 20),
            const SizedBox(width: 8),
            Text('Kalenderimport', style: AppTheme.cardTitleStyle),
          ]),
          const SizedBox(height: 8),
          Text(
            'Prenumerera på skolschema via ICS-länk (synkas automatiskt) '
            'eller ladda upp en engångsfil.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 6),
          Text(
            'Vid import väljer du schema (skola/job) eller aktivitet (t.ex. sport). '
            'Schema visas under Scheman; aktiviteter även i planering och hem.',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600, height: 1.35),
          ),
          if (calendarImports.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final imp in calendarImports)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: dayColor, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            imp['name'] as String? ?? 'Kalender',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          (imp['planningImportKind'] as String? ??
                                      imp['targetType'] as String? ??
                                      'schedule') ==
                                  'activity'
                              ? 'Aktivitet'
                              : 'Schema',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: dayColor,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 22, color: Colors.grey.shade600),
                          tooltip: 'Ta bort prenumeration och händelser',
                          onPressed: () {
                            final id = imp['id'];
                            if (id is String) onDeleteImport(id);
                          },
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 24, right: 8),
                      child: Text(
                        '${_formatLastSync(imp['lastSync'])} · '
                        '${imp['eventCount'] ?? 0} händelser'
                        '${imp['autoSync'] == true ? '' : (imp['source'] == 'file' ? ' · engångsfil' : '')}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                    if (_hasFeedUrl(imp)) ...[
                      SwitchListTile(
                        contentPadding: const EdgeInsets.only(left: 12),
                        dense: true,
                        title: const Text('Automatisk synk',
                            style: TextStyle(fontSize: 13)),
                        subtitle: const Text('Uppdateras varje natt',
                            style: TextStyle(fontSize: 11)),
                        value: imp['autoSync'] == true,
                        activeThumbColor: dayColor,
                        onChanged: (v) {
                          final id = imp['id'];
                          if (id is String) onToggleAutoSync(id, v);
                        },
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            final id = imp['id'];
                            if (id is String) onSyncNow(id);
                          },
                          icon: Icon(Icons.sync_rounded,
                              size: 18, color: dayColor),
                          label: Text('Synka nu',
                              style: TextStyle(color: dayColor, fontSize: 13)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: Icon(Icons.add_rounded, color: dayColor),
            label: Text('Lägg till kalender', style: TextStyle(color: dayColor)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onAddTap,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onPurgeTap,
            icon: Icon(Icons.delete_sweep_rounded,
                size: 20, color: Colors.red.shade700),
            label: Text(
              'Rensa alla kalenderimporter och importerade händelser',
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
