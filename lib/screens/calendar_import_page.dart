import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/calendar_feed_service.dart';
import '../services/family_service.dart';
import '../services/notification_service.dart';
import '../utils/ics_summary.dart';
import '../utils/import_borttagning.dart';
import '../utils/person_match.dart';
import '../utils/schedule_time_utils.dart';
import 'schedule_scan_page.dart';

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
  final Set<String> _inferringIds = {};
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
          // Senaste importen först, så en nyss skannad omgång är lätt att
          // hitta och ta bort.
          calendarImports.sort((a, b) {
            final ta = a['lastSync'];
            final tb = b['lastSync'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            if (ta is Timestamp) return -1;
            if (tb is Timestamp) return 1;
            return 0;
          });
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
      child: Column(
        children: [
          _buildScanBanner(dayColor),
          const SizedBox(height: 16),
          _ImportCard(
            dayColor: dayColor,
            calendarImports: _calendarImports,
            inferringImportIds: _inferringIds,
            onAddTap: _showAddCalendarDialog,
            onPurgeTap: _currentUser?.familyId == null
                ? null
                : _confirmPurgeAllCalendarImports,
            onDeleteImport: _confirmDeleteCalendarImport,
            onInferEndTimes: _inferEndTimesForImport,
            onToggleAutoSync: _toggleAutoSync,
            onSyncNow: _syncNow,
          ),
        ],
      ),
    );
  }

  Widget _buildScanBanner(Color dayColor) {
    return Container(
      decoration: AppTheme.cardDecoration(radius: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ScheduleScanPage(onImportAngrad: _loadData),
              ),
            );
            await _loadData();
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: dayColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.camera_alt_rounded,
                      color: dayColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fota ett pappersschema 📷',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Låt AI tolka veckoschemat och importera händelser direkt till kalendern.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
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
                  const Text('Alternativ 2 — Ladda upp .ics-filer:',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Du kan välja flera på en gång, till exempel en fil per vecka. '
                    'Varje fil blir en egen import som går att ta bort för sig.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600, height: 1.3),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(loading ? 'Importerar…' : 'Välj .ics-filer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.getDayAccentColor(),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: loading
                          ? null
                          : () async {
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
                                  allowMultiple: true,
                                  withData: true,
                                );
                                if (result == null || result.files.isEmpty) {
                                  setS(() => loading = false);
                                  return;
                                }
                                final resultat = await _importeraIcsFiler(
                                  result.files,
                                  prefix: icsNamnPrefix(nameCtrl.text, member),
                                  member: member,
                                  kind: planningImportKind,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _visaFilsammanfattning(resultat);
                                await _loadData();
                              } catch (e, stack) {
                                developer.log(
                                    'Fel vid uppladdning av lokala ICS-filer',
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
          '"$label": Alla händelser som kom från den här importen tas bort. '
          'Manuella händelser påverkas inte.',
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
      // Gemensam med "Ångra" efter skanning: tar bort exakt importens
      // händelser och avbokar deras lokala påminnelser.
      await taBortKalenderimport(docId);
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

  Future<void> _inferEndTimesForImport(String docId) async {
    if (_inferringIds.contains(docId)) return;
    setState(() => _inferringIds.add(docId));
    try {
      final impRef =
          FirebaseFirestore.instance.collection('calendar_imports').doc(docId);
      final impDoc = await impRef.get();
      if (!impDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kunde inte fylla i sluttider.'),
              backgroundColor: Colors.red,
            ),
          );
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

      final candidates = <Map<String, dynamic>>[];
      for (final d in eventsSnap.docs) {
        final m = d.data();
        if (m['source'] != 'calendar') continue;
        final byId = m['calendarImportId'] == docId;
        final legacy = m['calendarImportId'] == null &&
            m['calendarName'] == calendarName;
        if (!byId && !legacy) continue;

        final time = (m['time'] as String? ?? '').trim();
        if (time.isEmpty) continue;

        candidates.add({
          'date': m['date'] as String? ?? '',
          'time': time,
          'endTime': m['endTime'] as String?,
          'ref': d.reference,
        });
      }

      final initialEndTimes = <dynamic, String?>{
        for (final c in candidates) c['ref']: c['endTime'] as String?,
      };
      final filledCount = inferBlockEndTimes(candidates);

      if (filledCount > 0) {
        var batch = FirebaseFirestore.instance.batch();
        var ops = 0;
        for (final c in candidates) {
          final ref = c['ref'] as DocumentReference;
          final prevEnd = initialEndTimes[ref];
          final newEnd = c['endTime'] as String?;
          if (newEnd != null && newEnd.isNotEmpty && newEnd != prevEnd) {
            batch.update(ref, {'endTime': newEnd});
            ops++;
            if (ops >= 400) {
              await batch.commit();
              batch = FirebaseFirestore.instance.batch();
              ops = 0;
            }
          }
        }
        if (ops > 0) {
          await batch.commit();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              filledCount > 0
                  ? 'Fyllde i sluttider för $filledCount aktiviteter. ✅'
                  : 'Alla aktiviteter hade redan sluttid.',
            ),
            backgroundColor: filledCount > 0
                ? const Color(0xFF6BAE75)
                : Colors.grey.shade700,
          ),
        );
      }
    } catch (e, stack) {
      developer.log('Kunde inte fylla i sluttider',
          error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kunde inte fylla i sluttider.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _inferringIds.remove(docId));
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
      final borttagna = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final d in eventsSnap.docs) {
        final m = d.data();
        if (m['source'] != 'calendar') continue;
        batch.delete(d.reference);
        borttagna.add(d);
        deletedEvents++;
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      await avbokaPaminnelser(borttagna);

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

  /// Max storlek per fil — samma gräns som `importIcsText` på servern.
  static const int _maxIcsBytes = 5 * 1024 * 1024;

  /// Importerar valda .ics-filer en i taget via callable `importIcsText`,
  /// samma väg som Android — en enda parser, på servern. Varje fil blir en
  /// egen import, så en felaktig vecka går att ta bort för sig. Filerna körs
  /// i följd: en misslyckad fil ska inte kunna dra med sig de andra.
  Future<List<IcsFilResultat>> _importeraIcsFiler(
    List<PlatformFile> filer, {
    required String prefix,
    required String? member,
    required String kind,
  }) async {
    final memberUid =
        member == null ? null : uidForName(_familyMembers, member);
    final callable = FirebaseFunctions.instance.httpsCallable('importIcsText');
    final resultat = <IcsFilResultat>[];

    for (final fil in filer) {
      final bytes = fil.bytes;
      if (bytes == null) {
        resultat.add(IcsFilResultat.misslyckad(
            filnamn: fil.name, fel: 'kunde inte läsas'));
        continue;
      }
      if (bytes.length > _maxIcsBytes) {
        resultat.add(
            IcsFilResultat.misslyckad(filnamn: fil.name, fel: 'för stor'));
        continue;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final namn =
          icsImportNamn(icsText: text, prefix: prefix, filnamn: fil.name);
      try {
        final svar = await callable.call<Map<String, dynamic>>({
          'icsText': text,
          'calendarName': namn,
          'kind': kind == 'activity' ? 'activity' : 'schedule',
          if (memberUid != null && memberUid.isNotEmpty) 'memberUid': memberUid,
        });
        final antal = (svar.data['count'] as num?)?.toInt() ?? 0;
        resultat.add(
            IcsFilResultat.lyckad(filnamn: fil.name, namn: namn, antal: antal));
      } on FirebaseFunctionsException catch (e) {
        developer.log('importIcsText misslyckades för ${fil.name}', error: e);
        resultat.add(IcsFilResultat.misslyckad(
            filnamn: fil.name, fel: e.message ?? 'fel'));
      } catch (e, stack) {
        developer.log('importIcsText misslyckades för ${fil.name}',
            error: e, stackTrace: stack);
        resultat.add(IcsFilResultat.misslyckad(filnamn: fil.name, fel: '$e'));
      }
    }

    final familyId = _currentUser?.familyId;
    if (resultat.any((r) => (r.antal ?? 0) > 0) &&
        familyId != null &&
        familyId.isNotEmpty) {
      unawaited(NotificationService.rescheduleAllForFamily(familyId));
    }
    return resultat;
  }

  void _visaFilsammanfattning(List<IcsFilResultat> resultat) {
    if (!mounted) return;
    final allaLyckades = resultat.every((r) => r.lyckades);
    final nagot = resultat.any((r) => (r.antal ?? 0) > 0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(icsImportSammanfattning(resultat)),
      backgroundColor:
          (allaLyckades && nagot) ? const Color(0xFF6BAE75) : Colors.orange,
      duration: Duration(seconds: resultat.length > 1 ? 8 : 4),
    ));
  }
}

class _ImportCard extends StatelessWidget {
  final Color dayColor;
  final List<Map<String, dynamic>> calendarImports;
  final Set<String> inferringImportIds;
  final VoidCallback onAddTap;
  final VoidCallback? onPurgeTap;
  final void Function(String id) onDeleteImport;
  final void Function(String id) onInferEndTimes;
  final void Function(String id, bool value) onToggleAutoSync;
  final void Function(String id) onSyncNow;

  const _ImportCard({
    required this.dayColor,
    required this.calendarImports,
    required this.inferringImportIds,
    required this.onAddTap,
    required this.onPurgeTap,
    required this.onDeleteImport,
    required this.onInferEndTimes,
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
    if (imp['importKind'] == 'photo') return false;
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
            const SizedBox(height: 16),
            // En lista för allt — skannade scheman hamnar här tillsammans med
            // prenumerationer och filer, och tas bort härifrån.
            Text(
              'IMPORTERADE SCHEMAN OCH KALENDRAR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
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
                        Icon(
                          imp['importKind'] == 'photo'
                              ? Icons.camera_alt_rounded
                              : Icons.check_circle_rounded,
                          color: dayColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            imp['name'] as String? ?? 'Kalender',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          imp['importKind'] == 'photo'
                              ? 'Foto'
                              : ((imp['planningImportKind'] as String? ??
                                          imp['targetType'] as String? ??
                                          'schedule') ==
                                      'activity'
                                  ? 'Aktivitet'
                                  : 'Schema'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: dayColor,
                          ),
                        ),
                        if (imp['importKind'] == 'photo')
                          inferringImportIds.contains(imp['id'])
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(Icons.timelapse_rounded,
                                      size: 22, color: Colors.grey.shade600),
                                  tooltip: 'Fyll i sluttider',
                                  onPressed: () {
                                    final id = imp['id'];
                                    if (id is String) onInferEndTimes(id);
                                  },
                                ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 22, color: Colors.grey.shade600),
                          tooltip: 'Ta bort import och händelser',
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
                        '${imp['eventCount'] ?? 0} händelser · '
                        '${importKallEtikett(imp)}',
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
