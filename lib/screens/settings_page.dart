import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../utils/layout.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/family_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/user_service.dart';
import '../widgets/ai_planner_sheet.dart';
import '../widgets/food_prefs_sheet.dart';
import '../widgets/home_location_sheet.dart';
import 'invite_page.dart';
import 'manage_members_page.dart';
import 'verktyg_page.dart';

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
  double? _homeLat;
  double? _homeLon;
  String? _homeName;
  List<String> _foodAllergier = [];
  List<String> _foodOgillar = [];
  List<String> _foodGillar = [];
  bool _loading = true;

  // Notification toggles
  bool _notifActivity = true;
  bool _notifChore = true;
  bool _notifTransition = true;
  bool _notifStart = false;
  bool _notifFamily = true;
  bool _aiPlannerLoading = false;
  int _devClickCount = 0;
  bool _devMode = false;

  // Notisdiagnostik
  bool _enablingWebPush = false;
  bool _webRemindersEnabled = true;
  bool _diagExpanded = false;
  bool _diagLoading = false;
  bool _sendingTestPush = false;
  bool _schedulingLocalTest = false;
  bool? _diagNotifsEnabled;
  bool? _diagExactAlarmsEnabled;
  bool? _diagBatteryExempt;
  List<PendingNotificationRequest> _diagPending = [];
  String? _diagDeviceToken;
  bool _diagTokenRegistered = false;
  bool _diagIsBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadData();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifActivity = prefs.getBool('notifActivity') ?? true;
      _notifChore = prefs.getBool('notifChore') ?? true;
      _notifTransition = prefs.getBool('notifTransition') ?? true;
      _notifStart = prefs.getBool('notifStart') ?? false;
      _notifFamily = prefs.getBool('notifFamily') ?? true;
      _devMode = prefs.getBool('dev_mode_enabled') ?? false;
    });
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
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
            final fd = famDoc.data();
            familyName = fd?['name'] as String?;
            _homeLat = (fd?['homeLat'] as num?)?.toDouble();
            _homeLon = (fd?['homeLon'] as num?)?.toDouble();
            _homeName = fd?['homeName'] as String?;
            final prefs = fd?['foodPrefs'];
            if (prefs is Map) {
              _foodAllergier = (prefs['allergier'] as List?)
                      ?.whereType<String>()
                      .toList() ??
                  [];
              _foodOgillar = (prefs['ogillar'] as List?)
                      ?.whereType<String>()
                      .toList() ??
                  [];
              _foodGillar = (prefs['gillar'] as List?)
                      ?.whereType<String>()
                      .toList() ??
                  [];
            } else {
              _foodAllergier = [];
              _foodOgillar = [];
              _foodGillar = [];
            }
          }
        } catch (e, stack) {
          developer.log('Misslyckades hämta familjenamn', error: e, stackTrace: stack);
        }
      }
      bool webReminders = true;
      if (user != null) {
        try {
          final uDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 4));
          if (uDoc.exists) {
            webReminders = uDoc.data()?['webRemindersEnabled'] as bool? ?? true;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _currentUser = user;
          _familyMembers = members;
          _familyName = familyName;
          _webRemindersEnabled = webReminders;
          _loading = false;
        });
      }
    } catch (e, stack) {
      developer.log('Settings _loadData error', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeViewMode(String mode) async {
    final uid = _currentUser?.uid;
    if (uid == null) return;
    await UserService.updateViewMode(uid, mode);
    await _loadData();
  }

  /// Full vy (parent/youth/child i data) visas som ”Allt”; avskalad vy som ”Fokus”.
  Widget _buildViewModeControl(UserModel user, Color dayColor) {
    final segments = <ButtonSegment<String>>[];
    if (user.isParent) {
      segments.addAll(const [
        ButtonSegment<String>(
            value: 'parent',
            label: Text('Allt', style: TextStyle(fontSize: 12))),
        ButtonSegment<String>(
            value: 'focus',
            label: Text('Fokus', style: TextStyle(fontSize: 12))),
      ]);
    } else if (user.role == 'youth') {
      segments.addAll(const [
        ButtonSegment<String>(
            value: 'youth',
            label: Text('Allt', style: TextStyle(fontSize: 12))),
        ButtonSegment<String>(
            value: 'focus',
            label: Text('Fokus', style: TextStyle(fontSize: 12))),
      ]);
    } else {
      segments.addAll(const [
        ButtonSegment<String>(
            value: 'child',
            label: Text('Allt', style: TextStyle(fontSize: 12))),
        ButtonSegment<String>(
            value: 'focus',
            label: Text('Fokus', style: TextStyle(fontSize: 12))),
      ]);
    }

    var selected = user.viewMode;
    final allowed = segments.map((s) => s.value).toSet();
    if (!allowed.contains(selected)) {
      selected = segments.first.value;
    }

    return SegmentedButton<String>(
      segments: segments,
      selected: {selected},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) _changeViewMode(s.first);
      },
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
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dayColor = AppTheme.getDayAccentColor();
    final maxW = WindowSize.of(context).isExpanded
        ? WindowSize.settingsMaxWidth
        : 430.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            decoration: AppTheme.getBackground(),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, dayColor)),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(child: _buildVerktygCard(dayColor)),
                  SliverToBoxAdapter(child: _buildProfileCard(dayColor)),
                  SliverToBoxAdapter(child: _buildFamilyCard(dayColor)),
                  SliverToBoxAdapter(child: _buildFoodPrefsCard(dayColor)),
                  SliverToBoxAdapter(child: _buildHomeLocationCard(dayColor)),
                  SliverToBoxAdapter(child: _buildNotificationsCard(dayColor)),
                  SliverToBoxAdapter(child: _buildViewModeCard(dayColor)),
                  SliverToBoxAdapter(child: _buildSignOutButton()),
                  SliverToBoxAdapter(child: _buildAboutCard()),
                  if (_devMode)
                    SliverToBoxAdapter(child: _buildDevSection(dayColor)),
                ],
                SliverToBoxAdapter(
                    child: SizedBox(height: navSafeBottom(context).bottom + 20)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, Color dayColor) {
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context),
      child: Text('Inställningar',
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
    );
  }

  // ─── VERKTYG CARD ───────────────────────────────────────────────────────────
  Widget _buildVerktygCard(Color dayColor) {
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: dayColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text('🧰', style: TextStyle(fontSize: 22)),
        ),
        title: const Text(
          'Verktyg 🧰',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: const Text(
          'Timer, inköp, matsedel, lathund & scheman',
          style: TextStyle(fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: dayColor),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VerktygPage()),
        ),
      ),
    );
  }

  // ─── PROFILE CARD ────────────────────────────────────────────────────────────
  Widget _buildProfileCard(Color dayColor) {
    if (_currentUser == null) return const SizedBox.shrink();
    final user = _currentUser!;
    Color avatarColor;
    try {
      avatarColor = Color(user.colorValue);
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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(children: [
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
    );
  }

  // ─── FAMILY CARD ─────────────────────────────────────────────────────────────
  Widget _buildFamilyCard(Color dayColor) {
    if (_currentUser != null && !_currentUser!.isParent) {
      return const SizedBox.shrink();
    }
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
                  mc = Color(m.colorValue);
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

  // ─── FOOD PREFS CARD ─────────────────────────────────────────────────────────
  Widget _buildFoodPrefsCard(Color dayColor) {
    if (_currentUser != null && !_currentUser!.isParent) {
      return const SizedBox.shrink();
    }
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.restaurant_menu_rounded, color: dayColor, size: 24),
        title: const Text('Matpreferenser',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          [
            if (_foodAllergier.isNotEmpty)
              'Allergier: ${_foodAllergier.join(', ')}',
            if (_foodOgillar.isNotEmpty) 'Ogillar: ${_foodOgillar.length}',
            if (_foodGillar.isNotEmpty) 'Gillar: ${_foodGillar.length}',
          ].isEmpty
              ? 'Allergier, ogillar, gillar — för AI-menyn'
              : [
                  if (_foodAllergier.isNotEmpty)
                    'Allergier: ${_foodAllergier.join(', ')}',
                  if (_foodOgillar.isNotEmpty)
                    'Ogillar: ${_foodOgillar.length}',
                  if (_foodGillar.isNotEmpty) 'Gillar: ${_foodGillar.length}',
                ].join(' · '),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: dayColor),
        onTap: _currentUser?.familyId == null
            ? null
            : () => showFoodPrefsSheet(
                  context,
                  familyId: _currentUser!.familyId!,
                  allergier: _foodAllergier,
                  ogillar: _foodOgillar,
                  gillar: _foodGillar,
                  onSaved: _loadData,
                ),
      ),
    );
  }

  // ─── HOME LOCATION CARD ──────────────────────────────────────────────────────
  Widget _buildHomeLocationCard(Color dayColor) {
    if (_currentUser != null && !_currentUser!.isParent) {
      return const SizedBox.shrink();
    }
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.home_work_outlined, color: dayColor, size: 24),
        title: const Text('Hemposition',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          _homeName ?? 'Ej angiven — behövs för väder',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: dayColor),
        onTap: _currentUser?.familyId == null
            ? null
            : () => showHomeLocationSheet(
                  context,
                  familyId: _currentUser!.familyId!,
                  currentName: _homeName,
                  currentLat: _homeLat,
                  currentLon: _homeLon,
                  onSaved: _loadData,
                ),
      ),
    );
  }

  Future<void> _testAiPlanner() async {
    setState(() => _aiPlannerLoading = true);
    try {
      await runAiPlannerFlow(context);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? 'Kunde inte hämta AI-förslag.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte hämta AI-förslag: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _aiPlannerLoading = false);
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
        if (kIsWeb) ...[
          Text(
            'iPhone/iPad: spara först appen på hemskärmen (Dela → Lägg till på hemskärmen) och öppna den därifrån — annars kan notiser inte aktiveras.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _enablingWebPush
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.notifications_active_rounded, size: 18),
              label: const Text('Aktivera notiser på den här enheten'),
              style: ElevatedButton.styleFrom(
                backgroundColor: dayColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _enablingWebPush
                  ? null
                  : () async {
                      setState(() => _enablingWebPush = true);
                      final ok = await PushService.enableWebPush();
                      if (mounted) setState(() => _enablingWebPush = false);
                      if (!mounted) return;
                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Notiser aktiverade på den här enheten! 🔔'),
                            backgroundColor: Color(0xFF6BAE75),
                          ),
                        );
                        if (_diagExpanded) _loadNotificationDiagnostics();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Kunde inte aktivera. Kontrollera att appen är öppnad från hemskärmsikonen och att notiser inte är blockerade i Inställningar → Notiser.',
                            ),
                            backgroundColor: Colors.orange.shade700,
                          ),
                        );
                      }
                    },
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Påminnelser till den här enheten',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text(
              'Aktiviteter, övergångar och sysslor som push. Kan komma några minuter efter utsatt tid.',
              style: TextStyle(fontSize: 12),
            ),
            value: _webRemindersEnabled,
            activeThumbColor: dayColor,
            onChanged: (v) async {
              setState(() => _webRemindersEnabled = v);
              final uid = _currentUser?.uid;
              if (uid != null) {
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({'webRemindersEnabled': v});
                } catch (e) {
                  if (mounted) {
                    setState(() => _webRemindersEnabled = !v);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kunde inte spara inställningen.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
        if (!kIsWeb) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktivitet börjar snart',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('15 min innan',
                style: TextStyle(fontSize: 12)),
            value: _notifActivity,
            activeThumbColor: dayColor,
            onChanged: (v) async {
              if (!v) {
                // Avbokar BARA aktivitetspåminnelser — sysslor/övergångar rörs ej.
                await NotificationService.cancelByPayloads({'activity'});
              }
              setState(() => _notifActivity = v);
              await _savePreference('notifActivity', v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Övergångsvarning',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('"Om 10 min: byta aktivitet" — extra förvarning',
                style: TextStyle(fontSize: 12)),
            value: _notifTransition,
            activeThumbColor: dayColor,
            onChanged: (v) async {
              if (!v) {
                await NotificationService.cancelByPayloads({'transition'});
              }
              setState(() => _notifTransition = v);
              await _savePreference('notifTransition', v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Påminnelse vid start',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text(
                'Notis exakt när aktiviteten börjar — bra om man vilar mellan passen',
                style: TextStyle(fontSize: 12)),
            value: _notifStart,
            activeThumbColor: dayColor,
            onChanged: (v) async {
              if (!v) {
                await NotificationService.cancelByPayloads({'activity_start'});
              } else {
                final famId = _currentUser?.familyId;
                if (famId != null && famId.isNotEmpty) {
                  await NotificationService.rescheduleAllForFamily(famId);
                }
              }
              setState(() => _notifStart = v);
              await _savePreference('notifStart', v);
              if (_diagExpanded) _loadNotificationDiagnostics();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Syssla tilldelad',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            value: _notifChore,
            activeThumbColor: dayColor,
            onChanged: (v) async {
              if (!v) {
                await NotificationService.cancelByPayloads({'chore'});
              }
              setState(() => _notifChore = v);
              _savePreference('notifChore', v);
            },
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Familjehändelser',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: const Text(
              'Push när någon skriver på tavlan, reagerar eller tilldelar',
              style: TextStyle(fontSize: 12)),
          value: _notifFamily,
          activeThumbColor: dayColor,
          onChanged: (v) async {
            setState(() => _notifFamily = v);
            await _savePreference('notifFamily', v);
            // Servern läser flaggan på users-dokumentet innan utskick.
            await PushService.setFamilyPushEnabled(v);
          },
        ),
        const Divider(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Lågstimuli-läge',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: const Text(
              'Lugnare utseende: platta färger, inga skuggor eller gradienter',
              style: TextStyle(fontSize: 12)),
          value: AppTheme.lowStimuli,
          activeThumbColor: dayColor,
          onChanged: (v) {
            setState(() => AppTheme.lowStimuli = v);
            _savePreference('lowStimuli', v);
            // Rita om alla flikar direkt — inte bara denna sida.
            context.read<FamilyProvider>().refreshUi();
          },
        ),
      ]),
    );
  }

  // ─── VIEW MODE CARD ──────────────────────────────────────────────────────────
  Widget _buildViewModeCard(Color dayColor) {
    if (_currentUser == null) return const SizedBox.shrink();
    final user = _currentUser!;
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VIS-LÄGE', style: AppTheme.sectionLabelStyle),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _buildViewModeControl(user, dayColor),
          ),
        ],
      ),
    );
  }

  // ─── DEV SECTION (UTVECKLARLÄGE) ─────────────────────────────────────────────
  Widget _buildDevSection(Color dayColor) {
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔧', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Utvecklarläge', style: AppTheme.cardTitleStyle),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _aiPlannerLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: dayColor,
                      ),
                    )
                  : const Text('🧪', style: TextStyle(fontSize: 14)),
              label: Text('Testa AI-planeraren',
                  style: TextStyle(color: dayColor, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _aiPlannerLoading ? null : _testAiPlanner,
            ),
          ),
          const Divider(height: 24),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
              initiallyExpanded: _diagExpanded,
              onExpansionChanged: (exp) {
                setState(() => _diagExpanded = exp);
                if (exp) _loadNotificationDiagnostics();
              },
              title: const Text(
                'Felsök notiser 🔧',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Behörigheter, schema och testnotiser',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              children: [
                if (_diagLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else ...[
                  _buildDiagRow(
                    ok: _diagNotifsEnabled == true,
                    text: _diagNotifsEnabled == true
                        ? 'Notisbehörighet: Beviljad i systemet'
                        : 'Notisbehörighet: Saknas/blockeras i systemet',
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 6),
                    _buildDiagRow(
                      ok: _diagExactAlarmsEnabled == true,
                      text: _diagExactAlarmsEnabled == true
                          ? 'Exakta larm: Tillåtna (påminnelser i tid)'
                          : 'Exakta larm: Ej tillåtna (kan fördröjas av Android)',
                    ),
                    if (_diagExactAlarmsEnabled == false) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.alarm_add_rounded, size: 16),
                          label: const Text('Tillåt exakta larm'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () async {
                            await NotificationService.requestExactAlarmsPermission();
                            await _loadNotificationDiagnostics();
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildDiagRow(
                      ok: _diagBatteryExempt == true,
                      text: _diagBatteryExempt == true
                          ? 'Batterioptimering: Undantagen (larm störs inte)'
                          : 'Batterioptimering: Aktiv — larm kan försenas på vissa telefoner',
                    ),
                    if (_diagBatteryExempt == false) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.battery_alert_rounded, size: 16),
                          label: const Text('Öppna batteriinställningar'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () async {
                            await NotificationService.openBatteryOptimizationSettings();
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildDiagRow(
                      ok: _diagPending.isNotEmpty,
                      text: 'Schemalagda påminnelser: ${_diagPending.length} st',
                      neutral: _diagPending.isEmpty,
                    ),
                    if (_diagPending.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _diagPending.take(3).map((req) {
                            final title = req.title ?? 'Påminnelse';
                            final body = req.body != null && req.body!.isNotEmpty
                                ? ' — ${req.body}'
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '• $title$body',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 6),
                  _buildDiagRow(
                    ok: _diagTokenRegistered,
                    text: _diagTokenRegistered
                        ? 'Push-registrering: Denna enhet är kopplad (${_diagDeviceToken != null && _diagDeviceToken!.length > 10 ? '${_diagDeviceToken!.substring(0, 8)}...' : 'OK'})'
                        : 'Push-registrering: Enhetens token saknas i profilen',
                  ),
                  const SizedBox(height: 6),
                  _buildFilterStatusRow(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (!kIsWeb) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: _schedulingLocalTest
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.timer_outlined, size: 16),
                            label: const Text('Testnotis om 1 minut',
                                style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _schedulingLocalTest
                                ? null
                                : _testLocalNotification,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _sendingTestPush
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 16),
                          label: const Text('Skicka test-push',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: dayColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed:
                              _sendingTestPush ? null : _testPushNotification,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterStatusRow() {
    String text;
    bool ok;
    if (!_notifFamily) {
      text =
          'Familjepush till dig stoppas för tillfället: Familjehändelser avstängt';
      ok = false;
    } else if ((_currentUser?.energy ?? 3) <= 1) {
      text = 'Familjepush till dig stoppas för tillfället: Lägsta energinivån';
      ok = false;
    } else if (_diagIsBusy) {
      text = 'Familjepush till dig stoppas för tillfället: Upptagen aktiv';
      ok = false;
    } else {
      text = 'Inga filter aktiva ✅';
      ok = true;
    }

    return _buildDiagRow(ok: ok, text: text);
  }

  Widget _buildDiagRow(
      {required bool ok, required String text, bool neutral = false}) {
    final emoji = neutral ? 'ℹ️' : (ok ? '✅' : '⚠️');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: neutral
                  ? Colors.grey.shade700
                  : (ok ? Colors.green.shade800 : Colors.orange.shade900),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadNotificationDiagnostics() async {
    setState(() => _diagLoading = true);
    try {
      bool notifsEnabled = false;
      bool exactEnabled = true;
      bool batteryExempt = true;
      List<PendingNotificationRequest> pending = [];

      if (kIsWeb) {
        try {
          final settings =
              await FirebaseMessaging.instance.getNotificationSettings();
          notifsEnabled =
              settings.authorizationStatus == AuthorizationStatus.authorized;
        } catch (_) {
          notifsEnabled = false;
        }
      } else {
        notifsEnabled = await NotificationService.areNotificationsEnabled();
        exactEnabled =
            await NotificationService.canScheduleExactNotifications();
        batteryExempt =
            await NotificationService.isIgnoringBatteryOptimizations();
        pending = await NotificationService.getPendingNotifications();
      }

      final deviceToken = await PushService.getDeviceToken();

      bool tokenRegistered = false;
      if (deviceToken != null && _currentUser != null) {
        try {
          final userSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUser!.uid)
              .get();
          final tokens = (userSnap.data()?['fcmTokens'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              _currentUser!.fcmTokens;
          tokenRegistered = tokens.contains(deviceToken);
        } catch (_) {
          tokenRegistered = _currentUser!.fcmTokens.contains(deviceToken);
        }
      }

      bool isBusy = false;
      if (_currentUser?.familyId != null) {
        final now = DateTime.now();
        final busySnap = await FirebaseFirestore.instance
            .collection('busy_sessions')
            .where('familyId', isEqualTo: _currentUser!.familyId)
            .where('endAt', isGreaterThan: Timestamp.fromDate(now))
            .get();
        for (final doc in busySnap.docs) {
          final b = doc.data();
          final startAt = (b['startAt'] as Timestamp?)?.toDate();
          if (startAt != null && !startAt.isAfter(now)) {
            final uid = b['userUid'] as String?;
            final name = b['userName'] as String?;
            if (uid == _currentUser!.uid || name == _currentUser!.name) {
              isBusy = true;
              break;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _diagNotifsEnabled = notifsEnabled;
          _diagExactAlarmsEnabled = exactEnabled;
          _diagBatteryExempt = batteryExempt;
          _diagPending = pending;
          _diagDeviceToken = deviceToken;
          _diagTokenRegistered = tokenRegistered;
          _diagIsBusy = isBusy;
          _diagLoading = false;
        });
      }
    } catch (e, stack) {
      developer.log('Kunde inte läsa notisdiagnostik',
          error: e, stackTrace: stack);
      if (mounted) setState(() => _diagLoading = false);
    }
  }

  Future<void> _testLocalNotification() async {
    setState(() => _schedulingLocalTest = true);
    try {
      await NotificationService.scheduleTestReminderIn1Min();
      await _loadNotificationDiagnostics();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Testnotis schemalagd om 1 minut! ⏰ Lås gärna skärmen nu för att testa att den dyker upp.',
          ),
          backgroundColor: Color(0xFF2A6F97),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte schemalägga testnotis: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _schedulingLocalTest = false);
    }
  }

  Future<void> _testPushNotification() async {
    setState(() => _sendingTestPush = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('sendTestPush');
      final result = await callable.call();
      final data = result.data as Map<dynamic, dynamic>? ?? {};
      final success = data['success'] == true;
      final count = data['count'] ?? 0;
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Test-push skickad till $count enhet(er)! 🔔 Den bör dyka upp inom några sekunder.',
            ),
            backgroundColor: const Color(0xFF27AE60),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        final msg = data['message'] ?? 'Kunde inte skicka push.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg.toString()),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Ett fel uppstod vid push-test.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte skicka test-push: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingTestPush = false);
    }
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
          errorBuilder: (_, _, e) =>
              const Icon(Icons.favorite_rounded, size: 48, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        const Text('La Familia',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onVersionTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Version 1.0.0',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 2),
        Text('Skapad av Valladares',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ]),
    );
  }

  void _onVersionTap() async {
    _devClickCount++;
    if (_devClickCount >= 7) {
      _devClickCount = 0;
      final next = !_devMode;
      setState(() => _devMode = next);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dev_mode_enabled', next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next ? 'Utvecklarläge på 🔧' : 'Utvecklarläge av'),
            backgroundColor:
                next ? const Color(0xFF2F3B45) : Colors.grey.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
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
