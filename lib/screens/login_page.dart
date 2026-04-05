import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fyll i e-post och lösenord")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // AuthWrapper i main.dart känner av inloggningen och tar oss vidare automatiskt.
    } on FirebaseAuthException catch (e) {
      String message = "Inloggning misslyckades.";
      if (e.code == 'user-not-found') message = "Användaren finns inte.";
      if (e.code == 'wrong-password') message = "Fel lösenord.";
      if (e.code == 'invalid-email') message = "Ogiltig e-postadress.";

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Ett fel uppstod: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final TextEditingController _resetEmailController = TextEditingController();
    _resetEmailController.text = _emailController.text;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Återställ lösenord'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Ange den e-postadress du använde vid registrering så skickar vi en länk.",
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _resetEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-post'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_resetEmailController.text.isNotEmpty) {
                  try {
                    await FirebaseAuth.instance.sendPasswordResetEmail(
                      email: _resetEmailController.text.trim(),
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Ett e-postmeddelande för att återställa ditt lösenord har skickats!",
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("Fel: $e")));
                    }
                  }
                }
              },
              child: const Text('Skicka'),
            ),
          ],
        );
      },
    );
  }

  void _showRegisterDialog() {
    final _nameCtrl = TextEditingController();
    final _emailCtrl = TextEditingController();
    final _pwdCtrl = TextEditingController();
    bool _isRegistering = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateBuilder) {
            return AlertDialog(
              title: const Text('Skapa nytt konto'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Skapa ett konto för att starta en helt ny familj.",
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Ditt förnamn'),
                    ),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Din e-post'),
                    ),
                    TextField(
                      controller: _pwdCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Lösenord (minst 6 tecken)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                _isRegistering
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: () async {
                          if (_emailCtrl.text.isEmpty ||
                              _pwdCtrl.text.isEmpty ||
                              _nameCtrl.text.isEmpty) return;

                          // Spara navigatorn innan vi gör något asynkront!
                          final navigator = Navigator.of(context);
                          setStateBuilder(() => _isRegistering = true);
                          
                          try {
                            UserCredential uc = await FirebaseAuth.instance
                                .createUserWithEmailAndPassword(
                              email: _emailCtrl.text.trim(),
                              password: _pwdCtrl.text.trim(),
                            );

                            if (uc.user != null) {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uc.user!.uid)
                                  .set({
                                'email': _emailCtrl.text.trim(),
                                'name': _nameCtrl.text.trim(),
                                'role': 'parent', 
                                'createdAt': FieldValue.serverTimestamp(),
                              });

                              // Stäng dialogen med den sparade navigatorn oavsett "mounted"-status
                              navigator.pop();
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('Fel: $e')));
                            setStateBuilder(() => _isRegistering = false);
                          }
                        },
                        child: const Text('Skapa konto'),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  void _showInviteDialog() {
    final _inviteCodeCtrl = TextEditingController();
    final _nameCtrl = TextEditingController();
    final _emailCtrl = TextEditingController();
    final _pwdCtrl = TextEditingController();
    bool _isRegistering = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateBuilder) {
            return AlertDialog(
              title: const Text('Gå med med kod'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _inviteCodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Inbjudningskod',
                        hintText: 't.ex. ABC123',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ditt förnamn',
                      ),
                    ),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Din e-post',
                      ),
                    ),
                    TextField(
                      controller: _pwdCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Lösenord (minst 6 tecken)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                _isRegistering
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: () async {
                          if (_inviteCodeCtrl.text.isEmpty ||
                              _emailCtrl.text.isEmpty ||
                              _pwdCtrl.text.isEmpty ||
                              _nameCtrl.text.isEmpty)
                            return;

                          // Spara navigatorn innan async
                          final navigator = Navigator.of(context);
                          setStateBuilder(() => _isRegistering = true);
                          
                          try {
                            // Hitta familjen
                            var snapshot = await FirebaseFirestore.instance
                                .collection('families')
                                .where(
                                  'inviteCode',
                                  isEqualTo: _inviteCodeCtrl.text
                                      .trim()
                                      .toUpperCase(),
                                )
                                .limit(1)
                                .get();

                            if (snapshot.docs.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ogiltig inbjudningskod.'),
                                ),
                              );
                              setStateBuilder(() => _isRegistering = false);
                              return;
                            }

                            String familyId = snapshot.docs.first.id;

                            // Skapa konto
                            UserCredential uc = await FirebaseAuth.instance
                                .createUserWithEmailAndPassword(
                                  email: _emailCtrl.text.trim(),
                                  password: _pwdCtrl.text.trim(),
                                );

                            if (uc.user != null) {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uc.user!.uid)
                                  .set({
                                    'email': _emailCtrl.text.trim(),
                                    'name': _nameCtrl.text.trim(),
                                    'familyId': familyId,
                                    'role': 'member',
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });

                              // Stäng dialogen
                              navigator.pop();
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('Fel: $e')));
                            setStateBuilder(() => _isRegistering = false);
                          }
                        },
                        child: const Text('Gå med'),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),

                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "E-post",
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 15),

                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "Lösenord",
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 25),

                  if (_isLoading)
                    const CircularProgressIndicator()
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: AppTheme.getDayAccentColor(),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          "Logga in",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 15),

                  TextButton(
                    onPressed: _showForgotPasswordDialog,
                    child: const Text("Glömt lösenordet?"),
                  ),

                  const Divider(),

                  TextButton.icon(
                    onPressed: _showRegisterDialog,
                    icon: const Icon(Icons.person_add),
                    label: const Text("Skapa nytt konto (Ny familj)"),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.getDayAccentColor(),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                  TextButton.icon(
                    onPressed: _showInviteDialog,
                    icon: const Icon(Icons.group_add),
                    label: const Text("Har du en inbjudningskod?"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green[800],
                      textStyle:
                          const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}