import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _filterPerson;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
  }

  void _showEventDialog({DocumentSnapshot? eventToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEventSheet(eventToEdit: eventToEdit),
    );
  }

  void _showImportDialog() {
    showDialog(context: context, builder: (context) => const ImportDialog());
  }

  Color _getEventColor(Map data) {
    String type = data['type'] ?? '';
    String title = (data['title'] ?? '').toString().toLowerCase();
    if (title.contains('läkare') ||
        title.contains('tand') ||
        title.contains('bup') ||
        title.contains('sjukhus') ||
        title.contains('vård'))
      return Colors.redAccent;
    if (title.contains('skola') ||
        title.contains('läxa') ||
        title.contains('prov'))
      return Colors.purpleAccent;
    if (type == 'work' || title.contains('jobb')) return Colors.blue;
    if (type == 'food') return Colors.orange;
    return Colors.pinkAccent;
  }

  Future<void> _deleteEvent(String docId) async {
    await FirebaseFirestore.instance
        .collection('planner_events')
        .doc(docId)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    Color textColor = AppTheme.getTextColor();
    Color cardColor = AppTheme.getCardColor();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton(
          onPressed: () => _showEventDialog(),
          backgroundColor: Colors.white,
          foregroundColor: Colors.blueAccent,
          child: const Icon(Icons.add_rounded, size: 30),
        ),
      ),
      body: Stack(
        children: [
          Container(decoration: AppTheme.getBackground()),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48),
                      Text(
                        "Planering",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.upload_file, color: textColor),
                        onPressed: _showImportDialog,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  height: 50,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      var users = snapshot.data!.docs
                          .where((d) => (d.data() as Map)['name'] != null)
                          .toList();
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: users.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _filterPerson = null),
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: _filterPerson == null
                                      ? Colors.white
                                      : cardColor,
                                  child: Icon(
                                    Icons.people,
                                    color: _filterPerson == null
                                        ? Colors.blue
                                        : textColor,
                                  ),
                                ),
                              ),
                            );
                          }
                          var data = users[index - 1].data() as Map;
                          Color uColor = Color(
                            int.parse(data['color'] ?? 'ff2196f3', radix: 16),
                          );
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _filterPerson =
                                    _filterPerson == data['name']
                                    ? null
                                    : data['name'],
                              ),
                              child: CircleAvatar(
                                backgroundColor: uColor,
                                radius: 22,
                                child: _filterPerson == data['name']
                                    ? Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          data['name'][0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('planner_events')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      List<QueryDocumentSnapshot> allDocs = snapshot.data!.docs;
                      if (_filterPerson != null)
                        allDocs = allDocs
                            .where(
                              (doc) => (doc.data() as Map)['title']
                                  .toString()
                                  .contains(_filterPerson!),
                            )
                            .toList();
                      Map<DateTime, List<dynamic>> eventsPerDay = {};
                      for (var doc in allDocs) {
                        try {
                          var data = doc.data() as Map;
                          List<String> p = data['date'].split('-');
                          DateTime d = DateTime.utc(
                            int.parse(p[0]),
                            int.parse(p[1]),
                            int.parse(p[2]),
                          );
                          if (eventsPerDay[d] == null) eventsPerDay[d] = [];
                          eventsPerDay[d]!.add(data);
                        } catch (e) {}
                      }
                      String selDate =
                          "${_selectedDay?.year}-${_selectedDay?.month}-${_selectedDay?.day}";
                      var dayEvents = allDocs
                          .where((d) => (d.data() as Map)['date'] == selDate)
                          .toList();

                      return Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: TableCalendar(
                              locale: 'sv_SE',
                              firstDay: DateTime.utc(2024),
                              lastDay: DateTime.utc(2030),
                              focusedDay: _focusedDay,
                              calendarFormat: CalendarFormat.month,
                              startingDayOfWeek: StartingDayOfWeek.monday,

                              availableGestures: AvailableGestures.none,

                              eventLoader: (day) =>
                                  eventsPerDay[DateTime.utc(
                                    day.year,
                                    day.month,
                                    day.day,
                                  )] ??
                                  [],
                              calendarBuilders: CalendarBuilders(
                                defaultBuilder: (context, day, focusedDay) {
                                  return Center(
                                    child: Container(
                                      width: 35,
                                      height: 35,
                                      decoration: BoxDecoration(
                                        color: AppTheme.getNpfDayColor(
                                          day.weekday,
                                        ).withOpacity(0.8),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          color: AppTheme.getNpfTextColor(
                                            day.weekday,
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                todayBuilder: (context, day, focusedDay) {
                                  return Center(
                                    child: Container(
                                      width: 35,
                                      height: 35,
                                      decoration: BoxDecoration(
                                        color: AppTheme.getNpfDayColor(
                                          day.weekday,
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          color: AppTheme.getNpfTextColor(
                                            day.weekday,
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                selectedBuilder: (context, day, focusedDay) {
                                  return Center(
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${day.day}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                markerBuilder: (context, day, events) {
                                  if (events.isEmpty) return const SizedBox();
                                  return Positioned(
                                    bottom: 2,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: events
                                          .take(3)
                                          .map(
                                            (e) => Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 1.0,
                                                  ),
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.black54,
                                                  width: 0.5,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  );
                                },
                              ),
                              headerStyle: HeaderStyle(
                                formatButtonVisible: false,
                                titleCentered: true,
                                titleTextStyle: TextStyle(
                                  color: textColor,
                                  fontSize: 17,
                                ),
                                leftChevronVisible: true,
                                rightChevronVisible: true,
                                leftChevronIcon: Icon(
                                  Icons.chevron_left,
                                  color: textColor,
                                ),
                                rightChevronIcon: Icon(
                                  Icons.chevron_right,
                                  color: textColor,
                                ),
                              ),
                              selectedDayPredicate: (day) =>
                                  isSameDay(_selectedDay, day),
                              onDaySelected: (s, f) => setState(() {
                                _selectedDay = s;
                                _focusedDay = f;
                              }),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 120),
                              itemCount: dayEvents.length,
                              itemBuilder: (context, index) {
                                var data = dayEvents[index].data() as Map;
                                Color dotColor = _getEventColor(data);
                                IconData icon = AppTheme.getEventIcon(
                                  data['title'],
                                  data['type'],
                                );

                                return GestureDetector(
                                  onTap: () => _showEventDialog(
                                    eventToEdit: dayEvents[index],
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: dotColor.withOpacity(
                                          0.2,
                                        ),
                                        child: Icon(
                                          icon,
                                          color: dotColor,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        data['title'],
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        data['time'],
                                        style: TextStyle(
                                          color: textColor.withOpacity(0.7),
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(
                                          Icons.delete,
                                          color: textColor.withOpacity(0.5),
                                        ),
                                        onPressed: () =>
                                            _deleteEvent(dayEvents[index].id),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImportDialog extends StatelessWidget {
  const ImportDialog({super.key});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Importera"),
      content: const Text("Kommer snart"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("OK"),
        ),
      ],
    );
  }
}

class AddEventSheet extends StatefulWidget {
  final DocumentSnapshot? eventToEdit;
  const AddEventSheet({super.key, this.eventToEdit});
  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  String _selectedType = 'food';
  final TextEditingController _titleController = TextEditingController();
  String? _selectedPersonName;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final Set<DateTime> _selectedDates = {};
  DateTime _focusedDay = DateTime.now();
  bool _addToGoogleCalendar = false;
  @override
  void initState() {
    super.initState();
    if (widget.eventToEdit != null) {
      var data = widget.eventToEdit!.data() as Map;
      _selectedType = data['type'];
      _titleController.text = data['title'];
      try {
        _selectedDates.add(DateTime.parse(data['date']));
      } catch (e) {}
    } else {
      DateTime now = DateTime.now();
      _selectedDates.add(DateTime(now.year, now.month, now.day));
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) setState(() => isStart ? _startTime = t : _endTime = t);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  Future<void> _openGoogleCalendar(
    String title,
    DateTime date,
    TimeOfDay? start,
    TimeOfDay? end,
  ) async {
    final DateFormat formatter = DateFormat('yyyyMMdd');
    final String dateStr = formatter.format(date);
    String dates = "$dateStr/$dateStr";
    if (start != null) {
      final String sTime =
          "${start.hour.toString().padLeft(2, '0')}${start.minute.toString().padLeft(2, '0')}00";
      final String eTime = end != null
          ? "${end.hour.toString().padLeft(2, '0')}${end.minute.toString().padLeft(2, '0')}00"
          : "${(start.hour + 1).toString().padLeft(2, '0')}${start.minute.toString().padLeft(2, '0')}00";
      dates = "${dateStr}T$sTime/${dateStr}T$eTime";
    }
    final Uri url = Uri.parse(
      'https://www.google.com/calendar/render?action=TEMPLATE&text=${Uri.encodeComponent(title)}&dates=$dates',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _saveAll() async {
    if (_selectedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Välj minst ett datum i kalendern!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    String finalTitle = _titleController.text;
    if ((_selectedType == 'work' || _selectedType == 'activity') &&
        _selectedPersonName != null) {
      finalTitle = finalTitle.isEmpty
          ? _selectedPersonName!
          : "$_selectedPersonName ($finalTitle)";
    }
    String timeStr = _startTime != null ? _formatTime(_startTime!) : "";
    if (_endTime != null) timeStr += " - ${_formatTime(_endTime!)}";
    for (var date in _selectedDates) {
      String dateKey = "${date.year}-${date.month}-${date.day}";
      if (_selectedType == 'food') {
        var old = await FirebaseFirestore.instance
            .collection('planner_events')
            .where('date', isEqualTo: dateKey)
            .where('type', isEqualTo: 'food')
            .get();
        for (var doc in old.docs) await doc.reference.delete();
      }
      await FirebaseFirestore.instance.collection('planner_events').add({
        'type': _selectedType,
        'title': finalTitle,
        'date': dateKey,
        'time': timeStr,
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (_addToGoogleCalendar) {
        await _openGoogleCalendar(finalTitle, date, _startTime, _endTime);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _typeButton(String label, IconData icon, String value, Color color) {
    bool isSelected = _selectedType == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = value),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.grey[100],
              shape: BoxShape.circle,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[400],
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black87 : Colors.grey[400],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        children: [
          const Text(
            "Lägg till händelse",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _typeButton(
                        "Mat",
                        Icons.restaurant_rounded,
                        'food',
                        Colors.orange,
                      ),
                      _typeButton(
                        "Jobb/Skola",
                        Icons.work_rounded,
                        'work',
                        Colors.blue,
                      ),
                      _typeButton(
                        "Aktivitet",
                        Icons.sports_soccer_rounded,
                        'activity',
                        Colors.pink,
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  if (_selectedType != 'food')
                    SizedBox(
                      height: 80,
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox();
                          var users = snapshot.data!.docs
                              .where(
                                (d) =>
                                    (d.data() as Map)['name'] != null &&
                                    (d.data() as Map)['name']
                                        .toString()
                                        .isNotEmpty,
                              )
                              .toList();
                          return ListView(
                            scrollDirection: Axis.horizontal,
                            children: users.map((doc) {
                              var data = doc.data() as Map;
                              bool isSel = _selectedPersonName == data['name'];
                              Color uColor = Color(
                                int.parse(
                                  data['color'] ?? 'ff2196f3',
                                  radix: 16,
                                ),
                              );
                              return Padding(
                                padding: const EdgeInsets.only(right: 15.0),
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _selectedPersonName = isSel
                                        ? null
                                        : data['name'],
                                  ),
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: uColor,
                                        radius: 24,
                                        child: Container(
                                          decoration: isSel
                                              ? BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.blueAccent,
                                                    width: 3,
                                                  ),
                                                )
                                              : null,
                                          alignment: Alignment.center,
                                          child: Text(
                                            data['name'][0].toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        data['name'],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSel
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSel