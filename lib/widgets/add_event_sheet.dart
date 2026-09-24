import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../app_theme.dart';
import '../data/piktogram.dart';
import '../models/user_model.dart';
import '../navigation/app_navigation.dart';
import '../services/notification_service.dart';
import '../utils/aktivitet_formular.dart';
import '../utils/aktivitet_payload.dart';
import '../utils/checklist_updates.dart';
import '../theme/app_colors.dart';
import 'quick_add_bar.dart';
import 'vardag_header.dart';

/// Öppnar det gemensamma aktivitetsformuläret, skyddat mot oavsiktlig
/// stängning (svep/tryck utanför). Från Hem förvalt idag, från Kalendern vald
/// dag, vid redigering aktivitetens datum.
Future<void> showActivityForm(
  BuildContext context, {
  required DateTime day,
  required List<UserModel> familyMembers,
  String? familyId,
  QueryDocumentSnapshot? eventToEdit,
  String? initialTitle,
  String? initialTime,
  List<String>? initialPersonUids,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEventSheet(
        selectedDay: day,
        familyMembers: familyMembers,
        familyId: familyId,
        eventToEdit: eventToEdit,
        initialTitle: initialTitle,
        initialTime: initialTime,
        initialPersonUids: initialPersonUids,
      ),
    );

/// Aktivitetsformuläret (Androids `AktivitetFormular`): **titel, datum, vem,
/// tid**, därefter "Fler val" (upprepning, förberedelse dagen innan,
/// packlista, symbol och mall). Inget obligatoriskt symbolsteg.
///
/// Sparningen följer Androids kontrakt: vid redigering skrivs bara det som
/// ändrats, packlistan slås ihop i en transaktion mot senaste versionen, och
/// undantag, avbockningar, källkopplingar, `lessonPrep` och importerat
/// ursprung bevaras (se `aktivitet_payload.dart`).
class AddEventSheet extends StatefulWidget {
  final DateTime selectedDay;
  final List<UserModel> familyMembers;
  final String? familyId;
  final QueryDocumentSnapshot? eventToEdit;

  /// Förifylld titel (t.ex. från snabbinmatningen).
  final String? initialTitle;

  /// Förifylld tid `HH:mm` (t.ex. från AI-planeraren).
  final String? initialTime;

  /// Förifyllda deltagare via uid.
  final List<String>? initialPersonUids;

  const AddEventSheet({
    super.key,
    required this.selectedDay,
    required this.familyMembers,
    this.familyId,
    this.eventToEdit,
    this.initialTitle,
    this.initialTime,
    this.initialPersonUids,
  });

  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  late AktivitetFormularTillstand _f;
  late final TextEditingController _title;
  final _say = TextEditingController();
  late final TextEditingController _prep;
  final _cl = TextEditingController();
  Map<String, dynamic>? _original;
  bool _flerVal = false;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  List<QueryDocumentSnapshot> _templates = const [];
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;

  bool get _editing => widget.eventToEdit != null;

  @override
  void initState() {
    super.initState();
    final idag = DateTime.now();
    final edit = widget.eventToEdit;
    if (edit != null) {
      _original = Map<String, dynamic>.from(edit.data() as Map);
      _f = AktivitetFormularTillstand.redigera(
        oppning: FormularRedigering(edit.id, _original!),
        idag: idag,
        members: widget.familyMembers,
      );
    } else {
      _f = AktivitetFormularTillstand.ny(
        oppning: FormularFranKalender(widget.selectedDay),
        idag: idag,
        titel: widget.initialTitle ?? '',
        starttid: tolkaKlockslag(widget.initialTime ?? ''),
        deltagarUids: widget.initialPersonUids ?? const [],
      );
    }
    _title = TextEditingController(text: _f.titel);
    _prep = TextEditingController(text: _f.forberedelseText);
    _flerVal = _f.flerValOppetFranStart;
    _loadTemplates();
  }

  @override
  void dispose() {
    if (!kIsWeb) _speech.stop();
    _title.dispose();
    _say.dispose();
    _prep.dispose();
    _cl.dispose();
    super.dispose();
  }

  void _set(AktivitetFormularTillstand next) => setState(() {
        _f = next;
        _dirty = true;
        _error = null;
      });

  Future<void> _loadTemplates() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('activity_templates').get();
      if (!mounted) return;
      setState(() {
        _templates = snap.docs.where((doc) {
          final fid = doc.data()['familyId'] as String? ?? '';
          return fid.isEmpty || fid == widget.familyId;
        }).toList();
      });
    } catch (e, stack) {
      developer.log('Kunde inte läsa aktivitetsmallar', error: e, stackTrace: stack);
    }
  }

  // ─── "Skriv eller säg" ──────────────────────────────────────────────────
  /// Fyller formuläret ur en mening — sparar aldrig. Fält som meningen inte
  /// nämner lämnas orörda. Sysslor, middag och inköp går till sina egna
  /// befintliga bekräftelser.
  Future<void> _interpret() async {
    final text = _say.text.trim();
    if (text.isEmpty) return;
    final t = tolkaMening(text, members: widget.familyMembers);
    if (t is TolkadAnnanTyp) {
      // Syssla, middag eller inköp: formuläret stängs och det befintliga
      // bekräftelseflödet tar över.
      final fid = widget.familyId ?? '';
      final host = AppNavigation.navigatorKey.currentContext;
      Navigator.of(context).pop();
      if (host != null && host.mounted) {
        await showQuickAddConfirm(host, draft: t.utkast, familyId: fid);
      }
      return;
    }
    final next = _f.tillampaTolkning(t);
    _set(next);
    _title.text = next.titel;
    _say.clear();
  }

  Future<void> _toggleListen() async {
    if (kIsWeb) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ok) {
        if (mounted) {
          showVardagSnack(
              context, 'Taligenkänning är inte tillgänglig på den här enheten.');
        }
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(
        listenOptions:
            stt.SpeechListenOptions(partialResults: true, localeId: 'sv_SE'),
        onResult: (r) {
          if (!mounted) return;
          setState(() => _say.text = r.recognizedWords);
          if (r.finalResult && r.recognizedWords.isNotEmpty) {
            setState(() => _listening = false);
            _interpret();
          }
        },
      );
    } catch (e, stack) {
      developer.log('Röstinmatning misslyckades', error: e, stackTrace: stack);
      if (mounted) setState(() => _listening = false);
    }
  }

  // ─── Stängning ──────────────────────────────────────────────────────────
  Future<void> _close() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kasta ändringarna?'),
        content: const Text('Det du fyllt i sparas inte.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Fortsätt fylla i')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB3261E)),
              child: const Text('Kasta')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // ─── Sparning ───────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_saving) return; // dubbeltryck ger aldrig två aktiviteter
    final problem = _f.validera();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final fid = widget.familyId ?? '';
    if (uid == null || fid.isEmpty) {
      setState(() => _error = 'Ingen familj vald.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = byggAktivitetPayload(
      utkast: _f.tillUtkast(widget.familyMembers),
      uid: uid,
      familyId: fid,
      original: _original,
    );
    final coll = FirebaseFirestore.instance.collection('planner_events');
    final editDoc = widget.eventToEdit;
    final datum = _f.datum;
    final titel = _f.titel.trim();
    final original = _original;
    final saveTemplate = !_editing && _f.sparaSomMall;
    final packlista = _f.packlista;
    final piktogram = _f.piktogram;

    final utfall = await AktivitetSparning.instans.spara(
      titel: titel,
      kandId: editDoc?.id,
      skriv: (mottagId) => editDoc != null
          ? skrivRedigering(coll.doc(editDoc.id), payload,
              originalChecklist: checklistRowsOf(original?['checklist']))
          : skrivNyAktivitet(coll, payload, mottagId: mottagId),
      narIdArKant: (id) async {
        if (original != null) {
          await NotificationService.cancelActivityReminders(id, original);
        }
        await NotificationService.scheduleActivityReminders(
            docId: id, data: payload.forPaminnelser);
        if (saveTemplate) {
          await FirebaseFirestore.instance.collection('activity_templates').add(
              aktivitetsmall(
                  titel: titel,
                  piktogram: piktogram,
                  packlista: packlista,
                  familyId: fid));
        }
      },
    );
    if (!mounted) return;

    switch (utfall) {
      case SparNekat(:final meddelande):
        setState(() {
          _saving = false;
          _error = meddelande;
        });
        return;
      case SparBekraftat(:final eventId):
        _closeWithConfirmation(datum, eventId, lokalt: false);
      case SparLokalt(:final eventId):
        _closeWithConfirmation(datum, eventId.value, lokalt: true);
    }
  }

  void _closeWithConfirmation(DateTime datum, String? eventId,
      {required bool lokalt}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    // Webben kan inte lova att en köad skrivning överlever att sidan stängs.
    final text = lokalt && kIsWeb
        ? 'Inte bekräftat än — skickas när nätet finns. Stäng inte sidan förrän den syns i kalendern · ${kortDatum(datum, DateTime.now())}'
        : sparBekraftelseText(datum, lokalt: lokalt, idag: DateTime.now());
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 6),
      action: AppNavigation.tabsAvailable
          ? SnackBarAction(
              label: 'Visa',
              onPressed: () =>
                  AppNavigation.showInCalendarGlobal(datum, eventId: eventId),
            )
          : null,
    ));
  }

  // ─── Väljare ────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _f.datum,
      firstDate: DateTime(_f.datum.year - 2),
      lastDate: DateTime(_f.datum.year + 3),
      confirmText: 'OK',
      cancelText: 'Avbryt',
    );
    if (d != null) _set(_f.medDatum(d));
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(
        context: context,
        initialTime: _f.starttid ?? const TimeOfDay(hour: 12, minute: 0));
    if (t != null) _set(_f.medStarttid(t));
  }

  Future<void> _pickEnd() async {
    final s = _f.starttid ?? const TimeOfDay(hour: 12, minute: 0);
    final t = await showTimePicker(
        context: context,
        initialTime:
            _f.sluttid ?? TimeOfDay(hour: (s.hour + 1) % 24, minute: s.minute));
    if (t != null) _set(_f.medSluttid(t));
  }

  Future<void> _pickRecurrenceEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _f.upprepningSlut ?? _f.datum.add(const Duration(days: 90)),
      firstDate: _f.datum,
      lastDate: _f.datum.add(const Duration(days: 365 * 3)),
      confirmText: 'OK',
      cancelText: 'Avbryt',
    );
    if (d != null) _set(_f.medUpprepningSlut(d));
  }

  Future<void> _pickSymbol() async {
    final picked = await showModalBottomSheet<PiktogramItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SymbolPicker(),
    );
    if (picked != null) {
      final next = _f.medPiktogram(picked.emoji, picked.label);
      _set(next);
      _title.text = next.titel;
    }
  }

  // ─── Byggstenar ─────────────────────────────────────────────────────────
  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: AppTheme.sectionLabelStyle
                .copyWith(color: AppTheme.colors().onCardPrimary)),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    final accent = c.accent;
    final idag = DateTime.now();
    final saveLabel = _editing ? 'Spara ändringar' : 'Spara';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SheetFrame(
        title: _editing ? 'Redigera aktivitet' : 'Ny aktivitet',
        onClose: _close,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            // Skriv eller säg
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _say,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _interpret(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Skriv eller säg, t.ex. "fotboll Liam torsdag 17"',
                    prefixIcon: const Icon(Icons.auto_awesome_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (!kIsWeb)
                IconButton(
                  tooltip: _listening ? 'Sluta lyssna' : 'Säg det',
                  icon: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _listening ? const Color(0xFFB3261E) : accent),
                  onPressed: _toggleListen,
                ),
              TextButton(onPressed: _interpret, child: const Text('Fyll i')),
            ]),
            const SizedBox(height: 14),
            // 1. Titel
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) => _set(_f.medTitel(v)),
              decoration: InputDecoration(
                labelText: 'Vad ska hända?',
                prefixIcon: _f.piktogram.isNotEmpty && _f.piktogram != '📅'
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_f.piktogram,
                            style: const TextStyle(fontSize: 20)))
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            // 2. Datum
            _label('DATUM'),
            OutlinedButton.icon(
              onPressed: _f.datumLast ? null : _pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(datumRadText(_f.datum, idag)),
              ),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
            if (_f.datumLast)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(datumLastForklaring,
                    style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
              ),
            // 3. Vem
            _label('VEM'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final m in widget.familyMembers)
                FilterChip(
                  label: Text(m.name.split(' ').first),
                  selected: _f.deltagarUids.contains(m.uid),
                  selectedColor: AppTheme.colorFromHex(m.color).withValues(alpha: 0.2),
                  checkmarkColor: AppTheme.colorFromHex(m.color),
                  onSelected: (_) => _set(_f.vaxlaDeltagare(m.uid)),
                ),
            ]),
            // 4. Tid
            _label('TID'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<Tidslage>(
                segments: [
                  for (final l in Tidslage.values)
                    ButtonSegment(
                        value: l,
                        label: Text(l.valText,
                            style: const TextStyle(fontSize: 13))),
                ],
                selected: {_f.tidslage},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _set(_f.medTidslage(s.first)),
              ),
            ),
            if (_f.tidslage == Tidslage.klockslag) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.access_time_rounded),
                    label: Text(_f.starttid == null
                        ? 'Starttid'
                        : 'Start ${_f.starttid!.format(context)}'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEnd,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(_f.sluttid == null
                        ? 'Sluttid (valfri)'
                        : 'Slut ${_f.sluttid!.format(context)}'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ),
              ]),
              if (_f.sluttid != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _set(_f.medSluttid(null)),
                    child: const Text('Ta bort sluttid'),
                  ),
                ),
            ],
            if (_f.tidslage.forklaring != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_f.tidslage.forklaring!,
                    style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
              ),
            // Fler val
            const SizedBox(height: 16),
            Material(
              color: c.cardSurface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _flerVal = !_flerVal),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fler val',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: c.onCardPrimary)),
                          Text(flerValUnderrad(_f.sammanfattning),
                              style: TextStyle(
                                  fontSize: 12, color: c.onCardSecondary)),
                        ],
                      ),
                    ),
                    Icon(_flerVal
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded),
                  ]),
                ),
              ),
            ),
            if (_flerVal) ..._flerValContent(c, idag),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(saveLabel,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _flerValContent(AppColors c, DateTime idag) {
    final colors = AppTheme.colors();
    return [
      _label('UPPREPNING'),
      DropdownButtonFormField<String>(
        initialValue: _f.upprepning,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          for (final typ in _f.upprepningsAlternativ)
            DropdownMenuItem(
                value: typ, child: Text(upprepningsEtikett(typ, _f.datum))),
        ],
        onChanged: (v) => _set(_f.medUpprepning(v ?? 'none')),
      ),
      if (_f.upprepning != 'none') ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickRecurrenceEnd,
              icon: const Icon(Icons.event_busy_rounded),
              label: Text(upprepningSlutText(_f.upprepningSlut, idag)),
            ),
          ),
          if (_f.upprepningSlut != null)
            TextButton(
              onPressed: () => _set(_f.medUpprepningSlut(null)),
              child: const Text('Tills vidare'),
            ),
        ]),
      ],
      _label('FÖRBEREDELSE DAGEN INNAN'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Påminn om något att förbereda kvällen innan'),
        value: _f.forberedelseAktiv,
        activeThumbColor: colors.accent,
        onChanged: (v) => _set(_f.medForberedelse(aktiv: v)),
      ),
      if (_f.forberedelseAktiv)
        TextField(
          controller: _prep,
          onChanged: (v) => _set(_f.medForberedelse(text: v)),
          decoration: InputDecoration(
            hintText: 'T.ex. packa gympakläder',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      _label('PACKLISTA'),
      for (var i = 0; i < _f.packlista.length; i++)
        Row(children: [
          Icon(
              _f.packlista[i].klar
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: colors.onCardIcon),
          const SizedBox(width: 10),
          Expanded(child: Text(_f.packlista[i].text)),
          IconButton(
            tooltip: 'Ta bort raden',
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFB3261E)),
            onPressed: () => _set(_f.taBortPackrad(i)),
          ),
        ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _cl,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) {
              _set(_f.laggTillPackrad(v));
              _cl.clear();
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Lägg till något att ta med…',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Lägg till',
          icon: Icon(Icons.add_circle_rounded, color: colors.accent, size: 30),
          onPressed: () {
            _set(_f.laggTillPackrad(_cl.text));
            _cl.clear();
          },
        ),
      ]),
      _label('SYMBOL'),
      Row(children: [
        Text(_f.piktogram.isEmpty ? '📅' : _f.piktogram,
            style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: _pickSymbol, child: const Text('Välj symbol')),
      ]),
      if (_templates.isNotEmpty || !_editing) _label('MALL'),
      if (_templates.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final t in _templates)
            ActionChip(
              avatar: Text((t.data() as Map)['piktogram'] as String? ?? '📋'),
              label: Text((t.data() as Map)['title'] as String? ?? ''),
              onPressed: () {
                final next = _f.medMall(Map<String, dynamic>.from(t.data() as Map));
                _set(next);
                _title.text = next.titel;
              },
            ),
        ]),
      if (!_editing)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Spara som mall'),
          subtitle: const Text('Sparar namn, symbol och packlista för framtiden.'),
          value: _f.sparaSomMall,
          activeThumbColor: colors.accent,
          onChanged: (v) => _set(_f.medSparaSomMall(v)),
        ),
    ];
  }
}

class _SymbolPicker extends StatefulWidget {
  const _SymbolPicker();
  @override
  State<_SymbolPicker> createState() => _SymbolPickerState();
}

class _SymbolPickerState extends State<_SymbolPicker> {
  String _cat = 'Alla';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.colors().accent;
    final items = piktogramLibrary
        .where((p) =>
            (_cat == 'Alla' || p.category == _cat) &&
            (_q.isEmpty || p.label.toLowerCase().contains(_q.toLowerCase())))
        .toList();
    return SheetFrame(
      title: 'Välj symbol',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Sök symbol…',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final cat in piktogramCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _cat == cat,
                      selectedColor: accent.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() => _cat = cat),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 76, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: items.length,
              itemBuilder: (_, i) => InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(context, items[i]),
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(items[i].emoji, style: const TextStyle(fontSize: 24)),
                        Text(items[i].label,
                            style: const TextStyle(fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
