import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/family_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/user_service.dart';
import 'manage_members_page.dart';
import 'manage_routines_page.dart';
import 'invite_page.dart';

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

  // Notification toggles
  bool _notifActivity = true;
  bool _notifChore = true;
  bool _notifTransition = true;
  bool _notifFamily = true;

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
      _notifFamily = prefs.getBool('notifFamily') ?? true;
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
            familyName = famDoc.data()?['name'] as String?;
          }
        } catch (e, stack) {
          developer.log('Misslyckades hämta familjenamn', error: e, stackTrace: stack);
        }
      }
      if (mounted) {
        setState(() {
          _currentUser = user;
          _familyMembers = members;
          _familyName = familyName;
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
                SliverToBoxAdapter(child: _buildHeader(context, dayColor)),
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
                  SliverToBoxAdapter(child: _buildNotificationsCard(dayColor)),
                  if (_currentUser?.isParent ?? false)
                    SliverToBoxAdapter(child: _buildMaintenanceCard(dayColor)),
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
            child: _buildViewModeControl(user, dayColor),
          ),
        ],
      ),
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Text('🌅', style: TextStyle(fontSize: 14)),
            label: Text('Morgon- & kvällsrutiner',
                style: TextStyle(color: dayColor, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ManageRoutinesPage())),
          ),
        ),
      ]),
    );
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
          activeColor: dayColor,
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
          title: const Text('Syssla tilldelad',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          value: _notifChore,
          activeColor: dayColor,
          onChanged: (v) async {
            if (!v) {
              await NotificationService.cancelByPayloads({'chore'});
            }
            setState(() => _notifChore = v);
            _savePreference('notifChore', v);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Familjehändelser',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: const Text(
              'Push när någon skriver på tavlan, reagerar eller tilldelar',
              style: TextStyle(fontSize: 12)),
          value: _notifFamily,
          activeColor: dayColor,
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
          activeColor: dayColor,
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

  // ─── MAINTENANCE CARD (endast förälder — ta bort efter migrering) ───────────
  bool _migrating = false;

  Future<void> _runMigration({
    required String functionName,
    required String title,
    required String body,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kör migrering'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _migrating = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(functionName)
          .call<Map<String, dynamic>>();
      final migrated = result.data['migrated'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Klart! $migrated dokument uppdaterade. ✅'),
            backgroundColor: const Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e, stack) {
      developer.log('$functionName misslyckades', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Migrering misslyckades: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  Future<void> _runDateMigration() => _runMigration(
        functionName: 'migrateDateFormatOnce',
        title: 'Migrera datumformat?',
        body: 'Paddar alla gamla datum (t.ex. 2026-5-3 → 2026-05-03) i '
            'aktiviteter, sysslor och arbetspass.\n\nKör detta EN gång, och '
            'helst efter att en Firestore-backup tagits. Det är säkert att '
            'köra igen vid avbrott.',
      );

  Future<void> _runPersonUidBackfill() => _runMigration(
        functionName: 'backfillPersonUids',
        title: 'Koppla personer via uid?',
        body: 'Fyller i uid-kopplingar för befintliga aktiviteter, sysslor, '
            'arbetspass och upptagen-sessioner utifrån namnen. Gör att '
            'namnbyten inte längre tappar kopplingar.\n\nIdempotent — säker '
            'att köra igen.',
      );

  Widget _buildMaintenanceCard(Color dayColor) {
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.build_rounded, color: dayColor, size: 20),
          const SizedBox(width: 8),
          Text('Underhåll', style: AppTheme.cardTitleStyle),
        ]),
        const SizedBox(height: 8),
        Text(
          'Engångsåtgärd för att standardisera datumformat i databasen.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: _migrating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.update_rounded, size: 16, color: dayColor),
            label: Text(
              _migrating ? 'Migrerar…' : 'Migrera datumformat',
              style: TextStyle(color: dayColor, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _migrating ? null : _runDateMigration,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(Icons.link_rounded, size: 16, color: dayColor),
            label: Text(
              'Koppla personer via uid',
              style: TextStyle(color: dayColor, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _migrating ? null : _runPersonUidBackfill,
          ),
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
