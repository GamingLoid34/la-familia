import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../app_theme.dart';
import '../main.dart';

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

  String _generateRandomString(int len) {
    var r = Random();
    const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      len,
      (index) => _chars[r.nextInt(_chars.length)],
    ).join();
  }

  Future<void> _createFamily() async {
    if (_familyNameCtrl.text.isEmpty || _userNameCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Skapa familj
        final String newCode = _generateRandomString(6);
        final familyRef = await FirebaseFirestore.instance
            .collection('families')
            .add({
              'name': _familyNameCtrl.text.trim(),
              'inviteCode': newCode,
              'createdAt': FieldValue.serverTimestamp(),
              'createdBy': user.uid,
            });

        // Uppdatera användaren
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': _userNameCtrl.text.trim(),
          'familyId': familyRef.id,
          'role': 'admin',
          'points': 0,
        }, SetOptions(merge: true));

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainPage()),
          );
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fel: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinFamily() async {
    if (_inviteCodeCtrl.text.isEmpty || _userNameCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        var snapshot = await FirebaseFirestore.instance
            .collection('families')
            .where(
              'inviteCode',
              isEqualTo: _inviteCodeCtrl.text.trim().toUpperCase(),
            )
            .limit(1)
            .get();

        if (snapshot.docs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ogiltig inbjudningskod.')),
          );
          setState(() => _isLoading = false);
          return;
        }

        String familyId = snapshot.docs.first.id;

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': _userNameCtrl.text.trim(),
          'familyId': familyId,
          'role': 'member',
          'points': 0,
        }, SetOptions(merge: true));

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainPage()),
          );
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fel: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.getBackground(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.getCardColor(),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.family_restroom,
                      size: 60,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Välkommen till La Familia",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextColor(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Innan vi börjar behöver du ansluta till en familj.",
                      style: TextStyle(
                        color: AppTheme.getSubTextColor(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),

                    TextField(
                      controller: _userNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Ditt förnamn",
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 10),

                    Text(
                      "Skapa ny familj",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextColor(),
                      ),
                    ),
                    TextField(
                      controller: _familyNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Familjens namn (t.ex. Familjen Svensson)",
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _createFamily,
                      child: const Text("Skapa familj"),
                    ),

                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 10),

                    Text(
                      "Gå med i befintlig familj",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextColor(),
                      ),
                    ),
                    TextField(
                      controller: _inviteCodeCtrl,
                      decoration: const InputDecoration(
                        labelText: "Inbjudningskod",
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _joinFamily,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Gå med"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ))),
    );
  }
}
