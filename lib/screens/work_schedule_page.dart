import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Moln-koppling
import 'package:shared_preferences/shared_preferences.dart';

class WorkSchedulePage extends StatefulWidget {
  const WorkSchedulePage({super.key});

  @override
  State<WorkSchedulePage> createState() => _WorkSchedulePageState();
}

class _WorkSchedulePageState extends State<WorkSchedulePage> {
  // Familjemedlemmar och deras färger
  final Map<String, Color> familyColors = {
    "Mamma": Colors.purpleAccent,
    "Pappa": Colors.blueAccent,
    "Barn 1": Colors.greenAccent,
    "Barn 2": Colors.orangeAccent,
  };

  List<String> familyMembers = ["Mamma", "Pappa", "Barn 1", "Barn 2"];
  String? _selectedPerson; // Vem gäller passet?

  TimeOfDay? startTime;
  TimeOfDay? endTime;
  final Set<DateTime> _selectedDates = {};
  DateTime _focusedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadFamilySettings();
  }

  // Ladda om man ändrat namn i inställningar (men behåll färg-logiken enkel nu)
  Future<void> _loadFamilySettings() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedFamily = prefs.getStringList('family_members');
    if (savedFamily != null && savedFamily.isNotEmpty) {
      setState(() {
        familyMembers = savedFamily;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 08, minute: 00),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.blueAccent,
                onPrimary: Colors.white,
                surface: Colors.grey,
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart)
          startTime = picked;
        else
          endTime = picked;
      });
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return "--:--";
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _focusedDay = focusedDay;
      final dateOnly = DateTime(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
      );
      if (_selectedDates.contains(dateOnly)) {
        _selectedDates.remove(dateOnly);
      } else {
        _selectedDates.add(dateOnly);
      }
    });
  }

  // SPARA TILL FIREBASE
  Future<void> _saveShift() async {
    if (_selectedPerson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Du måste välja VEM som jobbar."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (startTime == null || endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Välj både start- och sluttid."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Markera minst ett datum i kalendern."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Spara varje datum som en egen post i databasen
    for (var date in _selectedDates) {
      String dateKey = "${date.year}-${date.month}-${date.day}";

      await FirebaseFirestore.instance.collection('work_shifts').add({
        'date': dateKey,
        'who': _selectedPerson,
        'startTime': _formatTime(startTime),
        'endTime': _formatTime(endTime),
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Sparat $_selectedPerson:s pass!"),
        backgroundColor: Colors.green,
      ),
    );

    // Rensa formuläret
    setState(() {
      _selectedDates.clear();
      startTime = null;
      endTime = null;
      // Vi behåller vald person ifall man ska lägga in fler pass för samma
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Lägg till Arbetspass"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. VÄLJ PERSON
            const Text(
              "1. Vem jobbar?",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: familyMembers.map((person) {
                bool isSelected = _selectedPerson == person;
                // Försök hitta en färg, annars ta grå
                Color pColor = familyColors[person] ?? Colors.grey;

                return ChoiceChip(
                  label: Text(
                    person,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: pColor,
                  backgroundColor: Colors.white10,
                  onSelected: (selected) {
                    setState(() => _selectedPerson = selected ? person : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 30),

            // 2. MARKERA DATUM
            const Text(
              "2. Markera datum",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white10),
              ),
              child: TableCalendar(
                firstDay: DateTime.utc(2024, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                startingDayOfWeek: StartingDayOfWeek.monday,
                selectedDayPredicate: (day) {
                  final dateOnly = DateTime(day.year, day.month, day.day);
                  return _selectedDates.contains(dateOnly);
                },
                onDaySelected: _onDaySelected,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: Colors.white, fontSize: 16),
                ),
                calendarStyle: const CalendarStyle(
                  defaultTextStyle: TextStyle(color: Colors.white),
                  weekendTextStyle: TextStyle(color: Colors.white70),
                  selectedDecoration: BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // 3. VÄLJ TID
            const Text(
              "3. Vilken tid?",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      startTime == null ? "Start" : _formatTime(startTime),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                const Icon(Icons.arrow_forward, color: Colors.white24),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(Icons.access_time_filled),
                    label: Text(
                      endTime == null ? "Slut" : _formatTime(endTime),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // SPARA KNAPP
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _saveShift,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "SPARA ARBETSPASS",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
