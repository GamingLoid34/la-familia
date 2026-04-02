import 'package:flutter/material.dart';
import '../app_theme.dart'; // För att få våra färger

class ScreenRulesPage extends StatefulWidget {
  const ScreenRulesPage({super.key});

  @override
  State<ScreenRulesPage> createState() => _ScreenRulesPageState();
}

class _ScreenRulesPageState extends State<ScreenRulesPage> {
  // Vi simulerar att detta sparas i Firebase senare
  final List<Map<String, dynamic>> _apps = [
    {'name': 'YouTube', 'icon': Icons.play_circle_filled, 'limit': const TimeOfDay(hour: 18, minute: 0), 'isOpen': true},
    {'name': 'Roblox', 'icon': Icons.games_rounded, 'limit': const TimeOfDay(hour: 19, minute: 30), 'isOpen': true},
    {'name': 'TikTok', 'icon': Icons.music_note_rounded, 'limit': const TimeOfDay(hour: 20, minute: 0), 'isOpen': true},
    {'name': 'Fortnite', 'icon': Icons.sports_esports, 'limit': const TimeOfDay(hour: 17, minute: 0), 'isOpen': false}, // T.ex. avstängd helt
  ];

  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _apps[index]['limit'],
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            timePickerTheme: TimePickerThemeData(
              dialHandColor: Colors.orange,
              hourMinuteTextColor: MaterialStateColor.resolveWith((states) => states.contains(MaterialState.selected) ? Colors.orange : Colors.black),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _apps[index]['limit'] = picked;
      });
      // Här skulle vi spara till Firebase: "updateScreenTime(...)"
    }
  }

  @override
  Widget build(BuildContext context) {
    // Använd dagens färg för bakgrunden
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Skärmtider & Regler", style: TextStyle(color: AppTheme.getTextColor(), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.getTextColor()),
      ),
      body: Container(
        decoration: AppTheme.getBackground(), // Vår gradient-bakgrund
        child: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _apps.length,
            itemBuilder: (context, index) {
              final app = _apps[index];
              final TimeOfDay limit = app['limit'];
              final String timeString = "${limit.hour.toString().padLeft(2, '0')}:${limit.minute.toString().padLeft(2, '0')}";
              final bool isAllowed = app['isOpen'];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.getCardColor(), // Vår Glassmorphism
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isAllowed ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      app['icon'], 
                      color: isAllowed ? Colors.green[800] : Colors.red[800], 
                      size: 30
                    ),
                  ),
                  title: Text(
                    app['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppTheme.getTextColor(),
                    ),
                  ),
                  subtit