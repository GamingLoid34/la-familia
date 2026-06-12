import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/family_service.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';

class WorkSchedulePage extends StatefulWidget {
  /// Öppna med ”Alla” valt (t.ex. från Planering när inget personfilter).
  final bool openWithAllMembers;
  /// Förval fullständigt namn som i Firestore, om det finns i familjen.
  final String? initialPersonName;
  /// Förval dag (lokal datumdel används).
  final DateTime? initialDay;

  const WorkSchedulePage({
    super.key,
    this.openWithAllMembers = false,
    this.initialPersonName,
    this.initialDay,
  });

  @override
  State<WorkSchedulePage> createState() => _WorkSchedulePageState();
}

class _WorkSchedulePageState extends State<WorkSchedulePage> {
  String _familyId = '';
  List<UserModel> _familyMembers = [];
  String? _selectedPerson;
  String? _selectedPersonUid;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadFamilyData();
  }

  Future<void> _loadFamilyData() async {
    final user = await FamilyService.getCurrentUserModel();
    if (user?.familyId != null) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('familyId', isEqualTo: user!.familyId)
          .get();
      final members =
          snap.docs.map((d) => UserModel.fromMap(d.id, d.data())).toList();
      if (mounted) {
        setState(() {
          _familyId = user.familyId!;
          _familyMembers = members;
          if (widget.initialDay != null) {
            final d = widget.initialDay!;
            _selectedDay = DateTime(d.year, d.month, d.day);
            _focusedDay = _selectedDay;
          }
          if (widget.openWithAllMembers) {
            _selectedPerson = null;
            _selectedPersonUid = null;
          } else if (widget.initialPersonName != null &&
              members.any((m) => m.name == widget.initialPersonName)) {
            _selectedPerson = widget.initialPersonName;
            _selectedPersonUid =
                uidForName(members, widget.initialPersonName!);
          } else {
            // Börja med ditt eget schema; byt till ”Alla” eller annan person när du vill.
            _selectedPerson ??= user.name;
            _selectedPersonUid ??= user.uid;
          }
        });
      }
    }
  }

  List<Map<String, dynamic>> _getCombinedEvents(
      List<QueryDocumentSnapshot> shifts, List<QueryDocumentSnapshot> calEvents) {
    List<Map<String, dynamic>> combined = [];

    // Arbetspass
    for (var doc in shifts) {
      final d = doc.data() as Map<String, dynamic>;
      final date = parseDate(d['date']);
      if (date == null || !isSameDay(date, _selectedDay)) continue;
      if (_selectedPerson != null &&
          !assignedToPerson(d,
              uid: _selectedPersonUid ?? '', name: _selectedPerson!)) {
        continue;
      }

      combined.add({
        'id': doc.id,
        'type': 'work',
        'title': 'Arbetspass',
        'who': d['who'] ?? 'Någon',
        'startTime': d['startTime'] ?? '',
        'endTime': d['endTime'] ?? '',
        'piktogram': '💼',
        'sortTime': d['startTime'] ?? '00:00',
        'doc': doc,
      });
    }

    // Importerade kalenderhändelser
    for (var doc in calEvents) {
      final d = doc.data() as Map<String, dynamic>;
      final date = parseDate(d['date']);
      if (date == null || !isSameDay(date, _selectedDay)) continue;
      
      final persons = (d['persons'] as List? ?? []).cast<String>();
      if (_selectedPerson != null &&
          !eventIncludesPerson(d,
              uid: _selectedPersonUid ?? '', name: _selectedPerson!)) {
        continue;
      }

      final t = (d['time'] as String? ?? '').trim();
      final et = (d['endTime'] as String? ?? '').trim();
      combined.add({
        'id': doc.id,
        'type': 'school',
        'title': d['title'] ?? 'Schema',
        'who': persons.isNotEmpty ? persons.first : 'Gemensam',
        'time': t,
        'endTime': et,
        'piktogram': d['piktogram'] ?? '🏫',
        'calendarName': d['calendarName'] ?? '',
        'sortTime': t.isEmpty ? '00:00' : t,
        'doc': doc,
      });
    }

    // Sortera på tid
    combined.sort((a, b) {
      return (a['sortTime'] as String).compareTo(b['sortTime'] as String);
    });

    return combined;
  }

  void _showAddShiftSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddWorkShiftSheet(
        familyId: _familyId,
        familyMembers: _familyMembers,
      ),
    );
  }

  void _confirmDelete(String collection, QueryDocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort post?'),
        content: const Text('Är du säker på att du vill ta bort detta från schemat?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              doc.reference.delete();
              Navigator.pop(ctx);
            },
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    return Scaffold(
      body: Container(
        decoration: AppTheme.getBackground(),
        child: _familyId.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: AppTheme.headerDecoration(),
                      padding: AppTheme.paddingBelowStatusBar(context),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(Icons.arrow_back_ios_rounded, color: textColor),
                          ),
                          const SizedBox(width: 12),
                          Text('Scheman',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: textColor)),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: AppTheme.cardDecoration(),
                      child: TableCalendar(
                        firstDay: DateTime.utc(2020),
                        lastDay: DateTime.utc(2030, 12, 31),
                        focusedDay: _focusedDay,
                        startingDayOfWeek: StartingDayOfWeek.monday,
                        calendarFormat: CalendarFormat.week, // VECKOVY!
                        availableCalendarFormats: const {CalendarFormat.week: 'Vecka'},
                        selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
                        onDaySelected: (s, f) => setState(() {
                          _selectedDay = s;
                          _focusedDay = f;
                        }),
                        locale: 'sv',
                        headerStyle: const HeaderStyle(
                          titleCentered: true,
                          formatButtonVisible: false,
                        ),
                        calendarStyle: CalendarStyle(
                          selectedDecoration: BoxDecoration(
                              color: dayColor, shape: BoxShape.circle),
                          todayDecoration: BoxDecoration(
                              color: dayColor.withValues(alpha: 0.3),
                              shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _Pill(
                              label: 'Alla',
                              selected: _selectedPerson == null,
                              color: dayColor,
                              onTap: () => setState(() {
                                    _selectedPerson = null;
                                    _selectedPersonUid = null;
                                  })),
                          ..._familyMembers.map((m) {
                            Color mc;
                            try {
                              mc = Color(m.colorValue as int);
                            } catch (_) {
                              mc = dayColor;
                            }
                            return _Pill(
                                label: m.name.split(' ').first,
                                selected: _selectedPerson == m.name,
                                color: mc,
                                onTap: () => setState(() {
                                      if (_selectedPerson == m.name) {
                                        _selectedPerson = null;
                                        _selectedPersonUid = null;
                                      } else {
                                        _selectedPerson = m.name;
                                        _selectedPersonUid = m.uid;
                                      }
                                    }));
                          }),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Text(
                        DateFormat('EEEE d MMMM', 'sv').format(_selectedDay),
                        style: AppTheme.sectionTitleStyle,
                      ),
                    ),
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('work_shifts')
                        .where('familyId', isEqualTo: _familyId)
                        .snapshots(),
                    builder: (context, shiftSnap) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('planner_events')
                            .where('familyId', isEqualTo: _familyId)
                            .where('source', isEqualTo: 'calendar')
                            .snapshots(),
                        builder: (context, calSnap) {
                          if (shiftSnap.connectionState == ConnectionState.waiting &&
                              calSnap.connectionState == ConnectionState.waiting) {
                            return const SliverToBoxAdapter(
                                child: Center(child: CircularProgressIndicator()));
                          }

                          final shifts = shiftSnap.data?.docs ?? [];
                          final calEvents = calSnap.data?.docs ?? [];
                          final combined = _getCombinedEvents(shifts, calEvents);

                          if (combined.isEmpty) {
                            return SliverToBoxAdapter(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                                padding: const EdgeInsets.all(24),
                                decoration: AppTheme.cardDecoration(),
                                child: const Center(
                                  child: Text('Inget inlagt denna dag.',
                                      style: TextStyle(color: Colors.grey)),
                                ),
                              ),
                            );
                          }

                          return SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final item = combined[i];
                                final isWork = item['type'] == 'work';
                                return Container(
                                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                  decoration: AppTheme.cardDecoration().copyWith(
                                    border: Border(left: BorderSide(color: isWork ? Colors.blue : dayColor, width: 4)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Text(item['piktogram'], style: const TextStyle(fontSize: 32)),
                                    title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('👤 ${item['who']}'),
                                        Text(
                                          isWork
                                              ? '🕒 ${item['startTime']} - ${item['endTime']}'
                                              : () {
                                                  final st = item['time']?.toString() ?? '';
                                                  final en =
                                                      item['endTime']?.toString() ?? '';
                                                  if (st.isNotEmpty &&
                                                      en.isNotEmpty) {
                                                    return '🕒 $st – $en';
                                                  }
                                                  if (st.isNotEmpty) {
                                                    return '🕒 $st';
                                                  }
                                                  return '🕒 Heldag / tid saknas';
                                                }(),
                                          style: TextStyle(color: isWork ? Colors.blue : dayColor, fontWeight: FontWeight.bold),
                                        ),
                                        if (!isWork && item['calendarName'].toString().isNotEmpty)
                                          Text('📅 Importerad från: ${item['calendarName']}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _confirmDelete(isWork ? 'work_shifts' : 'planner_events', item['doc']),
                                    ),
                                  ),
                                );
                              },
                              childCount: combined.length,
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddShiftSheet,
        backgroundColor: dayColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nytt arbetspass', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

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

// ==========================================
// BOTTOM SHEET FÖR ATT LÄGGA TILL ARBETSPASS
// ==========================================
/// Delad med planeringssidan (FAB).
class AddWorkShiftSheet extends StatefulWidget {
  final String familyId;
  final List<UserModel> familyMembers;

  const AddWorkShiftSheet({
    super.key,
    required this.familyId,
    required this.familyMembers,
  });

  @override
  State<AddWorkShiftSheet> createState() => _AddWorkShiftSheetState();
}

class _AddWorkShiftSheetState extends State<AddWorkShiftSheet> {
  String? _selectedPerson;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final Set<DateTime> _selectedDates = {};
  DateTime _focusedDay = DateTime.now();
  bool _saving = false;

  Future<void> _pickTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return "--:--";
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _saveShift() async {
    if (_selectedPerson == null || _startTime == null || _endTime == null || _selectedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fyll i vem, tid och välj datum."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (var date in _selectedDates) {
        final ref = FirebaseFirestore.instance.collection('work_shifts').doc();
        batch.set(ref, {
          'date': dateKey(date),
          'who': _selectedPerson,
          'whoUid': uidForName(widget.familyMembers, _selectedPerson ?? ''),
          'startTime': _formatTime(_startTime),
          'endTime': _formatTime(_endTime),
          'familyId': widget.familyId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Arbetspass sparat! ✅"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fel: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Lägg till Arbetspass', style: AppTheme.sectionTitleStyle),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1. Vem jobbar?', style: AppTheme.sectionLabelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: widget.familyMembers.map((m) {
                      final sel = _selectedPerson == m.name;
                      Color mc;
                      try { mc = Color(m.colorValue as int); } catch (_) { mc = dayColor; }
                      return ChoiceChip(
                        label: Text(m.name.split(' ').first),
                        selected: sel,
                        selectedColor: mc.withValues(alpha: 0.2),
                        onSelected: (v) => setState(() => _selectedPerson = v ? m.name : null),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  
                  Text('2. Välj tid', style: AppTheme.sectionLabelStyle),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(true),
                          icon: const Icon(Icons.access_time),
                          label: Text(_startTime == null ? 'Starttid' : _formatTime(_startTime)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(false),
                          icon: const Icon(Icons.access_time_filled),
                          label: Text(_endTime == null ? 'Sluttid' : _formatTime(_endTime)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  Text('3. Markera datum', style: AppTheme.sectionLabelStyle),
                  const SizedBox(height: 8),
                  Container(
                    decoration: AppTheme.cardDecoration(radius: 16).copyWith(
                      border: Border.all(color: Colors.grey.shade200)
                    ),
                    child: TableCalendar(
                      firstDay: DateTime.utc(2020),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      calendarFormat: CalendarFormat.month,
                      availableCalendarFormats: const {CalendarFormat.month: 'Månad'},
                      selectedDayPredicate: (day) {
                        return _selectedDates.contains(DateTime(day.year, day.month, day.day));
                      },
                      onDaySelected: (s, f) {
                        setState(() {
                          _focusedDay = f;
                          final d = DateTime(s.year, s.month, s.day);
                          if (_selectedDates.contains(d)) {
                            _selectedDates.remove(d);
                          } else {
                            _selectedDates.add(d);
                          }
                        });
                      },
                      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
                      calendarStyle: CalendarStyle(
                        selectedDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        todayDecoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.3), shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveShift,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Spara Arbetspass', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}