import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_theme.dart';
import 'personal_countdown_screen.dart';
import 'screen_rules_page.dart'; // <--- VIKTIGT: Se till att du skapat denna fil!

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _showOnlyMine = false;
  String? _currentUserName;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('sv', null);
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _currentUserEmail = user.email);
      var snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty && mounted) {
        setState(() => _currentUserName = snapshot.docs.first['name']);
      }
    }
  }

  String _getDateKey(DateTime date) => "${date.year}-${date.month}-${date.day}";

  Color _getEventColor(String title, String type) {
    String t = title.toLowerCase();
    if (t.contains('läkare') ||
        t.contains('tand') ||
        t.contains('bup') ||
        t.contains('sjukhus'))
      return Colors.redAccent;
    if (t.contains('skola') || t.contains('läxa') || t.contains('prov'))
      return Colors.purpleAccent;
    if (type == 'work' || t.contains('jobb')) return Colors.blue;
    if (type == 'food') return Colors.orange;
    return Colors.pinkAccent;
  }

  void _showEnergyDialog(String docId, String currentName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Hur mår du, $currentName?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _energyOption(
                docId,
                4,
                "Toppen!",
                Icons.battery_full_rounded,
                Colors.green,
              ),
              _energyOption(
                docId,
                3,
                "Helt okej",
                Icons.battery_5_bar_rounded,
                Colors.lightGreen,
              ),
              _energyOption(
                docId,
                2,
                "Lite trött",
                Icons.battery_3_bar_rounded,
                Colors.orangeAccent,
              ),
              _energyOption(
                docId,
                1,
                "Slut på batteri",
                Icons.battery_alert_rounded,
                Colors.redAccent,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _energyOption(
    String docId,
    int level,
    String label,
    IconData icon,
    Color color,
  ) {
    return ListTile(
      leading: Icon(icon, color: color, size: 30),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: () {
        FirebaseFirestore.instance.collection('users').doc(docId).update({
          'energy': level,
        });
        Navigator.pop(context);
      },
    );
  }

  void _showStartmotorDialog(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    List substeps = data['substeps'] ?? [];
    String choreTitle = data['chore'] ?? 'Syssla';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(
                    Icons.rocket_launch_rounded,
                    color: Colors.orange,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      choreTitle,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "Ta ett litet steg i taget. Du klarar det!",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 20),
              const Divider(),
              Expanded(
                child: substeps.isEmpty
                    ? const Center(
                        child: Text("Inga delsteg inlagda. Bara kör! 🚀"),
                      )
                    : ListView.builder(
                        itemCount: substeps.length,
                        itemBuilder: (context, index) {
                          var step = substeps[index];
                          bool isDone = step['isDone'] ?? false;
                          return CheckboxListTile(
                            title: Text(
                              step['title'],
                              style: TextStyle(
                                decoration: isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isDone ? Colors.grey : Colors.black87,
                              ),
                            ),
                            value: isDone,
                            activeColor: Colors.green,
                            onChanged: (val) async {
                              List newSteps = List.from(substeps);
                              newSteps[index]['isDone'] = val;
                              bool allDone = newSteps.every(
                                (s) => s['isDone'] == true,
                              );
                              await FirebaseFirestore.instance
                                  .collection('chores')
                                  .doc(doc.id)
                                  .update({
                                    'substeps': newSteps,
                                    if (allDone) 'isDone': true,
                                  });
                              if (allDone && mounted)
                                Navigator.pop(context);
                              else {
                                Navigator.pop(context);
                                _showStartmotorDialog(
                                  await FirebaseFirestore.instance
                                      .collection('chores')
                                      .doc(doc.id)
                                      .get(),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String todayDate = DateFormat(
      'EEEE d MMMM',
      'sv',
    ).format(DateTime.now());
    final String capitalizedDate =
        todayDate.substring(0, 1).toUpperCase() + todayDate.substring(1);
    Color textColor = AppTheme.getTextColor();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Idag",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: textColor,
              ),
            ),
            Text(
              capitalizedDate,
              style: TextStyle(fontSize: 14, color: AppTheme.getSubTextColor()),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Text(
                "Visa bara mina",
                style: TextStyle(fontSize: 12, color: textColor),
              ),
              Switch(
                value: _showOnlyMine,
                activeColor: Colors.black87,
                activeTrackColor: Colors.white,
                onChanged: (val) => setState(() => _showOnlyMine = val),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.getBackground(),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader("Familjens Energi"),
                  _buildEnergyBar(),
                  const SizedBox(height: 20),

                  _sectionHeader("Dagens Mat"),
                  _buildFoodCard(),
                  const SizedBox(height: 20),

                  _sectionHeader("På Schemat"),
                  _buildScheduleList(),
                  const SizedBox(height: 20),

                  // --- HÄR ÄR DE NYA KNAPPARNA (Timer & Skärmtid) ---
                  _sectionHeader("Verktyg"),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.timer, size: 22),
                          label: const Text("Timer"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.9),
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PersonalCountdownScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.videogame_asset, size: 22),
                          label: const Text("Skärmregler"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.9),
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ScreenRulesPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _sectionHeader("Att göra"),
                  _buildChoresList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0, left: 4),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.getTextColor(),
      ),
    ),
  );

  Widget _buildEnergyBar() {
    return SizedBox(
      height: 90,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          var users = snapshot.data!.docs;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: users.length,
            itemBuilder: (context, index) {
              var data = users[index].data() as Map;
              String name = data['name'] ?? "?";
              String email = data['email'] ?? "";
              String colorHex = data['color'] ?? 'ff2196f3';
              int energy = data['energy'] ?? 3;
              IconData batteryIcon;
              Color batteryColor;
              switch (energy) {
                case 4:
                  batteryIcon = Icons.battery_full_rounded;
                  batteryColor = Colors.green;
                  break;
                case 2:
                  batteryIcon = Icons.battery_3_bar_rounded;
                  batteryColor = Colors.orangeAccent;
                  break;
                case 1:
                  batteryIcon = Icons.battery_alert_rounded;
                  batteryColor = Colors.redAccent;
                  break;
                default:
                  batteryIcon = Icons.battery_5_bar_rounded;
                  batteryColor = Colors.lightGreen;
              }
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: GestureDetector(
                  onTap: () {
                    if (email == _currentUserEmail)
                      _showEnergyDialog(users[index].id, name);
                  },
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Color(
                              int.parse(colorHex, radix: 16),
                            ),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : "?",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                batteryIcon,
                                color: batteryColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.getTextColor(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFoodCard() {
    final String dateKey = _getDateKey(DateTime.now());
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('planner_events')
          .where('date', isEqualTo: dateKey)
          .where('type', isEqualTo: 'food')
          .snapshots(),
      builder: (context, snapshot) {
        String foodText = "Inget bestämt än";
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty)
          foodText =
              (snapshot.data!.docs.first.data() as Map)['title'] ??
              "Inget bestämt än";
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.getCardColor(),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              const Icon(Icons.restaurant, color: Colors.orangeAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  foodText,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: AppTheme.getTextColor(),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScheduleList() {
    final String dateKey = _getDateKey(DateTime.now());
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('planner_events')
          .where('date', isEqualTo: dateKey)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        var docs = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map;
          if (data['type'] == 'food') return false;
          if (_showOnlyMine && _currentUserName != null)
            return data['title'].toString().contains(_currentUserName!);
          return true;
        }).toList();
        if (docs.isEmpty)
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.getCardColor(),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              "Inget mer på schemat idag.",
              style: TextStyle(color: AppTheme.getSubTextColor()),
            ),
          );
        docs.sort(
          (a, b) =>
              (a.data() as Map)['time'].compareTo((b.data() as Map)['time']),
        );
        return Column(
          children: docs.map((doc) {
            var data = doc.data() as Map;
            Color eventColor = _getEventColor(data['title'], data['type']);
            IconData eventIcon = AppTheme.getEventIcon(
              data['title'],
              data['type'],
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.getCardColor(),
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: eventColor, width: 4)),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: eventColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(eventIcon, color: eventColor, size: 20),
                ),
                title: Text(
                  data['title'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.getTextColor(),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: data['time'] != ""
                    ? Text(
                        data['time'],
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.getSubTextColor(),
                        ),
                      )
                    : null,
                dense: true,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildChoresList() {
    final String dateKey = _getDateKey(DateTime.now());
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chores')
          .where('date', isEqualTo: dateKey)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        var docs = snapshot.data!.docs;
        if (_showOnlyMine && _currentUserName != null)
          docs = docs
              .where(
                (doc) => (doc.data() as Map)['who'].contains(_currentUserName!),
              )
              .toList();
        if (docs.isEmpty)
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _showOnlyMine
                  ? "Du har inga sysslor idag."
                  : "Inga sysslor inlagda idag.",
              style: TextStyle(color: AppTheme.getSubTextColor()),
            ),
          );
        docs.sort((a, b) {
          bool doneA = (a.data() as Map)['isDone'] ?? false;
          bool doneB = (b.data() as Map)['isDone'] ?? false;
          return doneA == doneB ? 0 : (doneA ? 1 : -1);
        });
        return Column(
          children: docs.map((doc) {
            var data = doc.data() as Map;
            bool isDone = data['isDone'] ?? false;
            Color whoColor = Color(
              int.parse(data['whoColor'] ?? 'ff000000', radix: 16),
            );
            List substeps = data['substeps'] ?? [];
            int doneSteps = substeps.where((s) => s['isDone'] == true).length;
            return GestureDetector(
              onTap: () {
                _showStartmotorDialog(doc);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isDone
                      ? Colors.white.withOpacity(0.2)
                      : AppTheme.getCardColor(),
                  borderRadius: BorderRadius.circular(12),
                  border: isDone
                      ? null
                      : Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1,
                        ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isDone ? Colors.grey : whoColor,
                    radius: 16,
                    child: Text(
                      data['who'].isNotEmpty
                          ? data['who'][0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    data['chore'],
                    style: TextStyle(
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      color: isDone ? Colors.black38 : AppTheme.getTextColor(),
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: substeps.isNotEmpty
                      ? Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: doneSteps / substeps.length,
                                  backgroundColor: Colors.grey[300],
                                  color: Colors.green,
                                  minHeight: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "$doneSteps/${substeps.length}",
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.getSubTextColor(),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          data['who'],
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.getSubTextColor(),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: Checkbox(
                    value: isDone,
                    activeColor: Colors.black87,
                    onChanged: (val) => FirebaseFirestore.instance
                        .collection('chores')
                        .doc(doc.id)
                        .update({'isDone': val}),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
