import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../main.dart';
import '../app_theme.dart';

/// Inloggning (omdesignad i Etapp 14): dagens gradient som fond,
/// vitt kort, samma flöden som tidigare (logga in / ny familj / kod).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.grey.shade50,
      );

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll i e-post och lösenord')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => rootAfterAuth()),
        );
      }
    } on FirebaseAuthException catch (e) {
      var message = 'Inloggning misslyckades.';
      if (e.code == 'user-not-found') message = 'Användaren finns inte.';
      if (e.code == 'wrong-password') message = 'Fel lösenord.';
      if (e.code == 'invalid-email') message = 'Ogiltig e-postadress.';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ett fel uppstod: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController();
    resetEmailController.text = _emailController.text;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Återställ lösenord'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ange den e-postadress du använde vid registrering så '
                'skickar vi en länk.',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: resetEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-post'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (resetEmailController.text.isEmpty) return;
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(
                    email: resetEmailController.text.trim(),
                  );
                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ett e-postmeddelande för att återställa ditt '
                        'lösenord har skickats!',
                      ),
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Fel: $e')));
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
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    var isRegistering = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateBuilder) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Skapa nytt konto'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Skapa ett konto för att starta en ny familj.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Ditt förnamn'),
                    ),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration:
                          const InputDecoration(labelText: 'Din e-post'),
                    ),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Lösenord (minst 6 tecken)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Avbryt'),
                ),
                if (isRegistering)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: () async {
                      if (emailCtrl.text.isEmpty ||
                          pwdCtrl.text.isEmpty ||
                          nameCtrl.text.isEmpty) {
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      final messenger = ScaffoldMessenger.of(context);
                      setStateBuilder(() => isRegistering = true);

                      try {
                        final uc = await FirebaseAuth.instance
                            .createUserWithEmailAndPassword(
                          email: emailCtrl.text.trim(),
                          password: pwdCtrl.text.trim(),
                        );

                        if (uc.user != null) {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uc.user!.uid)
                              .set({
                            'email': emailCtrl.text.trim(),
                            'name': nameCtrl.text.trim(),
                            'role': 'parent',
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                          navigator.pop();
                        }
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text('Fel: $e')));
                        setStateBuilder(() => isRegistering = false);
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
    final inviteCodeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    var isRegistering = false;
    var joinRole = 'child';

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateBuilder) {
            Widget roleBtn(String role, String label) {
              final selected = joinRole == role;
              return Expanded(
                child: InkWell(
                  onTap: () => setStateBuilder(() => joinRole = role),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.dayPalette().base.withValues(alpha: 0.12)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppTheme.dayPalette().base
                            : Colors.grey.shade300,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppTheme.dayPalette().deep
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Gå med med kod'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: inviteCodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Inbjudningskod',
                        hintText: 't.ex. ABC123',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    TextField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Ditt förnamn'),
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
                        roleBtn('parent', 'Vuxen 👤'),
                        const SizedBox(width: 6),
                        roleBtn('youth', 'Ungdom 🧑'),
                        const SizedBox(width: 6),
                        roleBtn('child', 'Barn 🧒'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration:
                          const InputDecoration(labelText: 'Din e-post'),
                    ),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Lösenord (minst 6 tecken)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Avbryt'),
                ),
                if (isRegistering)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () async {
                      if (inviteCodeCtrl.text.isEmpty ||
                          emailCtrl.text.isEmpty ||
                          pwdCtrl.text.isEmpty ||
                          nameCtrl.text.isEmpty) {
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      final rootNavigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      setStateBuilder(() => isRegistering = true);
                      try {
                        final uc = await FirebaseAuth.instance
                            .createUserWithEmailAndPassword(
                          email: emailCtrl.text.trim(),
                          password: pwdCtrl.text.trim(),
                        );

                        if (uc.user != null) {
                          await FirebaseFunctions.instance
                              .httpsCallable('joinFamilyWithCode')
                              .call<Map<String, dynamic>>({
                            'code': inviteCodeCtrl.text.trim().toUpperCase(),
                            'name': nameCtrl.text.trim(),
                            'role': joinRole,
                          });

                          navigator.pop();
                          rootNavigator.pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => rootAfterAuth(),
                            ),
                          );
                        }
                      } catch (e, stack) {
                        developer.log('Invite join misslyckades',
                            error: e, stackTrace: stack);
                        messenger.showSnackBar(
                            SnackBar(content: Text('Fel: $e')));
                        setStateBuilder(() => isRegistering = false);
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
    final palette = AppTheme.dayPalette();

    return Scaffold(
      body: Container(
        // Dagens gradient som fond — samma identitet som resten av appen.
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
                      width: 160,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(
                        'La Familia',
                        style: AppTheme.pageTitleStyle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Familjens vardag, samlad.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration:
                          _fieldDecoration('E-post', Icons.email_rounded),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                      decoration:
                          _fieldDecoration('Lösenord', Icons.lock_rounded),
                    ),
                    const SizedBox(height: 24),
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: palette.base,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Logga in',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: const Text('Glömt lösenordet?'),
                    ),
                    const Divider(),
                    TextButton.icon(
                      onPressed: _showRegisterDialog,
                      icon: const Icon(Icons.person_add_rounded),
                      label: const Text('Skapa nytt konto (Ny familj)'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.deep,
                        textStyle:
                            const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showInviteDialog,
                      icon: const Icon(Icons.group_add_rounded),
                      label: const Text('Har du en inbjudningskod?'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.deep,
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
      ),
    );
  }
}
