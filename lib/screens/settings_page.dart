import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/family_service.dart';
import '../services/user_service.dart';
import 'manage_members_page.dart';
import 'invite_page.dart';
import 'screen_rules_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  UserModel? _currentUser;
  List<UserModel> _familyMembers = [];
  String? _familyName;
  bool _loading = true;

  List<Map<String, dynamic>> _calendarImports = [];

  // Notification toggles (local state only — extend with Firestore as needed)
  bool _notifActivity = true;
  bool _notifChore = true;
  bool _notifReward = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await FamilyService.getCurrentUserModel()
          .timeout(const Duration(seconds: 6));
      final members = <UserModel>[];
      String? familyName;
      if (user?.familyId != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('familyId', isEqualTo: user!.familyId)
            .get()
            .timeout(const Duration(seconds: 6));
        for (final d in snap.docs) {
          members.add(UserModel.fromMap(d.id, d.data()));
        }
        try {
          final famDoc = await FirebaseFirestore.instance
              .collection('families')
              .doc(user.familyId)
              .get()
              .timeout(const Duration(seconds: 4));
          if (famDoc.exists) {
            familyName = famDoc.data()?['name'] as String?;
          }
        } catch (_) {
          // Family name is optional — ignore timeout
        }
        try {
          final impsSnap = await FirebaseFirestore.instance
              .collection('calendar_imports')
              .where('familyId', isEqualTo: user.familyId)
              .get()
              .timeout(const Duration(seconds: 4));
          for (final d in impsSnap.docs) {
            _calendarImports.add({...d.data(), 'id': d.id});
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _currentUser = user;
          _familyMembers = members;
          _familyName = familyName;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Settings _loadData error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeViewMode(String mode) async {
    final uid = _currentUser?.uid;
    if (uid == null) return;
    await UserService.updateViewMode(uid, mode);
    await _loadData();
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dayColor = AppTheme.getDayAccentColor();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: AppTheme.getBackground(),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(dayColor)),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(child: _buildProfileCard(dayColor)),
                  SliverToBoxAdapter(child: _buildFamilyCard(dayColor)),
                  SliverToBoxAdapter(child: _buildCalendarCard(dayColor)),
                  SliverToBoxAdapter(child: _buildNotificationsCard(dayColor)),
                  SliverToBoxAdapter(child: _buildAboutCard()),
                  SliverToBoxAdapter(child: _buildSignOutButton()),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(Color dayColor) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: BoxDecoration(
        color: dayColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
      child: Text('Inställningar',
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
    );
  }

  // ─── PROFILE CARD ────────────────────────────────────────────────────────────
  Widget _buildProfileCard(Color dayColor) {
    if (_currentUser == null) return const SizedBox.shrink();
    final user = _currentUser!;
    Color avatarColor;
    try {
      avatarColor = Color(user.colorValue as int);
    } catch (_) {
      avatarColor = dayColor;
    }
    
    final roleLabel = switch (user.role) {
      'parent' || 'admin' => 'Förälder',
      'child' => 'Barn',
      'youth' => 'Ungdom',
      _ => 'Familjemedlem',
    };

    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: avatarColor,
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                _Badge(label: roleLabel, color: dayColor),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Text('VIS-LÄGE', style: AppTheme.sectionLabelStyle),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'parent',
                    label: Text('Förälder', style: TextStyle(fontSize: 12))),
                ButtonSegment(
                    value: 'focus',
                    label: Text('Fokus', style: TextStyle(fontSize: 12))),
                ButtonSegment(
                    value: 'youth',
                    label: Text('Ungdom', style: TextStyle(fontSize: 12))),
              ],
              selected: {user.viewMode},
              onSelectionChanged: (s) { if (s.isNotEmpty) _changeViewMode(s.first); },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return dayColor;
                  return null;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return AppTheme.getTextColor();
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── FAMILY CARD ─────────────────────────────────────────────────────────────
  Widget _buildFamilyCard(Color dayColor) {
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.people_rounded, color: dayColor, size: 20),
          const SizedBox(width: 8),
          Text(
            _familyName ?? 'Familj',
            style: AppTheme.cardTitleStyle,
          ),
        ]),
        const SizedBox(height: 16),
        if (_familyMembers.isNotEmpty) ...[
          SizedBox(
            height: 64,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _familyMembers.length,
              itemBuilder: (_, i) {
                final m = _familyMembers[i];
                Color mc;
                try {
                  mc = Color(m.colorValue as int);
                } catch (_) {
                  mc = dayColor;
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: mc,
                      child: Text(
                        m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(m.name.split(' ').first,
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w500)),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(Icons.group_rounded, size: 16, color: dayColor),
              label: Text('Hantera familj',
                  style: TextStyle(color: dayColor, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const ManageMembersPage())),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('Bjud in', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: dayColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const InvitePage())),
            ),
          ),
        ]),
      ]),
    );
  }

  // ─── CALENDAR SOURCES ────────────────────────────────────────────────────────
  Widget _buildCalendarCard(Color dayColor) {
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.calendar_month_rounded, color: dayColor, size: 20),
          const SizedBox(width: 8),
          Text('Kalenderimport', style: AppTheme.cardTitleStyle),
        ]),
        const SizedBox(height: 8),
        Text('Importera händelser från Google Kalender, Outlook eller Apple Kalender.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        if (_calendarImports.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final imp in _calendarImports)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: dayColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(imp['name'] as String? ?? 'Kalender',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                Text('${imp['eventCount'] ?? 0} händelser',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _deleteCalendarImport(imp['id'] as String),
                  child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400),
                ),
              ]),
            ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: Icon(Icons.add_rounded, color: dayColor),
          label: Text('Lägg till kalender', style: TextStyle(color: dayColor)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _showAddCalendarDialog,
        ),
      ]),
    );
  }

  // ─── CALENDAR IMPORT LOGIC ───────────────────────────────────────────────────

  void _showAddCalendarDialog() {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool loading = false;
    String? errorMsg;

    showDialog(
      context: context,
      barrierDismissible: !loading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Lägg till kalender'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Kalendernamn',
                      hintText: 'T.ex. Mammas kalender',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Alternativ 1 — ICS-länk:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: urlCtrl,
                    decoration: InputDecoration(
                      labelText: 'ICS-URL',
                      hintText: 'https://calendar.google.com/calendar/ical/...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Hämta från URL'),
                      onPressed: loading
                          ? null
                          : () async {
                              final url = urlCtrl.text.trim();
                              final name = nameCtrl.text.trim().isEmpty
                                  ? 'Importerad kalender'
                                  : nameCtrl.text.trim();
                              if (url.isEmpty) return;
                              setS(() { loading = true; errorMsg = null; });
                              try {
                                final resp = await http.get(Uri.parse(url))
                                    .timeout(const Duration(seconds: 10));
                                final content = utf8.decode(resp.bodyBytes);
                                final count = await _parseAndSaveIcs(content, name, url);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _showImportResult(count, name);
                                await _loadData();
                              } catch (e) {
                                setS(() {
                                  loading = false;
                                  errorMsg =
                                      'Kunde inte hämta URL. Prova att ladda upp filen direkt istället.';
                                });
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Alternativ 2 — Ladda upp .ics-fil:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Välj .ics-fil'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.getDayAccentColor(),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: loading
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim().isEmpty
                                  ? 'Importerad kalender'
                                  : nameCtrl.text.trim();
                              setS(() { loading = true; errorMsg = null; });
                              try {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['ics'],
                                  withData: true,
                                );
                                if (result == null || result.files.isEmpty) {
                                  setS(() => loading = false);
                                  return;
                                }
                                final bytes = result.files.first.bytes;
                                if (bytes == null) {
                                  setS(() { loading = false; errorMsg = 'Kunde inte läsa filen.'; });
                                  return;
                                }
                                final content = utf8.decode(bytes);
                                final count = await _parseAndSaveIcs(content, name, '');
                                if (ctx.mounted) Navigator.pop(ctx);
                                _showImportResult(count, name);
                                await _loadData();
                              } catch (e) {
                                setS(() { loading = false; errorMsg = 'Fel: $e'; });
                              }
                            },
                    ),
                  ),
                  if (loading) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportResult(int count, String name) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count > 0
          ? '$count händelser importerade från "$name"! 📅'
          : 'Inga kommande händelser hittades i "$name".'),
      backgroundColor: count > 0 ? const Color(0xFF6BAE75) : Colors.orange,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _deleteCalendarImport(String docId) async {
    await FirebaseFirestore.instance
        .collection('calendar_imports')
        .doc(docId)
        .delete();
    if (mounted) setState(() => _calendarImports.removeWhere((m) => m['id'] == docId));
  }

  Future<int> _parseAndSaveIcs(String icsContent, String name, String url) async {
    // Unfold continuation lines
    final raw = icsContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final lines = <String>[];
    for (final line in raw) {
      if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] += line.substring(1);
      } else {
        lines.add(line);
      }
    }

    final events = <Map<String, String>>[];
    Map<String, String>? current;
    for (final line in lines) {
      final t = line.trim();
      if (t == 'BEGIN:VEVENT') {
        current = {};
      } else if (t == 'END:VEVENT' && current != null) {
        events.add(current);
        current = null;
      } else if (current != null) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          final keyRaw = line.substring(0, idx);
          final val = line.substring(idx + 1).trim();
          final key = keyRaw.split(';')[0].toUpperCase();
          current[key] = val;
        }
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final familyId = _currentUser?.familyId ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (final ev in events) {
      final title = _decodeIcsText(ev['SUMMARY'] ?? '');
      if (title.isEmpty) continue;
      final dtStart = _parseDtstart(ev['DTSTART']);
      if (dtStart == null) continue;
      if (dtStart.isBefore(today)) continue;
      if (count >= 200) break;

      final ref = FirebaseFirestore.instance.collection('planner_events').doc();
      batch.set(ref, {
        'title': title,
        'piktogram': '📅',
        'type': 'activity',
        'date': '${dtStart.year}-${dtStart.month}-${dtStart.day}',
        'time': dtStart.hour == 0 && dtStart.minute == 0
            ? ''
            : '${dtStart.hour.toString().padLeft(2, '0')}:${dtStart.minute.toString().padLeft(2, '0')}',
        'persons': <String>[],
        'checklist': <dynamic>[],
        'source': 'calendar',
        'calendarName': name,
        'createdBy': uid,
        'isPending': false,
        'familyId': familyId,
      });
      count++;
    }

    if (count > 0) await batch.commit();

    await FirebaseFirestore.instance.collection('calendar_imports').add({
      'name': name,
      'url': url,
      'familyId': familyId,
      'lastSync': FieldValue.serverTimestamp(),
      'eventCount': count,
      'source': url.isEmpty ? 'file' : 'url',
    });

    return count;
  }

  String _decodeIcsText(String text) => text
      .replaceAll('\\n', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  DateTime? _parseDtstart(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final clean = value.replaceAll('Z', '').trim();
      if (clean.length < 8) return null;
      final y = int.parse(clean.substring(0, 4));
      final m = int.parse(clean.substring(4, 6));
      final d = int.parse(clean.substring(6, 8));
      int h = 0, min = 0;
      if (clean.length >= 15 && clean[8] == 'T') {
        h = int.parse(clean.substring(9, 11));
        min = int.parse(clean.substring(11, 13));
      }
      return DateTime(y, m, d, h, min);
    } catch (_) {
      return null;
    }
  }

  // ─── NOTIFICATIONS CARD ──────────────────────────────────────────────────────
  Widget _buildNotificationsCard(Color dayColor) {
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.notifications_rounded, color: dayColor, size: 20),
          const SizedBox(width: 8),
          Text('Aviseringar', style: AppTheme.cardTitleStyle),
        ]),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Aktivitet börjar snart',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: const Text('15 min innan',
              style: TextStyle(fontSize: 12)),
          value: _notifActivity,
          activeColor: dayColor,
          onChanged: (v) => setState(() => _notifActivity = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Syssla tilldelad',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          value: _notifChore,
          activeColor: dayColor,
          onChanged: (v) => setState(() => _notifChore = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Belöning godkänd',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          value: _notifReward,
          activeColor: dayColor,
          onChanged: (v) => setState(() => _notifReward = v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.phone_android_rounded, color: dayColor),
          title: const Text('Skärmtidsregler',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          trailing: Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: Colors.grey.shade400),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScreenRulesPage())),
        ),
      ]),
    );
  }

  // ─── ABOUT CARD ──────────────────────────────────────────────────────────────
  Widget _buildAboutCard() {
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(children: [
        Image.asset(
          'assets/images/logo.png',
          width: 72,
          fit: BoxFit.contain,
          errorBuilder: (_, __, e) =>
              const Icon(Icons.favorite_rounded, size: 48, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        Text('La Familia',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Version 1.0.0',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        const SizedBox(height: 2),
        Text('Skapad av Valladares',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ]),
    );
  }

  // ─── SIGN OUT ────────────────────────────────────────────────────────────────
  Widget _buildSignOutButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.logout_rounded, color: Colors.red),
          label: const Text('Logga ut',
              style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _signOut,
        ),
      ),
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  const _Card({required this.child, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.cardDecoration(radius: 20),
        child: child,
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      );
}