import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../data/piktogram.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/notification_service.dart';

class AddChoreSheet extends StatefulWidget {
  final List<UserModel> familyMembers;
  final String? familyId;
  final QueryDocumentSnapshot? choreToEdit;
  /// Förifyll vald dag i veckoplaneringen (ny syssla).
  final DateTime? preselectedDay;
  /// Hoppa över piktogramsteg — standard ✅ (snabbare vardagsplanering).
  final bool startOnForm;

  const AddChoreSheet({
    super.key,
    required this.familyMembers,
    this.familyId,
    this.choreToEdit,
    this.preselectedDay,
    this.startOnForm = false,
  });

  @override
  State<AddChoreSheet> createState() => _AddChoreSheetState();
}

class _AddChoreSheetState extends State<AddChoreSheet> {
  String _pik = '✅';
  String _cat = 'Alla';
  String _q = '';
  int _step = 0;
  final _title = TextEditingController();
  String? _assignTo;
  int _points = 10;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  /// null = engång; annars daily/weekly/biweekly/monthly.
  String? _recType;
  final Set<String> _rotationUids = {};
  final List<String> _substeps = [];
  final _subCtrl = TextEditingController();
  bool _saving = false;
  bool _saveAsTemplate = false;

  static String _dueDateKey(DateTime d) => dateKey(d);

  String _effectiveFamilyId() {
    var id = widget.familyId?.trim() ?? '';
    if (id.isEmpty) {
      final fp = context.read<FamilyProvider>();
      id = fp.currentUser?.familyId?.trim() ?? '';
    }
    return id;
  }

  @override
  void initState() {
    super.initState();
    if (widget.choreToEdit != null) {
      final d = widget.choreToEdit!.data() as Map<String, dynamic>;
      _title.text = d['chore'] as String? ?? d['title'] as String? ?? '';
      _pik = d['piktogram'] as String? ?? '✅';
      _assignTo = d['who'] as String?;
      if (_assignTo != null && _assignTo!.isEmpty) _assignTo = null;
      _points = (d['points'] as int?) ?? 10;
      final subs = (d['substeps'] as List? ?? []).cast<Map<String, dynamic>>();
      _substeps.addAll(subs.map((s) => s['title'] as String? ?? ''));
      final raw = d['dueDate'];
      if (raw is String && raw.isNotEmpty) {
        try {
          final p = raw.split('-');
          if (p.length >= 3) {
            _dueDate = DateTime(
              int.parse(p[0]),
              int.parse(p[1]),
              int.parse(p[2]),
            );
          }
        } catch (e, stack) {
          developer.log('chores: ogiltigt dueDate "$raw"',
              error: e, stackTrace: stack);
        }
      }
      final timeStr = d['dueTime'] as String? ?? '';
      if (timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          _dueTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 18,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
      if (d['isRecurring'] == true) {
        final rec = d['recurrence'] as Map<String, dynamic>?;
        _recType = rec?['type'] as String? ?? 'weekly';
        final start = rec?['startDate'] as String? ?? d['dueDate'] as String?;
        if (start is String && start.isNotEmpty && _dueDate == null) {
          _dueDate = parseDate(start);
        }
        for (final u in (d['rotationUids'] as List? ?? []).whereType<String>()) {
          if (u.isNotEmpty) _rotationUids.add(u);
        }
      }
      _step = 1;
    } else {
      if (widget.startOnForm) _step = 1;
      if (widget.preselectedDay != null) {
        final p = widget.preselectedDay!;
        _dueDate = DateTime(p.year, p.month, p.day);
      }
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final firstDay = DateTime(now.year, 1, 1);
      final weekNum = ((now.difference(firstDay).inDays + firstDay.weekday - 1) / 7).ceil();
      final weekOf = '${now.year}-W$weekNum';
      
      String whoColor = '';
      String whoUid = uidForName(widget.familyMembers, _assignTo ?? '');
      String whoName = _assignTo ?? '';
      if (_rotationUids.isNotEmpty) {
        whoUid = _rotationUids.first;
        for (final m in widget.familyMembers) {
          if (m.uid == whoUid) {
            whoName = m.name;
            whoColor = m.color;
            break;
          }
        }
      } else if (_assignTo != null) {
        final member = widget.familyMembers.where((m) => m.name == _assignTo).isNotEmpty
            ? widget.familyMembers.firstWhere((m) => m.name == _assignTo)
            : null;
        if (member != null) whoColor = member.color;
      }

      final startDay = _dueDate ?? DateTime(now.year, now.month, now.day);
      final timeStr = _dueTime == null
          ? null
          : '${_dueTime!.hour.toString().padLeft(2, '0')}:'
              '${_dueTime!.minute.toString().padLeft(2, '0')}';

      Map<String, dynamic> recurrenceFields() {
        if (_recType == null) {
          return {
            'isRecurring': false,
            'doneDates': FieldValue.delete(),
            'rotationUids': FieldValue.delete(),
            'recurrence': FieldValue.delete(),
          };
        }
        return {
          'isRecurring': true,
          'isDone': false,
          'doneDates': <String>[],
          'dueDate': _dueDateKey(startDay),
          'rotationUids': _rotationUids.toList(),
          'recurrence': {
            'type': _recType,
            'startDate': _dueDateKey(startDay),
            'endDate': null,
            'exceptions': <String>[],
          },
          'dueTime': ?timeStr,
        };
      }

      if (widget.choreToEdit != null) {
        final upd = <String, dynamic>{
          'chore': _title.text.trim(),
          'piktogram': _pik,
          'who': whoName,
          'whoUid': whoUid,
          'whoColor': whoColor,
          'points': _points,
          'substeps':
              _substeps.map((s) => {'title': s, 'isDone': false}).toList(),
          ...recurrenceFields(),
        };
        if (_recType == null) {
          if (_dueDate != null) {
            upd['dueDate'] = _dueDateKey(_dueDate!);
            if (timeStr != null) {
              upd['dueTime'] = timeStr;
            } else {
              upd['dueTime'] = FieldValue.delete();
            }
          } else {
            upd['dueDate'] = FieldValue.delete();
            upd['dueTime'] = FieldValue.delete();
          }
        }
        final docId = widget.choreToEdit!.id;
        final old = widget.choreToEdit!.data() as Map<String, dynamic>;
        await NotificationService.cancelChoreReminders(docId, old);
        await widget.choreToEdit!.reference.update(upd);
        final merged = {...old, ...upd}
          ..removeWhere((_, v) => v is FieldValue);
        await NotificationService.scheduleChoreReminders(
          docId: docId,
          data: merged,
        );
      } else {
        final fid = _effectiveFamilyId();
        if (fid.isEmpty) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Ingen familj hittades — kan inte spara. Ladda om eller vänta tills kontot är kopplat.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        final data = <String, dynamic>{
          'chore': _title.text.trim(),
          'piktogram': _pik,
          'who': whoName,
          'whoUid': whoUid,
          'whoColor': whoColor,
          'isDone': false,
          'points': _points,
          'familyId': fid,
          'weekOf': weekOf,
          'substeps': _substeps.map((s) => {'title': s, 'isDone': false}).toList(),
          if (FirebaseAuth.instance.currentUser != null)
            'createdByUid': FirebaseAuth.instance.currentUser!.uid,
        };
        if (_recType != null) {
          data.addAll({
            'isRecurring': true,
            'doneDates': <String>[],
            'dueDate': _dueDateKey(startDay),
            'rotationUids': _rotationUids.toList(),
            'recurrence': {
              'type': _recType,
              'startDate': _dueDateKey(startDay),
              'endDate': null,
              'exceptions': <String>[],
            },
            'dueTime': ?timeStr,
          });
        } else {
          data['isRecurring'] = false;
          if (_dueDate != null) {
            data['dueDate'] = _dueDateKey(_dueDate!);
            if (timeStr != null) data['dueTime'] = timeStr;
          }
        }
        String savedDocId;
        if (_saveAsTemplate) {
          final batch = FirebaseFirestore.instance.batch();
          final choreRef = FirebaseFirestore.instance.collection('chores').doc();
          savedDocId = choreRef.id;
          batch.set(choreRef, data);
          final tplRef =
              FirebaseFirestore.instance.collection('chore_templates').doc();
          batch.set(tplRef, {
            'familyId': fid,
            'title': _title.text.trim(),
            'piktogram': _pik,
            'points': _points.clamp(1, 999),
            if (whoName.isNotEmpty) 'defaultWho': whoName,
          });
          await batch.commit();
        } else {
          final ref = await FirebaseFirestore.instance.collection('chores').add(data);
          savedDocId = ref.id;
        }
        await NotificationService.scheduleChoreReminders(
          docId: savedDocId,
          data: data,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.choreToEdit != null ? 'Syssla uppdaterad! ✅' : 'Syssla sparad! ✅'),
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.only(top: 12),
          child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(
              _step == 0 ? 'Välj piktogram' : (widget.choreToEdit != null ? 'Redigera syssla' : 'Ny syssla'), 
              style: AppTheme.sectionTitleStyle
            )),
            if (_step == 1) TextButton(onPressed: () => setState(() => _step = 0), child: const Text('← Byt')),
          ])),
        Expanded(child: _step == 0 ? _buildPicker(dayColor) : _buildForm(dayColor)),
      ]),
    );
  }

  Widget _buildPicker(Color dayColor) {
    final items = piktogramLibrary.where((p) =>
      (_cat == 'Alla' || p.category == _cat) &&
      (_q.isEmpty || p.label.toLowerCase().contains(_q.toLowerCase()))).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(hintText: 'Sök...', prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true, fillColor: Colors.grey.shade100, contentPadding: const EdgeInsets.symmetric(vertical: 8)))),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: piktogramCategories.map((c) => GestureDetector(
          onTap: () => setState(() => _cat = c),
          child: Container(margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _cat == c ? dayColor : Colors.white, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cat == c ? dayColor : Colors.grey.shade300)),
            child: Text(c, style: TextStyle(color: _cat == c ? Colors.white : AppTheme.getTextColor(), fontSize: 13)))
        )).toList())),
      const SizedBox(height: 8),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.9),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final p = items[i]; final sel = p.emoji == _pik;
          return GestureDetector(
            onTap: () { setState(() { _pik = p.emoji; if (_title.text.isEmpty) _title.text = p.label; _step = 1; }); },
            child: AnimatedContainer(duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(color: sel ? dayColor.withValues(alpha: 0.15) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12), border: sel ? Border.all(color: dayColor, width: 2) : null),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.emoji, style: const TextStyle(fontSize: 24)),
                Text(p.label, style: const TextStyle(fontSize: 9), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ])));
        })),
    ]);
  }

  Widget _buildForm(Color dayColor) {
    return SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: GestureDetector(onTap: () => setState(() => _step = 0),
        child: Column(children: [Text(_pik, style: const TextStyle(fontSize: 56)), Text('Byt piktogram', style: TextStyle(fontSize: 12, color: dayColor))]))),
      const SizedBox(height: 16),
      TextField(controller: _title, decoration: InputDecoration(labelText: 'Syssla', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 12),
      Text('Dag i planeringen', style: AppTheme.sectionLabelStyle),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _dueDate ?? widget.preselectedDay ?? now,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 2, 12, 31),
            locale: const Locale('sv', 'SE'),
          );
          if (picked != null) setState(() => _dueDate = picked);
        },
        icon: const Icon(Icons.event_rounded, size: 18),
        label: Text(
          _dueDate == null
              ? 'Hela veckan (ingen specifik dag)'
              : DateFormat('EEEE d MMM', 'sv').format(_dueDate!),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      if (_dueDate != null) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: _dueTime ?? const TimeOfDay(hour: 18, minute: 0),
            );
            if (picked != null) setState(() => _dueTime = picked);
          },
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: Text(
            _dueTime == null
                ? 'Välj tid för påminnelse (valfritt)'
                : 'Påminnelse kl ${_dueTime!.format(context)}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (_dueTime != null)
          TextButton(
            onPressed: () => setState(() => _dueTime = null),
            child: const Text('Ta bort tid'),
          ),
      ],
      if (_dueDate != null)
        TextButton(
          onPressed: () => setState(() {
            _dueDate = null;
            _dueTime = null;
          }),
          child: const Text('Ta bort specifik dag'),
        ),
      const SizedBox(height: 12),
      Text('Upprepning', style: AppTheme.sectionLabelStyle),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final e in [
            (null, 'Engång'),
            ('daily', 'Varje dag'),
            ('weekly', 'Varje vecka'),
            ('biweekly', 'Varannan vecka'),
            ('monthly', 'Varje månad'),
          ])
            ChoiceChip(
              label: Text(e.$2, style: const TextStyle(fontSize: 12)),
              selected: _recType == e.$1,
              selectedColor: dayColor.withValues(alpha: 0.2),
              onSelected: (_) => setState(() {
                _recType = e.$1;
                if (_recType == null) _rotationUids.clear();
                if (_recType != null && _dueDate == null) {
                  _dueDate = DateTime.now();
                }
              }),
            ),
        ],
      ),
      if (_recType != null) ...[
        const SizedBox(height: 10),
        Text('Roterar mellan (valfritt)', style: AppTheme.sectionLabelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: widget.familyMembers.map((m) {
            final sel = _rotationUids.contains(m.uid);
            return FilterChip(
              label: Text(m.name.split(' ').first),
              selected: sel,
              onSelected: (v) => setState(() {
                if (v) {
                  _rotationUids.add(m.uid);
                } else {
                  _rotationUids.remove(m.uid);
                }
              }),
            );
          }).toList(),
        ),
      ],
      const SizedBox(height: 12),
      Text('Tilldela', style: AppTheme.sectionLabelStyle),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: widget.familyMembers.map((m) {
        Color mc; try { mc = Color(m.colorValue); } catch (_) { mc = dayColor; }
        return ChoiceChip(label: Text(m.name.split(' ').first), selected: _assignTo == m.name,
            selectedColor: mc.withValues(alpha: 0.2),
            onSelected: (v) => setState(() => _assignTo = v ? m.name : null));
      }).toList()),
      const SizedBox(height: 16),
      Text('Poäng: $_points ⭐', style: AppTheme.sectionLabelStyle),
      Slider(value: _points.toDouble(), min: 5, max: 50, divisions: 9, activeColor: dayColor,
          onChanged: (v) => setState(() => _points = v.round())),
      const SizedBox(height: 12),
      Text('Delsteg', style: AppTheme.sectionLabelStyle),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _subCtrl,
          decoration: InputDecoration(hintText: 'Lägg till delsteg...', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          onSubmitted: (v) { if (v.trim().isNotEmpty) setState(() { _substeps.add(v.trim()); _subCtrl.clear(); }); })),
        const SizedBox(width: 8),
        IconButton(icon: Icon(Icons.add_circle_rounded, color: dayColor, size: 32),
          onPressed: () { if (_subCtrl.text.trim().isNotEmpty) setState(() { _substeps.add(_subCtrl.text.trim()); _subCtrl.clear(); }); }),
      ]),
      ..._substeps.map((s) => ListTile(dense: true, contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.drag_handle), title: Text(s),
        trailing: IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.red),
          onPressed: () => setState(() => _substeps.remove(s))))),
      if (widget.choreToEdit == null) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Spara som mall',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text(
              'Visas som snabbval under Planering när du vill dela ut samma syssla igen'),
          value: _saveAsTemplate,
          activeThumbColor: dayColor,
          onChanged: (v) => setState(() => _saveAsTemplate = v),
        ),
      ],
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(backgroundColor: dayColor, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _saving ? const CircularProgressIndicator(color: Colors.white) :
            Text(widget.choreToEdit != null ? 'Uppdatera syssla' : 'Spara syssla', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
      const SizedBox(height: 40),
    ]));
  }
}

/// Minimal vy: titel + vem, standard ✅, vald dag från kalendern.
class QuickChoreSheet extends StatefulWidget {
  final List<UserModel> familyMembers;
  final String? familyId;
  final DateTime selectedDay;

  const QuickChoreSheet({
    super.key,
    required this.familyMembers,
    this.familyId,
    required this.selectedDay,
  });

  @override
  State<QuickChoreSheet> createState() => _QuickChoreSheetState();
}

class _QuickChoreSheetState extends State<QuickChoreSheet> {
  final _title = TextEditingController();
  String? _assignTo;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final firstDay = DateTime(now.year, 1, 1);
      final weekNum =
          ((now.difference(firstDay).inDays + firstDay.weekday - 1) / 7).ceil();
      final weekOf = '${now.year}-W$weekNum';
      String whoColor = '';
      if (_assignTo != null) {
        for (final m in widget.familyMembers) {
          if (m.name == _assignTo) {
            whoColor = m.color;
            break;
          }
        }
      }
      final d = widget.selectedDay;
      await FirebaseFirestore.instance.collection('chores').add({
        'chore': _title.text.trim(),
        'piktogram': '✅',
        'who': _assignTo ?? '',
        'whoUid': uidForName(widget.familyMembers, _assignTo ?? ''),
        'whoColor': whoColor,
        'isDone': false,
        'points': 10,
        'isRecurring': false,
        'familyId': widget.familyId ?? '',
        'weekOf': weekOf,
        'dueDate': dateKey(d),
        'substeps': <Map<String, dynamic>>[],
        if (FirebaseAuth.instance.currentUser != null)
          'createdByUid': FirebaseAuth.instance.currentUser!.uid,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Syssla tillagd!'),
            backgroundColor: Color(0xFF6BAE75),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final dayLabel =
        DateFormat('EEEE d MMMM', 'sv').format(widget.selectedDay);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Snabb syssla', style: AppTheme.sectionTitleStyle),
          const SizedBox(height: 4),
          Text(
            dayLabel,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Vad ska göras?',
              hintText: 'T.ex. diska, gå ut med hunden',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Text('Tilldela', style: AppTheme.sectionLabelStyle),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: widget.familyMembers.map((m) {
              Color mc;
              try {
                mc = Color(m.colorValue);
              } catch (_) {
                mc = dayColor;
              }
              return ChoiceChip(
                label: Text(m.name.split(' ').first),
                selected: _assignTo == m.name,
                selectedColor: mc.withValues(alpha: 0.2),
                onSelected: (v) =>
                    setState(() => _assignTo = v ? m.name : null),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: dayColor),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Lägg till'),
            ),
          ),
        ],
      ),
    );
  }
}