import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../app_theme.dart';
import '../data/piktogram.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';
import '../utils/recurrence.dart';
import '../models/user_model.dart';
import '../services/family_service.dart';
import '../services/notification_service.dart';
import '../widgets/activity_detail_sheet.dart';
import '../widgets/planner_event_leading.dart';


class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  UserModel? _currentUser;
  List<UserModel> _familyMembers = [];
  String? _filterPerson;
  String? _filterPersonUid;
  
  // NYTT: Göm kalenderimporter som standard
  bool _showImported = false; 

  Stream<QuerySnapshot>? _eventsStream;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await FamilyService.getCurrentUserModel();
    final members = <UserModel>[];
    if (user?.familyId != null) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('familyId', isEqualTo: user!.familyId)
          .get();
      for (final d in snap.docs) members.add(UserModel.fromMap(d.id, d.data()));
    }
    if (mounted) {
      setState(() { 
        _currentUser = user; 
        _familyMembers = members; 
        
        if (user?.familyId != null && user!.familyId!.isNotEmpty) {
          _eventsStream = FirebaseFirestore.instance
              .collection('planner_events')
              .where('familyId', isEqualTo: user.familyId)
              .snapshots();
        }
      });
    }
  }

  List<QueryDocumentSnapshot> _getEventsForDay(
      List<QueryDocumentSnapshot> all, DateTime day) {
    return all.where((doc) {
      try {
        final d = doc.data() as Map<String, dynamic>;
        
        // Schema-import (skola/job): dölj om togglen är av. Aktivitets-import syns alltid.
        if (!_showImported &&
            d['source'] == 'calendar' &&
            (d['planningImportKind'] as String? ?? 'schedule') == 'schedule') {
          return false;
        }

        if (!eventOccursOnDay(d, day)) return false;
        if (_filterPerson != null) {
          return eventIncludesPerson(d,
              uid: _filterPersonUid ?? '', name: _filterPerson!);
        }
        return true;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  void _showAddSheet({QueryDocumentSnapshot? edit}) {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Laddar familjedata... försök igen'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEventSheet(
        selectedDay: _selectedDay,
        familyMembers: _familyMembers,
        familyId: _currentUser?.familyId ?? '',
        eventToEdit: edit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dayColor = AppTheme.getDayAccentColor();
    final isFocus = _currentUser?.isFocusMode ?? false;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: AppTheme.getBackground(),
      child: Stack(
        children: [
          if (_eventsStream == null)
             _buildParentView([], dayColor)
          else
            StreamBuilder<QuerySnapshot>(
              stream: _eventsStream,
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Fel: ${snap.error}',
                          style: const TextStyle(color: Colors.red)),
                    ),
                  );
                }
                final all = snap.data?.docs ?? [];
                if (isFocus) return _buildFocusView(all);
                return _buildParentView(all, dayColor);
              },
            ),
          Positioned(
            right: 16,
            bottom: bottomPad + 16,
            child: FloatingActionButton.extended(
              onPressed: _showAddSheet,
              backgroundColor: dayColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ny aktivitet',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentView(List<QueryDocumentSnapshot> all, Color dayColor) {
    final selected = _getEventsForDay(all, _selectedDay);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, dayColor)),
          SliverToBoxAdapter(child: _buildCalendar(all, dayColor)),
          SliverToBoxAdapter(child: _buildPersonFilter(dayColor)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                  () {
                    try {
                      return DateFormat('EEEE d MMMM', 'sv').format(_selectedDay);
                    } catch (_) {
                      return DateFormat('d MMMM').format(_selectedDay);
                    }
                  }(),
                  style: AppTheme.sectionTitleStyle),
            ),
          ),
          if (selected.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(24),
                decoration: AppTheme.cardDecoration(),
                child: const Center(child: Text('Ingen planering — lägg till! ✨',
                    style: TextStyle(color: Colors.grey))),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _ActivityCard(
                  doc: selected[i], 
                  dayColor: dayColor,
                  currentUser: _currentUser,
                  familyMembers: _familyMembers,
                ),
                childCount: selected.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      );
  }

  Widget _buildFocusView(List<QueryDocumentSnapshot> all) {
    final today = _getEventsForDay(all, DateTime.now());
    final dayColor = AppTheme.getDayAccentColor();
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, dayColor)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('Min dag', style: AppTheme.sectionTitleStyle),
            ),
          ),
          if (today.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(32),
                decoration: AppTheme.cardDecoration(),
                child: const Center(child: Text('Fri dag! 🌿')),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _FocusCard(
                  doc: today[i], 
                  dayColor: dayColor,
                  currentUser: _currentUser,
                  familyMembers: _familyMembers,
                ),
                childCount: today.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      );
  }

  Widget _buildHeader(BuildContext context, Color dayColor) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context),
      child: Text('Planering',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
    );
  }

  Widget _buildCalendar(List<QueryDocumentSnapshot> all, Color dayColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: AppTheme.cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: TableCalendar(
        firstDay: DateTime.utc(2020), lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        startingDayOfWeek: StartingDayOfWeek.monday,
        availableGestures: AvailableGestures.horizontalSwipe, 
        selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
        calendarFormat: CalendarFormat.month,
        availableCalendarFormats: const {CalendarFormat.month: 'Månad'},
        eventLoader: (day) {
          try {
            return _getEventsForDay(all, day).map((e) => e.id).toList();
          } catch (_) {
            return [];
          }
        },
        onDaySelected: (s, f) => setState(() { _selectedDay = s; _focusedDay = f; }),
        onPageChanged: (f) => setState(() => _focusedDay = f),
        locale: 'sv',
        calendarStyle: CalendarStyle(
          selectedDecoration: BoxDecoration(color: dayColor, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(color: dayColor.withValues(alpha: 0.3), shape: BoxShape.circle),
          markerDecoration: BoxDecoration(color: dayColor, shape: BoxShape.circle),
          markersMaxCount: 3,
          outsideDaysVisible: false,
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false, titleCentered: true,
          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildPersonFilter(Color dayColor) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          // NYTT: Toggle för importerat schema
          GestureDetector(
            onTap: () => setState(() => _showImported = !_showImported),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _showImported ? Colors.blueGrey.shade100 : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _showImported ? Colors.blueGrey : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(_showImported ? Icons.visibility : Icons.visibility_off, size: 16, color: _showImported ? Colors.blueGrey.shade800 : Colors.grey),
                  const SizedBox(width: 6),
                  Text('Schema', style: TextStyle(
                    color: _showImported ? Colors.blueGrey.shade800 : Colors.grey,
                    fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
          ),
          _Pill(label: 'Alla', selected: _filterPerson == null, color: dayColor,
              onTap: () => setState(() {
                    _filterPerson = null;
                    _filterPersonUid = null;
                  })),
          ..._familyMembers.map((m) {
            Color mc;
            try { mc = Color(m.colorValue as int); } catch (_) { mc = dayColor; }
            return _Pill(
              label: m.name.split(' ').first,
              selected: _filterPerson == m.name,
              color: mc,
              onTap: () => setState(() {
                if (_filterPerson == m.name) {
                  _filterPerson = null;
                  _filterPersonUid = null;
                } else {
                  _filterPerson = m.name;
                  _filterPersonUid = m.uid;
                }
              }),
            );
          }),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label; final bool selected; final Color color; final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, required this.color, required this.onTap});
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
      child: Text(label, style: TextStyle(
        color: selected ? Colors.white : AppTheme.getTextColor(),
        fontWeight: FontWeight.w600, fontSize: 13)),
    ),
  );
}

class _ActivityCard extends StatelessWidget {
  final QueryDocumentSnapshot doc; 
  final Color dayColor;
  final UserModel? currentUser;
  final List<UserModel> familyMembers;
  
  const _ActivityCard({
    required this.doc, 
    required this.dayColor,
    required this.currentUser,
    required this.familyMembers,
  });

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort aktivitet?'),
        content: const Text('Är du säker på att du vill ta bort denna aktivitet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await NotificationService.cancel(doc.id);
              await doc.reference.delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Ta bort'),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? '';
    final timeStr = d['time'] as String? ?? '';
    final date = parseDate(d['date']);
    final time = timeStr.isNotEmpty ? timeStr : (date != null ? DateFormat('HH:mm').format(date) : '');
    final isPending = d['isPending'] == true;

    return GestureDetector(
      onTap: () => showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ActivityDetailSheet(docSnapshot: doc)),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: AppTheme.cardDecoration().copyWith(
          border: Border(left: BorderSide(color: dayColor, width: 4))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            PlannerEventLeading(data: d, accentColor: dayColor, emojiSize: 34),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text(time, style: TextStyle(fontSize: 13, color: dayColor, fontWeight: FontWeight.w600)),
              if (isPending) const Text('⏳ Väntar på godkännande',
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
            ])),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
              padding: EdgeInsets.zero,
              onSelected: (val) {
                if (val == 'edit') {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AddEventSheet(
                      selectedDay: date ?? DateTime.now(),
                      familyMembers: familyMembers,
                      familyId: currentUser?.familyId,
                      eventToEdit: doc,
                    ),
                  );
                } else if (val == 'delete') {
                  _confirmDelete(context);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'edit', child: Text('Redigera')),
                const PopupMenuItem(value: 'delete', child: Text('Ta bort', style: TextStyle(color: Colors.red))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  final QueryDocumentSnapshot doc; 
  final Color dayColor;
  final UserModel? currentUser;
  final List<UserModel> familyMembers;

  const _FocusCard({
    required this.doc, 
    required this.dayColor,
    required this.currentUser,
    required this.familyMembers,
  });

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort aktivitet?'),
        content: const Text('Är du säker på att du vill ta bort denna aktivitet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await NotificationService.cancel(doc.id);
              await doc.reference.delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Ta bort'),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final title = d['title'] as String? ?? '';
    final timeStr = d['time'] as String? ?? '';
    final date = parseDate(d['date']);
    final time = timeStr.isNotEmpty ? timeStr : (date != null ? DateFormat('HH:mm').format(date) : '');

    return GestureDetector(
      onTap: () => showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ActivityDetailSheet(docSnapshot: doc)),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.cardDecoration(),
        child: Row(children: [
          PlannerEventLeading(data: d, accentColor: dayColor, emojiSize: 42),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(time, style: TextStyle(fontSize: 15, color: dayColor, fontWeight: FontWeight.w600)),
          ])),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
            padding: EdgeInsets.zero,
            onSelected: (val) {
              if (val == 'edit') {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddEventSheet(
                    selectedDay: date ?? DateTime.now(),
                    familyMembers: familyMembers,
                    familyId: currentUser?.familyId,
                    eventToEdit: doc,
                  ),
                );
              } else if (val == 'delete') {
                _confirmDelete(context);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('Redigera')),
              const PopupMenuItem(value: 'delete', child: Text('Ta bort', style: TextStyle(color: Colors.red))),
            ],
          ),
        ]),
      ),
    );
  }
}

class AddEventSheet extends StatefulWidget {
  final DateTime selectedDay;
  final List<UserModel> familyMembers;
  final String? familyId;
  final QueryDocumentSnapshot? eventToEdit;
  /// Förifylld titel (från snabbinmatningens fallback).
  final String? initialTitle;
  const AddEventSheet({super.key, required this.selectedDay, required this.familyMembers, this.familyId, this.eventToEdit, this.initialTitle});
  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  int _step = 0;
  String _pik = '📅';
  String _cat = 'Alla';
  String _q = '';
  final _title = TextEditingController();
  TimeOfDay _start = TimeOfDay.now();
  TimeOfDay? _end;
  final List<String> _persons = [];
  final List<String> _checklist = [];
  final _clCtrl = TextEditingController();
  
  bool _saving = false;
  bool _saveAsTemplate = false;
  List<QueryDocumentSnapshot> _templates = [];

  // Upprepning (ROADMAP Etapp 4)
  String _recurrenceType = 'none'; // none | weekly | biweekly | monthly
  DateTime? _recurrenceEnd;
  List<String> _recurrenceExceptions = [];
  String? _recurrenceStartDate; // bevaras vid redigering

  @override
  void initState() {
    super.initState();
    _loadTemplates();

    if (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) {
      _title.text = widget.initialTitle!;
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
        _recurrenceExceptions =
            (rec['exceptions'] as List? ?? []).cast<String>().toList();
      }
      
      final timeStr = d['time'] as String? ?? '';
      if (timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          _start = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
        }
      }
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
      
      final loadedChecklist = (d['checklist'] as List? ?? []).cast<Map<String, dynamic>>();
      _checklist.addAll(loadedChecklist.map((e) => e['item'] as String? ?? ''));

      _step = 1;
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('activity_templates').get();
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
      developer.log('planner _loadTemplates misslyckades',
          error: e, stackTrace: stack);
    }
  }

  void _applyTemplate(Map<String, dynamic> data) {
    setState(() {
      _pik = data['piktogram'] ?? '📅';
      _title.text = data['title'] ?? '';
      _checklist.clear();
      _checklist.addAll((data['checklist'] as List<dynamic>? ?? []).map((e) => e.toString()));
      _step = 1;
    });
  }

  List<PiktogramItem> get _filtered => piktogramLibrary.where((p) =>
    (_cat == 'Alla' || p.category == _cat) &&
    (_q.isEmpty || p.label.toLowerCase().contains(_q.toLowerCase()))
  ).toList();

  /// Veckodagsnamn för upprepningens startdag (befintlig start vid redigering).
  String _recurrenceDayName() {
    final start =
        parseDate(_recurrenceStartDate) ?? widget.selectedDay;
    const days = ['', 'måndag', 'tisdag', 'onsdag', 'torsdag',
        'fredag', 'lördag', 'söndag'];
    return days[start.weekday];
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final d = widget.selectedDay;
      final titleStr = _title.text.trim();
      
      final data = <String, dynamic>{
        'title': titleStr,
        'piktogram': _pik,
        'type': 'activity',
        'date': dateKey(d),
        'time': '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}',
        'persons': _persons,
        'personUids': uidsForNames(widget.familyMembers, _persons),
        'checklist': _checklist.map((i) {
          bool isDone = false;
          if (widget.eventToEdit != null) {
            final oldD = widget.eventToEdit!.data() as Map<String, dynamic>;
            final oldChecklist = (oldD['checklist'] as List? ?? []).cast<Map<String, dynamic>>();
            final existing = oldChecklist.where((old) => old['item'] == i);
            if (existing.isNotEmpty) {
              isDone = existing.first['isDone'] == true;
            }
          }
          return {'item': i, 'isDone': isDone};
        }).toList(),
        'source': 'manual',
        'createdBy': user?.uid,
        'isPending': false,
        'familyId': widget.familyId ?? '',
      };

      if (_end != null) {
        data['endTime'] =
            '${_end!.hour.toString().padLeft(2, '0')}:${_end!.minute.toString().padLeft(2, '0')}';
      } else if (widget.eventToEdit != null) {
        data['endTime'] = FieldValue.delete();
      }

      // Upprepning: spara/uppdatera recurrence-blocket.
      if (_recurrenceType != 'none') {
        data['isRecurring'] = true;
        data['recurrence'] = {
          'type': _recurrenceType,
          'startDate': _recurrenceStartDate ?? dateKey(d),
          'endDate': _recurrenceEnd != null ? dateKey(_recurrenceEnd!) : null,
          'exceptions': _recurrenceExceptions,
        };
      } else if (widget.eventToEdit != null) {
        data['isRecurring'] = FieldValue.delete();
        data['recurrence'] = FieldValue.delete();
      }

      String savedDocId;
      if (widget.eventToEdit != null) {
        savedDocId = widget.eventToEdit!.id;
        // Avboka gamla notiser (även instanser om eventet var återkommande).
        await NotificationService.cancelActivityReminders(
          savedDocId,
          widget.eventToEdit!.data() as Map<String, dynamic>,
        );
        await widget.eventToEdit!.reference.update(data);
      } else {
        final ref = await FirebaseFirestore.instance
            .collection('planner_events')
            .add(data);
        savedDocId = ref.id;
      }

      // Ren karta utan FieldValue-sentinels för notis-schemaläggning.
      await NotificationService.scheduleActivityReminders(
        docId: savedDocId,
        data: {
          'title': titleStr,
          'date': dateKey(d),
          'time': data['time'],
          if (_recurrenceType != 'none')
            'recurrence': {
              'type': _recurrenceType,
              'startDate': _recurrenceStartDate ?? dateKey(d),
              'endDate':
                  _recurrenceEnd != null ? dateKey(_recurrenceEnd!) : null,
              'exceptions': _recurrenceExceptions,
            },
        },
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
            content: Text(widget.eventToEdit != null ? 'Aktivitet uppdaterad! ✅' : 'Aktivitet sparad! ✅'),
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
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.only(top: 12),
          child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(
              _step == 0 ? 'Välj piktogram / Mall' : (widget.eventToEdit != null ? 'Redigera aktivitet' : 'Aktivitetsdetaljer'),
              style: AppTheme.sectionTitleStyle
            )),
            if (_step == 1) TextButton(onPressed: () => setState(() => _step = 0),
                child: const Text('← Tillbaka')),
          ]),
        ),
        Expanded(child: _step == 0 ? _picker(dayColor) : _form(dayColor)),
      ]),
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
          child: Text('Hämta från mall', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    border: Border.all(color: dayColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d['piktogram'] ?? '📋', style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 10),
                      Text(d['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          decoration: InputDecoration(hintText: 'Sök piktogram...', prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true, fillColor: Colors.grey.shade100, contentPadding: const EdgeInsets.symmetric(vertical: 8)),
        ),
      ),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: piktogramCategories.map((c) => _Pill(label: c, selected: _cat == c,
            color: dayColor, onTap: () => setState(() => _cat = c))).toList())),
      const SizedBox(height: 8),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.9),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final p = items[i];
          final sel = p.emoji == _pik;
          return GestureDetector(
            onTap: () { setState(() { _pik = p.emoji; if (_title.text.isEmpty) _title.text = p.label; _step = 1; }); },
            child: AnimatedContainer(duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: sel ? dayColor.withValues(alpha: 0.15) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: sel ? Border.all(color: dayColor, width: 2) : null),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.emoji, style: const TextStyle(fontSize: 24)),
                Text(p.label, style: const TextStyle(fontSize: 9), textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
          );
        },
      )),
    ]);
  }

  Widget _form(Color dayColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: GestureDetector(
          onTap: () => setState(() => _step = 0),
          child: Column(children: [
            Text(_pik, style: const TextStyle(fontSize: 56)),
            Text('Byt piktogram / Mall', style: TextStyle(fontSize: 12, color: dayColor)),
          ]),
        )),
        const SizedBox(height: 16),
        TextField(controller: _title,
          decoration: InputDecoration(labelText: 'Aktivitetsnamn',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.access_time),
          label: Text('Starttid: ${_start.format(context)}'),
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: _start);
            if (t != null) setState(() => _start = t);
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.schedule_rounded),
          label: Text(
            _end == null
                ? 'Sluttid (valfritt)'
                : 'Slut: ${_end!.format(context)}',
          ),
          onPressed: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: _end ??
                  TimeOfDay(
                    hour: (_start.hour + 1) % 24,
                    minute: _start.minute,
                  ),
            );
            if (t != null) setState(() => _end = t);
          },
        ),
        if (_end != null)
          TextButton(
            onPressed: () => setState(() => _end = null),
            child: const Text('Ta bort sluttid'),
          ),
        const SizedBox(height: 16),
        Text('UPPREPNING', style: AppTheme.sectionLabelStyle),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _recurrenceType,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            const DropdownMenuItem(
                value: 'none', child: Text('Engångshändelse')),
            DropdownMenuItem(
                value: 'weekly',
                child: Text('Varje ${_recurrenceDayName()}')),
            DropdownMenuItem(
                value: 'biweekly',
                child: Text('Varannan ${_recurrenceDayName()}')),
            const DropdownMenuItem(
                value: 'monthly', child: Text('Varje månad (samma datum)')),
          ],
          onChanged: (v) => setState(() => _recurrenceType = v ?? 'none'),
        ),
        if (_recurrenceType != 'none') ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_busy_rounded),
            label: Text(_recurrenceEnd == null
                ? 'Slutdatum: tills vidare'
                : 'Slut: ${dateKey(_recurrenceEnd!)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _recurrenceEnd ??
                    widget.selectedDay.add(const Duration(days: 90)),
                firstDate: widget.selectedDay,
                lastDate: widget.selectedDay.add(const Duration(days: 365 * 2)),
              );
              if (picked != null) setState(() => _recurrenceEnd = picked);
            },
          ),
          if (_recurrenceEnd != null)
            TextButton(
              onPressed: () => setState(() => _recurrenceEnd = null),
              child: const Text('Upprepa tills vidare'),
            ),
        ],
        const SizedBox(height: 16),
        Text('Vem deltar?', style: AppTheme.sectionLabelStyle),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: widget.familyMembers.map((m) {
          final sel = _persons.contains(m.name);
          Color mc; try { mc = Color(m.colorValue as int); } catch (_) { mc = dayColor; }
          return FilterChip(label: Text(m.name.split(' ').first), selected: sel,
            selectedColor: mc.withValues(alpha: 0.2), checkmarkColor: mc,
            onSelected: (v) => setState(() => v ? _persons.add(m.name) : _persons.remove(m.name)));
        }).toList()),
        const SizedBox(height: 16),
        Text('Packlista / Förberedelser', style: AppTheme.sectionLabelStyle),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _clCtrl,
            decoration: InputDecoration(hintText: 'Lägg till...', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            onSubmitted: (v) { if (v.trim().isNotEmpty) setState(() { _checklist.add(v.trim()); _clCtrl.clear(); }); })),
          const SizedBox(width: 8),
          IconButton(icon: Icon(Icons.add_circle_rounded, color: dayColor, size: 32),
            onPressed: () { if (_clCtrl.text.trim().isNotEmpty) setState(() { _checklist.add(_clCtrl.text.trim()); _clCtrl.clear(); }); }),
        ]),
        ..._checklist.map((item) => ListTile(
          leading: const Icon(Icons.check_circle_outline), title: Text(item), dense: true, contentPadding: EdgeInsets.zero,
          trailing: IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.red),
            onPressed: () => setState(() => _checklist.remove(item))))),
        
        if (widget.eventToEdit == null) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200)
            ),
            child: SwitchListTile(
              title: const Text('Spara som mall', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Sparar namn, emoji och packlista för framtiden.', style: TextStyle(fontSize: 12)),
              value: _saveAsTemplate,
              activeColor: dayColor,
              onChanged: (val) => setState(() => _saveAsTemplate = val),
            ),
          ),
        ],

        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: dayColor, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: _saving ? const CircularProgressIndicator(color: Colors.white) :
              Text(widget.eventToEdit != null ? 'Uppdatera aktivitet' : 'Spara aktivitet', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        )),
        const SizedBox(height: 40),
      ]),
    );
  }
}