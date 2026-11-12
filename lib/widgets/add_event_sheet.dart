import '../services/activity_receipts.dart';
import '../utils/quick_add_parser.dart';
import '../utils/calendar_input.dart';
import 'quick_add_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../utils/recurrence_edit.dart';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/piktogram.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../utils/activity_start_time.dart';
import '../utils/date_utils.dart';
import '../utils/layout.dart';
import '../utils/person_match.dart';

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppTheme.getTextColor(),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class AddEventSheet extends StatefulWidget {
  final DateTime selectedDay;
  final List<UserModel> familyMembers;
  final String? familyId;
  final QueryDocumentSnapshot? eventToEdit;

  /// Förifylld titel (från snabbinmatningens fallback).
  final String? initialTitle;
  final QuickAddDraft? initialDraft;

  /// Förifylld tid `HH:mm` (t.ex. från AI-planeraren).
  final String? initialTime;

  /// Förifyllda deltagare via uid (t.ex. från AI-planeraren).
  final List<String>? initialPersonUids;
  const AddEventSheet({
    super.key,
    required this.selectedDay,
    required this.familyMembers,
    this.familyId,
    this.eventToEdit,
    this.initialTitle,
    this.initialDraft,
    this.initialTime,
    this.initialPersonUids,
  });
  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  int _step = 1;
  late DateTime _date;
  bool _showDetails = false;
  bool _more = false;
  String _draftMessage = '';
  String? _titleError;
  String? _timeMode = 'undecided';
  bool _timeModeChanged = false;
  String _pik = '📅';
  String _cat = 'Alla';
  String _q = '';
  final _title = TextEditingController();
  final _quickCtrl = TextEditingController();
  // Starttid eller "ingen tid" (activity_start_time.dart). En tidlös aktivitet
  // förblir tidlös tills någon själv väljer ett klockslag.
  ActivityStartTime _start = const ActivityStartTime(
    untimed: true,
    start: TimeOfDay(hour: 9, minute: 0),
  );
  TimeOfDay? _end;
  final List<String> _persons = [];
  final List<String> _checklist = [];
  final _clCtrl = TextEditingController();

  bool _saving = false;
  bool _saveAsTemplate = false;
  List<QueryDocumentSnapshot> _templates = [];

  // Upprepning (ROADMAP Etapp 4)
  bool _recurrenceChanged = false;
  String _recurrenceType = 'none'; // none | weekly | biweekly | monthly
  DateTime? _recurrenceEnd;
  List<String> _recurrenceExceptions = [];
  String? _recurrenceStartDate; // bevaras vid redigering

  @override
  void initState() {
    super.initState();
    _date = widget.selectedDay;
    _showDetails =
        widget.eventToEdit != null ||
        (widget.initialTitle?.isNotEmpty ?? false) ||
        widget.initialDraft != null;
    _loadTemplates();

    if (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) {
      _title.text = widget.initialTitle!;
    }

    final timePrefill = widget.initialTime;
    if (timePrefill != null && timePrefill.isNotEmpty) {
      final parts = timePrefill.split(':');
      if (parts.length >= 2) {
        _start = ActivityStartTime.timed(
          TimeOfDay(
            hour: int.tryParse(parts[0]) ?? _start.start.hour,
            minute: int.tryParse(parts[1]) ?? _start.start.minute,
          ),
        );
      }
    }

    final uidPrefill = widget.initialPersonUids;
    if (uidPrefill != null && uidPrefill.isNotEmpty) {
      for (final uid in uidPrefill) {
        for (final m in widget.familyMembers) {
          if (m.uid == uid && !_persons.contains(m.name)) {
            _persons.add(m.name);
          }
        }
      }
    }

    // AI / snabb-fallback: hoppa till detaljsteget när titel finns.
    if (widget.eventToEdit == null &&
        widget.initialTitle != null &&
        widget.initialTitle!.isNotEmpty) {
      _step = 1;
    }

    if (widget.eventToEdit != null) {
      final d = widget.eventToEdit!.data() as Map<String, dynamic>;
      _pik = d['piktogram'] as String? ?? '📅';
      _title.text = d['title'] as String? ?? '';

      final rec = d['recurrence'] as Map<String, dynamic>?;
      if (rec != null) {
        _recurrenceType = rec['type'] as String? ?? 'none';
        _recurrenceStartDate = rec['startDate'] as String?;
        _recurrenceEnd = parseDate(rec['endDate']);
        _recurrenceExceptions = (rec['exceptions'] as List? ?? [])
            .cast<String>()
            .toList();
      }

      _timeMode = d["timeMode"] as String?;
      _start = ActivityStartTime.fromDoc(d, fallback: _start.start);
      final endStr = d['endTime'] as String? ?? '';
      if (endStr.isNotEmpty) {
        final parts = endStr.split(':');
        if (parts.length >= 2) {
          _end = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }

      final loadedPersons = (d['persons'] as List? ?? []).cast<String>();
      _persons.addAll(loadedPersons);

      final loadedChecklist = (d['checklist'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      _checklist.addAll(loadedChecklist.map((e) => e['item'] as String? ?? ''));

      _step = 1;
    }
    if (widget.initialDraft != null) {
      _quickCtrl.text = widget.initialDraft!.rawText;
      _applyQuickDraft(widget.initialDraft!);
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('activity_templates')
          .where(
            'familyId',
            whereIn: [
              if (widget.familyId?.isNotEmpty == true) widget.familyId!,
              '',
            ],
          )
          .get();
      if (mounted) {
        setState(() {
          _templates = snap.docs.where((doc) {
            final d = doc.data();
            final fid = d['familyId'] as String? ?? '';
            return fid.isEmpty || fid == widget.familyId;
          }).toList();
        });
      }
    } catch (e, stack) {
      developer.log(
        'planner _loadTemplates misslyckades',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void _applyQuickDraft(QuickAddDraft draft) {
    setState(() {
      final patch = CalendarInputPatch.fromDraft(draft);
      _title.text = patch.title;
      if (patch.date != null) _date = patch.date!;
      if (patch.time != null) _start = _start.picked(patch.time!);
      if (patch.personNames != null) {
        _persons
          ..clear()
          ..addAll(patch.personNames!);
      }
      if (patch.recurrence != null) {
        _recurrenceType = patch.recurrence!;
        _recurrenceChanged = true;
      }
      if (patch.pictogram != null) _pik = patch.pictogram!;
      _showDetails = true;
      _draftMessage =
          'Kontrollera datum, tid och person. Det som inte nämndes är oförändrat.';
    });
  }

  @override
  void dispose() {
    _quickCtrl.dispose();
    _title.dispose();
    _clCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate(Map<String, dynamic> data) {
    setState(() {
      _pik = data['piktogram'] ?? '📅';
      _title.text = data['title'] ?? '';
      _checklist.clear();
      _checklist.addAll(
        (data['checklist'] as List<dynamic>? ?? []).map((e) => e.toString()),
      );
      _step = 1;
      _showDetails = true;
    });
  }

  List<PiktogramItem> get _filtered => piktogramLibrary
      .where(
        (p) =>
            (_cat == 'Alla' || p.category == _cat) &&
            (_q.isEmpty || p.label.toLowerCase().contains(_q.toLowerCase())),
      )
      .toList();

  /// Veckodagsnamn för upprepningens startdag (befintlig start vid redigering).
  String _recurrenceDayName() {
    final start = parseDate(_recurrenceStartDate) ?? _date;
    const days = [
      '',
      'måndag',
      'tisdag',
      'onsdag',
      'torsdag',
      'fredag',
      'lördag',
      'söndag',
    ];
    return days[start.weekday];
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Skriv vad aktiviteten ska heta.');
      return;
    }
    final original = widget.eventToEdit?.data() as Map?;
    final startText = _start.untimed
        ? ''
        : '${_start.start.hour.toString().padLeft(2, '0')}:${_start.start.minute.toString().padLeft(2, '0')}';
    final endText = _end == null
        ? ''
        : '${_end!.hour.toString().padLeft(2, '0')}:${_end!.minute.toString().padLeft(2, '0')}';
    final unchangedTime =
        original != null &&
        (original['time'] ?? '') == startText &&
        (original['endTime'] ?? '') == endText;
    if (!unchangedTime &&
        !_start.untimed &&
        _end != null &&
        _end!.hour * 60 + _end!.minute <=
            _start.start.hour * 60 + _start.start.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sluttiden måste vara senare samma dag. Flerdagarsaktiviteter stöds inte i formuläret ännu.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final d = _date;
      final titleStr = _title.text.trim();

      final data = <String, dynamic>{
        'title': titleStr,
        'piktogram': _pik,
        'type': 'activity',
        'date': dateKey(d),
        'persons': _persons,
        'personUids': uidsForNames(widget.familyMembers, _persons),
        'checklist': _checklist.map((i) {
          bool isDone = false;
          if (widget.eventToEdit != null) {
            final oldD = widget.eventToEdit!.data() as Map<String, dynamic>;
            final oldChecklist = (oldD['checklist'] as List? ?? [])
                .whereType<Map>();
            final existing = oldChecklist.where((old) => old['item'] == i);
            if (existing.isNotEmpty) {
              isDone = existing.first['isDone'] == true;
            }
          }
          return {'item': i, 'isDone': isDone};
        }).toList(),
        if (widget.eventToEdit == null) 'source': 'manual',
        'createdBy': user?.uid,
        'isPending': false,
        'familyId': widget.familyId ?? '',
      };
      if (widget.eventToEdit == null && user != null) {
        data['createdByUid'] = user.uid;
      }

      // time, endTime och timeMode: utan tid sparas time "" och ingen sluttid;
      // med klockslag tas timeMode bort (activity_start_time.dart).
      final tid = activityTimeFields(
        start: _start,
        end: _end,
        editing: widget.eventToEdit != null,
      );
      data.addAll(tid.fields);
      if (_start.untimed && (widget.eventToEdit == null || _timeModeChanged)) {
        data['timeMode'] = _timeMode ?? 'undecided';
      }
      for (final f in tid.removals) {
        data[f] = FieldValue.delete();
      }

      data.addAll(
        recurrenceEditFields(
          editing: widget.eventToEdit != null,
          changed: _recurrenceChanged,
          type: _recurrenceType,
          start: _recurrenceStartDate ?? dateKey(d),
          end: _recurrenceEnd == null ? null : dateKey(_recurrenceEnd!),
          exceptions: _recurrenceExceptions,
          deleteValue: FieldValue.delete(),
        ),
      );
      // En titeländring får inte skriva över någon annans packlistekvittens.
      if (widget.eventToEdit != null) {
        final old = widget.eventToEdit!.data() as Map<String, dynamic>;
        final texts = (old['checklist'] as List? ?? [])
            .map(
              (row) =>
                  row is Map ? row['item']?.toString() ?? '' : row.toString(),
            )
            .toList();
        if (texts.length == _checklist.length &&
            List.generate(
              texts.length,
              (i) => texts[i] == _checklist[i],
            ).every((v) => v)) {
          data.remove('checklist');
        }
      }

      final ref =
          widget.eventToEdit?.reference ??
          FirebaseFirestore.instance.collection('planner_events').doc();
      final savedDocId = ref.id;
      final writing = ActivityReceipts.track(
        family: widget.familyId ?? '',
        title: titleStr,
        date: dateKey(_date),
        ids: [savedDocId],
        operation: (writeId) async {
          data['writeId'] = writeId;
          if (widget.eventToEdit != null) {
            await ref.update(data);
          } else {
            await ref.set(data);
          }
          return true;
        },
      );
      final confirmed = await writing.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
      if (!confirmed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sparat lokalt, väntar på serverbekräftelse.'),
            ),
          );
          Navigator.pop(context);
        }
        return;
      }
      if (widget.eventToEdit != null) {
        await NotificationService.cancelActivityReminders(
          savedDocId,
          widget.eventToEdit!.data() as Map<String, dynamic>,
        );
      }

      final reminderData = <String, dynamic>{
        if (widget.eventToEdit != null)
          ...widget.eventToEdit!.data() as Map<String, dynamic>,
        ...data,
      }..removeWhere((key, value) => value is FieldValue);
      await NotificationService.scheduleActivityReminders(
        docId: savedDocId,
        data: reminderData,
      );

      if (_saveAsTemplate) {
        await FirebaseFirestore.instance.collection('activity_templates').add({
          'title': titleStr,
          'piktogram': _pik,
          'checklist': _checklist,
          'familyId': widget.familyId ?? '',
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.eventToEdit != null
                  ? 'Aktivitet uppdaterad! ✅'
                  : 'Aktivitet sparad! ✅',
            ),
            backgroundColor: const Color(0xFF6BAE75),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fel vid sparande: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return wrapBottomSheet(
      context,
      Padding(
        padding: EdgeInsets.only(bottom: kb),
        child: Container(
          height:
              (MediaQuery.sizeOf(context).height -
                  kb -
                  MediaQuery.paddingOf(context).top) *
              (_showDetails || _step == 0 ? 0.92 : 0.5),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _step == 0
                            ? 'Välj piktogram / Mall'
                            : (widget.eventToEdit != null
                                  ? 'Redigera aktivitet'
                                  : 'Vad vill du lägga till?'),
                        style: AppTheme.sectionTitleStyle,
                      ),
                    ),
                    if (_step == 0)
                      TextButton(
                        onPressed: () => setState(() => _step = 1),
                        child: const Text('Till utkastet'),
                      ),
                  ],
                ),
              ),
              Expanded(child: _step == 0 ? _picker(dayColor) : _form(dayColor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _picker(Color dayColor) {
    final items = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_templates.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Hämta från mall',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _templates.length,
              itemBuilder: (ctx, i) {
                final d = _templates[i].data() as Map<String, dynamic>;
                return GestureDetector(
                  onTap: () => _applyTemplate(d),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: dayColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: dayColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          d['piktogram'] ?? '📋',
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          d['title'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Divider(),
          ),
        ],

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Sök piktogram...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: piktogramCategories
                .map(
                  (c) => _Pill(
                    label: c,
                    selected: _cat == c,
                    color: dayColor,
                    onTap: () => setState(() => _cat = c),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.9,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final p = items[i];
              final sel = p.emoji == _pik;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _pik = p.emoji;
                    if (_title.text.isEmpty) _title.text = p.label;
                    _step = 1;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: sel
                        ? dayColor.withValues(alpha: 0.15)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: sel ? Border.all(color: dayColor, width: 2) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(p.emoji, style: const TextStyle(fontSize: 24)),
                      Text(
                        p.label,
                        style: const TextStyle(fontSize: 9),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _form(Color dayColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((widget.eventToEdit?.data() as Map?)?['source'] == 'calendar')
            const Text(
              'Importerad aktivitet. Ändra tid och titel i källkalendern för bestående ändringar; lokala ändringar kan ersättas vid nästa import.',
            ),
          if (widget.eventToEdit == null) ...[
            const Text(
              'Skriv eller säg vad du vill lägga till. Kontrollera utkastet innan du sparar.',
            ),
            QuickAddBar(
              familyMembers: widget.familyMembers,
              familyId: widget.familyId ?? '',
              onActivityDraft: _applyQuickDraft,
              controller: _quickCtrl,
              onFallbackToForm: (raw) => setState(() {
                _title.text = raw;
                _showDetails = true;
                _draftMessage = 'Fyll i det som saknas nedan.';
              }),
            ),
            if (kIsWeb)
              const Text(
                'Vill du tala? Använd mikrofonen på telefonens tangentbord för diktering.',
              ),
            if (_draftMessage.isNotEmpty) Text(_draftMessage),
            if (!_showDetails)
              TextButton(
                onPressed: () => setState(() => _showDetails = true),
                child: const Text('Fyll i själv'),
              ),
          ],
          if (_showDetails) ...[
            TextField(
              controller: _title,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
              decoration: InputDecoration(
                labelText: 'Aktivitetsnamn',
                errorText: _titleError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('När', style: AppTheme.sectionLabelStyle),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(
                DateFormat('EEEE d MMMM yyyy', 'sv_SE').format(_date),
              ),
              onPressed:
                  widget.eventToEdit != null && _recurrenceStartDate != null
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Klockslag'),
                  selected: !_start.untimed,
                  onSelected: (_) async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _start.start,
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        _start = _start.picked(picked);
                        _timeModeChanged = true;
                      });
                    }
                  },
                ),
                for (final mode in const {
                  'allDay': 'Heldag',
                  'undecided': 'Tid inte bestämd',
                }.entries)
                  ChoiceChip(
                    label: Text(mode.value),
                    selected:
                        _start.untimed &&
                        (_timeMode ?? 'undecided') == mode.key,
                    onSelected: (_) => setState(() {
                      _timeMode = mode.key;
                      _timeModeChanged = true;
                      _start = ActivityStartTime(
                        untimed: true,
                        start: _start.start,
                      );
                    }),
                  ),
              ],
            ),
            if (!_start.untimed) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(_start.label((t) => t.format(context))),
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _start.start,
                  );
                  if (t != null) setState(() => _start = _start.picked(t));
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  _start.untimed
                      ? 'Sluttid (välj starttid först)'
                      : _end == null
                      ? 'Sluttid (valfritt)'
                      : 'Slut: ${_end!.format(context)}',
                ),
                // Utan starttid sparas ingen sluttid, så den går inte att välja.
                onPressed: _start.untimed
                    ? null
                    : () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime:
                              _end ??
                              TimeOfDay(
                                hour: (_start.start.hour + 1) % 24,
                                minute: _start.start.minute,
                              ),
                        );
                        if (t != null) setState(() => _end = t);
                      },
              ),
              if (_end != null && !_start.untimed)
                TextButton(
                  onPressed: () => setState(() => _end = null),
                  child: const Text('Ta bort sluttid'),
                ),
              const SizedBox(height: 16),
            ],
            Text('Vem gäller det?', style: AppTheme.sectionLabelStyle),
            if (_persons.isEmpty)
              const Text(
                'Ingen person vald: aktiviteten gäller hela familjen. Välj nedan om den gäller någon särskild.',
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: widget.familyMembers.map((m) {
                final sel = _persons.contains(m.name);
                Color mc;
                try {
                  mc = Color(m.colorValue);
                } catch (_) {
                  mc = dayColor;
                }
                return FilterChip(
                  label: Text(m.name.split(' ').first),
                  selected: sel,
                  selectedColor: mc.withValues(alpha: 0.2),
                  checkmarkColor: mc,
                  onSelected: (v) => setState(
                    () => v ? _persons.add(m.name) : _persons.remove(m.name),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: Icon(_more ? Icons.expand_less : Icons.expand_more),
              label: Text(
                'Fler val · ${_recurrenceType == 'none' ? 'ingen upprepning' : 'upprepning vald'} · ${_checklist.length} i packlistan',
              ),
              onPressed: () => setState(() => _more = !_more),
            ),
            if (_more) ...[
              TextButton(
                onPressed: () => setState(() => _step = 0),
                child: Text('$_pik Byt symbol eller välj mall'),
              ),
              Text('UPPREPNING', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _recurrenceType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  if (!supportedRecurrence(_recurrenceType))
                    DropdownMenuItem(
                      value: _recurrenceType,
                      child: const Text('Anpassad upprepning (behålls)'),
                    ),
                  const DropdownMenuItem(
                    value: 'none',
                    child: Text('Engångshändelse'),
                  ),
                  DropdownMenuItem(
                    value: 'weekly',
                    child: Text('Varje ${_recurrenceDayName()}'),
                  ),
                  DropdownMenuItem(
                    value: 'biweekly',
                    child: Text('Varannan ${_recurrenceDayName()}'),
                  ),
                  const DropdownMenuItem(
                    value: 'monthly',
                    child: Text('Varje månad (samma datum)'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _recurrenceType = v ?? 'none';
                  _recurrenceChanged = true;
                }),
              ),
              if (_recurrenceType != 'none' &&
                  supportedRecurrence(_recurrenceType)) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_busy_rounded),
                  label: Text(
                    _recurrenceEnd == null
                        ? 'Slutdatum: tills vidare'
                        : 'Slut: ${dateKey(_recurrenceEnd!)}',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _recurrenceEnd ?? _date.add(const Duration(days: 90)),
                      firstDate: _date,
                      lastDate: _date.add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setState(() {
                        _recurrenceEnd = picked;
                        _recurrenceChanged = true;
                      });
                    }
                  },
                ),
                if (_recurrenceEnd != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _recurrenceEnd = null;
                      _recurrenceChanged = true;
                    }),
                    child: const Text('Upprepa tills vidare'),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Packlista / Förberedelser',
                style: AppTheme.sectionLabelStyle,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _clCtrl,
                      decoration: InputDecoration(
                        hintText: 'Lägg till...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          setState(() {
                            _checklist.add(v.trim());
                            _clCtrl.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_rounded,
                      color: dayColor,
                      size: 32,
                    ),
                    onPressed: () {
                      if (_clCtrl.text.trim().isNotEmpty) {
                        setState(() {
                          _checklist.add(_clCtrl.text.trim());
                          _clCtrl.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
              ..._checklist.map(
                (item) => ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(item),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    onPressed: () => setState(() => _checklist.remove(item)),
                  ),
                ),
              ),

              if (widget.eventToEdit == null) ...[
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Spara som mall',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Sparar namn, emoji och packlista för framtiden.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _saveAsTemplate,
                    activeThumbColor: dayColor,
                    onChanged: (val) => setState(() => _saveAsTemplate = val),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: dayColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.eventToEdit != null
                            ? 'Uppdatera aktivitet'
                            : 'Spara aktivitet',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }
}
