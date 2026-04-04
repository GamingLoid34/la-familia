import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_theme.dart';

class ScreenRulesPage extends StatefulWidget {
  const ScreenRulesPage({super.key});

  @override
  State<ScreenRulesPage> createState() => _ScreenRulesPageState();
}

class _ScreenRulesPageState extends State<ScreenRulesPage> {
  Future<void> _updateTime(String docId, TimeOfDay limit) async {
    await FirebaseFirestore.instance
        .collection('screen_rules')
        .doc(docId)
        .update({'limitHour': limit.hour, 'limitMinute': limit.minute});
  }

  Future<void> _toggleAllowed(String docId, bool current) async {
    await FirebaseFirestore.instance
        .collection('screen_rules')
        .doc(docId)
        .update({'isAllowed': !current});
  }

  Future<void> _selectTime(String docId, int hour, int minute) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            timePickerTheme: TimePickerThemeData(
              dialHandColor: Colors.orange,
              hourMinuteTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.orange
                    : Colors.black,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      await _updateTime(docId, picked);
    }
  }

  void _addRuleDialog() {
    final _appNameCtrl = TextEditingController();
    final _memberCtrl = TextEditingController();
    bool _isAllowed = true;
    TimeOfDay _limit = const TimeOfDay(hour: 0, minute: 0);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateBuilder) {
            return AlertDialog(
              title: const Text('Ny Skärmregel'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _appNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'App Namn (ex. Roblox)',
                    ),
                  ),
                  TextField(
                    controller: _memberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tilldelad (Namn)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tidsgräns:'),
                      TextButton(
                        onPressed: () async {
                          final TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime: _limit,
                          );
                          if (picked != null) {
                            setStateBuilder(() => _limit = picked);
                          }
                        },
                        child: Text(
                          '${_limit.hour.toString().padLeft(2, '0')}:${_limit.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tillåten?'),
                      Switch(
                        value: _isAllowed,
                        activeColor: Colors.green,
                        onChanged: (val) =>
                            setStateBuilder(() => _isAllowed = val),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_appNameCtrl.text.isNotEmpty) {
                      FirebaseFirestore.instance.collection('screen_rules').add(
                        {
                          'appName': _appNameCtrl.text,
                          'icon': 'games_rounded', // Default icon string
                          'limitHour': _limit.hour,
                          'limitMinute': _limit.minute,
                          'isAllowed': _isAllowed,
                          'memberId': _memberCtrl.text,
                        },
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Spara'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'play_circle_filled':
        return Icons.play_circle_filled;
      case 'music_note_rounded':
        return Icons.music_note_rounded;
      case 'sports_esports':
        return Icons.sports_esports;
      case 'games_rounded':
      default:
        return Icons.games_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Skärmtider & Regler",
          style: TextStyle(
            color: AppTheme.getTextColor(),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.getTextColor()),
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
        decoration: AppTheme.getBackground(),
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('screen_rules')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Fel: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red)),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Inga regler inlagda ännu.",
                        style: TextStyle(
                          color: AppTheme.getSubTextColor(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _addRuleDialog,
                        child: const Text('Lägg till appregel'),
                      ),
                    ],
                  ),
                );
              }

              var docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var doc = docs[index];
                  var data = doc.data() as Map;

                  String appName = data['appName'] ?? 'App';
                  String iconKey = data['icon'] ?? 'games_rounded';
                  int limitHour = data['limitHour'] ?? 0;
                  int limitMinute = data['limitMinute'] ?? 0;
                  bool isAllowed = data['isAllowed'] ?? false;
                  String memberId = data['memberId'] ?? '';

                  String timeString =
                      "${limitHour.toString().padLeft(2, '0')}:${limitMinute.toString().padLeft(2, '0')}";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.getCardColor(),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isAllowed
                              ? Colors.green.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getIconData(iconKey),
                          color: isAllowed
                              ? Colors.green[800]
                              : Colors.red[800],
                          size: 30,
                        ),
                      ),
                      title: Text(
                        appName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppTheme.getTextColor(),
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            "För: $memberId",
                            style: TextStyle(
                              color: AppTheme.getSubTextColor(),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () =>
                                _selectTime(doc.id, limitHour, limitMinute),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  timeString,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      trailing: Switch(
                        value: isAllowed,
                        activeColor: Colors.green,
                        onChanged: (val) => _toggleAllowed(doc.id, isAllowed),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ))),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRuleDialog,
        backgroundColor: Colors.white,
        child: const Icon(Icons.add, color: Colors.black87),
      ),
    );
  }
}

