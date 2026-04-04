import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import '../app_theme.dart';

class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  String? _inviteCode;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrGenerateInviteCode();
  }

  String _generateRandomString(int len) {
    var r = Random();
    const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      len,
      (index) => _chars[r.nextInt(_chars.length)],
    ).join();
  }

  Future<void> _loadOrGenerateInviteCode() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final familyId = userDoc.data()?['familyId'];

      if (familyId != null) {
        final familyDoc = await FirebaseFirestore.instance
            .collection('families')
            .doc(familyId)
            .get();
        if (familyDoc.exists && familyDoc.data()!.containsKey('inviteCode')) {
          setState(() {
            _inviteCode = familyDoc.data()!['inviteCode'];
          });
        } else {
          String newCode = _generateRandomString(6);
          await FirebaseFirestore.instance
              .collection('families')
              .doc(familyId)
              .set({'inviteCode': newCode}, SetOptions(merge: true));

          setState(() {
            _inviteCode = newCode;
          });
        }
      }
    } catch (e) {
      debugPrint("Invite error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard() {
    if (_inviteCode != null) {
      Clipboard.setData(ClipboardData(text: _inviteCode!));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Inbjudningskod kopierad!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Bjud in",
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
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.getBackground(),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
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
                            Icons.card_giftcard,
                            size: 60,
                            color: Colors.blueAccent,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "Dela inbjudningskod",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.getTextColor(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Personer som har denna kod kan ansluta till din familj genom att välja 'Skapa konto' eller 'Har du en inbjudningskod?' vid inloggning.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.getSubTextColor(),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blueAccent),
                            ),
                            child: Text(
                              _inviteCode ?? "FEL",
                              style: TextStyle(
                                fontSize: 32,
                                letterSpacing: 5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.getTextColor(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _copyToClipboard,
                            icon: const Icon(Icons.copy),
                            label: const Text("Kopiera kod"),
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
