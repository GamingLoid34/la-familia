import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../app_theme.dart';
import '../main.dart';
import '../services/family_service.dart';
import '../utils/date_utils.dart';

/// Onboarding (omdesignad i Etapp 14): skapa eller gå med i familj.
/// Vid NY familj skapas tre exempel (aktivitet, rutin, syssla) så att
/// appen inte är tom dag 1 — allt tydligt märkt och raderbart.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _inviteCodeCtrl = TextEditingController();
  final _familyNameCtrl = TextEditingController();
  final _userNameCtrl = TextEditingController();
  bool _isLoading = false;
  /// Join-roll: parent | youth | child (default Barn).
  String _joinRole = 'child';

  @override
  void dispose() {
    _inviteCodeCtrl.dispose();
    _familyNameCtrl.dispose();
    _userNameCtrl.dispose();
    super.dispose();
  }

  String _generateRandomString(int len) {
    final r = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(len, (index) => chars[r.nextInt(chars.length)])
        .join();
  }

  InputDecoration _fieldDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.grey.shade50,
      );

  /// Förstagångs-exempel (Etapp 14.2) — visar hur appen funkar utan att
  /// familjen behöver lista ut allt själva. Lätta att radera.
  Future<void> _seedExamples(
      String familyId, String uid, String userName) async {
    try {
      final db = FirebaseFirestore.instance;
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      final batch = db.batch();

      batch.set(db.collection('planner_events').doc(), {
        'title': 'Exempel: Middag tillsammans',
        'piktogram': '🍽️',
        'type': 'activity',
        'date': dateKey(tomorrow),
        'time': '17:30',
        'persons': <String>[],
        'personUids': <String>[],
        'checklist': <dynamic>[],
        'source': 'manual',
        'createdBy': uid,
        'createdByUid': uid,
        'isPending': false,
        'familyId': familyId,
      });

      batch.set(db.collection('routines').doc(), {
        'familyId': familyId,
        'ownerUid': uid,
        'ownerName': userName,
        'type': 'morning',
        'steps': [
          {'title': 'Borsta tänderna', 'piktogram': '🪥'},
          {'title': 'Klä på dig', 'piktogram': '👕'},
          {'title': 'Ät frukost', 'piktogram': '🥣'},
        ],
        'doneDate': '',
        'doneSteps': <int>[],
      });

      batch.set(db.collection('chores').doc(), {
        'chore': 'Exempel: Vattna blommorna',
        'piktogram': '🪴',
        'who': '',
        'whoUid': '',
        'whoColor': '',
        'isDone': false,
        'points': 3,
        'isRecurring': false,
        'familyId': familyId,
        'substeps': <Map<String, dynamic>>[],
        'createdByUid': uid,
      });

      await batch.commit();
    } catch (e, stack) {
      // Exempel är trevliga men inte kritiska — blockera aldrig onboarding.
      developer.log('seedExamples misslyckades', error: e, stackTrace: stack);
    }
  }

  Future<void> _createFamily() async {
    if (_familyNameCtrl.text.isEmpty || _userNameCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final newCode = _generateRandomString(6);
        final familyRef =
            await FirebaseFirestore.instance.collection('families').add({
          'name': _familyNameCtrl.text.trim(),
          'inviteCode': newCode,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
        });

        // Tilldela unik medlemsfärg från paletten innan vi skriver doc.
        final assignedColor =
            await FamilyService.assignNextAvailableColor(familyRef.id);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'name': _userNameCtrl.text.trim(),
          'familyId': familyRef.id,
          'role': 'admin',
          'color': assignedColor,
        }, SetOptions(merge: true));

        await _seedExamples(
            familyRef.id, user.uid, _userNameCtrl.text.trim());

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainPage()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fel: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinFamily() async {
    if (_inviteCodeCtrl.text.isEmpty || _userNameCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFunctions.instance
          .httpsCallable('joinFamilyWithCode')
          .call<Map<String, dynamic>>({
        'code': _inviteCodeCtrl.text.trim().toUpperCase(),
        'name': _userNameCtrl.text.trim(),
        'role': _joinRole,
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainPage()),
        );
      }
    } catch (e, stack) {
      developer.log('joinFamily misslyckades', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fel: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _roleChoiceButton({
    required String role,
    required String label,
    required Color accent,
  }) {
    final selected = _joinRole == role;
    return Expanded(
      child: Material(
        color: selected ? accent.withValues(alpha: 0.15) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => setState(() => _joinRole = role),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? accent : Colors.grey.shade300,
                width: selected ? 2 : 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? accent : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.dayPalette();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.lowStimuli ? null : palette.gradient,
          color: AppTheme.lowStimuli ? palette.base : null,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 150,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Text('La Familia', style: AppTheme.pageTitleStyle),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Välkommen! 👋',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextColor(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Innan vi börjar behöver du skapa eller '
                      'ansluta till en familj.',
                      style: TextStyle(color: AppTheme.getSubTextColor()),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _userNameCtrl,
                      decoration: _fieldDecoration(
                          'Ditt förnamn', Icons.person_rounded),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child:
                          Text('SKAPA NY FAMILJ', style: AppTheme.sectionLabelStyle),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _familyNameCtrl,
                      decoration: _fieldDecoration(
                          'Familjens namn (t.ex. Svensson)',
                          Icons.home_rounded),
                    ),
                    const SizedBox(height: 14),
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _createFamily,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: palette.base,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Skapa familj',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('GÅ MED I BEFINTLIG FAMILJ',
                          style: AppTheme.sectionLabelStyle),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inviteCodeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _fieldDecoration(
                          'Inbjudningskod', Icons.vpn_key_rounded),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Jag är…',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _roleChoiceButton(
                          role: 'parent',
                          label: 'Vuxen 👤',
                          accent: palette.base,
                        ),
                        const SizedBox(width: 8),
                        _roleChoiceButton(
                          role: 'youth',
                          label: 'Ungdom 🧑',
                          accent: palette.base,
                        ),
                        const SizedBox(width: 8),
                        _roleChoiceButton(
                          role: 'child',
                          label: 'Barn 🧒',
                          accent: palette.base,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (!_isLoading)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _joinFamily,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: palette.base, width: 1.5),
                            foregroundColor: palette.deep,
                          ),
                          child: const Text(
                            'Gå med',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
