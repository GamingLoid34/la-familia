import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../app_theme.dart';
import '../firebase_options.dart';

class ManageMembersPage extends StatefulWidget {
  const ManageMembersPage({super.key});

  @override
  State<ManageMembersPage> createState() => _ManageMembersPageState();
}

class _ManageMembersPageState extends State<ManageMembersPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _selectedColor = 'ff2196f3';
  String _selectedRole = 'Barn';
  String? _editingId;
  String? _familyId;
  bool _isLoading = false;

  final List<String> _colors = [
    'ff2196f3',
    'fff44336',
    'ff4caf50',
    'ffff9800',
    'ff9c27b0',
    'ffe91e63',
    'ff795548',
    'ff607d8b',
    'ff6bae75', // NPF Grön
    'ffedd87a', // NPF Gul
  ];

  @override
  void initState() {
    super.initState();
    _loadFamilyId();
  }

  Future<void> _loadFamilyId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          _familyId = doc.data()?['familyId'] as String?;
        });
      }
    }
  }

  void _resetForm() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    setState(() {
      _selectedColor = 'ff2196f3';
      _selectedRole = 'Barn';
      _editingId = null;
    });
    FocusScope.of(context).unfocus();
  }

  void _editMember(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    _nameController.text = data['name'] ?? '';
    _emailController.text = data['email'] ?? '';
    
    setState(() {
      _editingId = doc.id;
      _selectedColor = data['color'] ?? 'ff2196f3';
      
      // Översätt databas-roll till rullgardin
      final r = data['role'] ?? 'child';
      if (r == 'parent') {
        _selectedRole = 'Förälder';
      } else if (r == 'admin') {
        _selectedRole = 'Admin';
      } else if (r == 'youth') {
        _selectedRole = 'Ungdom';
      } else {
        _selectedRole = 'Barn';
      }
    });
  }

  Future<void> _deleteMember(String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort medlem?'),
        content: Text('Är du säker på att du vill ta bort $name från familjen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Ta bort')
          ),
        ],
      )
    );

    if (confirm == true) {
      // Tar bort användarens koppling till familjen genom att radera dokumentet.
      // (Observera att auth-inloggningen tekniskt sett ligger kvar i Firebase Auth, men de är borta från appen).
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medlem borttagen.')));
      }
    }
  }

  Future<void> _saveMember() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fyll i namn och e-post!")));
      return;
    }

    if (_editingId == null && _passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lösenordet måste vara minst 6 tecken.")));
      return;
    }

    if (_familyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Laddar familjedata, försök igen om en sekund...")));
      return;
    }

    setState(() => _isLoading = true);

    // Översätt rullgardin till databas-roll
    String dbRole = 'child';
    if (_selectedRole == 'Förälder') dbRole = 'parent';
    if (_selectedRole == 'Admin') dbRole = 'admin';
    if (_selectedRole == 'Ungdom') dbRole = 'youth';

    Map<String, dynamic> userData = {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'color': _selectedColor,
      'role': dbRole,
    };

    try {
      if (_editingId == null) {
        FirebaseApp secondaryApp;
        try {
          secondaryApp = Firebase.app('SecondaryApp');
        } catch (e) {
          secondaryApp = await Firebase.initializeApp(
            name: 'SecondaryApp',
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }

        UserCredential userCredential = await FirebaseAuth.instanceFor(app: secondaryApp)
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        final uid = userCredential.user?.uid;
        if (uid == null) {
          throw Exception("Kunde inte hämta UID från Firebase Auth.");
        }

        // --- VIKTIGT: Spara familyId och standardvärden på NYA konton ---
        userData['uid'] = uid;
        userData['familyId'] = _familyId; // Det var denna som saknades förut!
        userData['createdAt'] = FieldValue.serverTimestamp();
        userData['energy'] = 3;
        userData['weeklyPoints'] = 0;
        userData['points'] = 0;
        userData['viewMode'] = (dbRole == 'parent' || dbRole == 'admin') ? 'parent' : 'child';

        await FirebaseFirestore.instance.collection('users').doc(uid).set(userData);
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Medlem skapad! ✅")));
      } else {
        // Uppdatera befintlig medlem
        await FirebaseFirestore.instance.collection('users').doc(_editingId).update(userData);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Medlem uppdaterad! ✅")));
      }
      _resetForm();
    } on FirebaseAuthException catch (e) {
      String msg = "Ett fel uppstod.";
      if (e.code == 'email-already-in-use') msg = "Denna e-postadress används redan.";
      if (e.code == 'invalid-email') msg = "E-postadressen är felaktigt formaterad.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Något gick fel: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color textColor = AppTheme.getTextColor();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Hantera Medlemmar",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
        height: double.infinity,
        decoration: AppTheme.getBackground(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- FORMULÄRET ---
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _editingId == null ? "Lägg till medlem" : "Redigera medlem",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          if (_editingId != null)
                            TextButton(onPressed: _resetForm, child: const Text('Avbryt'))
                        ],
                      ),
                      const SizedBox(height: 15),
                      const Text("Profilfärg", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _colors.map((colorHex) => GestureDetector(
                          onTap: () => setState(() => _selectedColor = colorHex),
                          child: CircleAvatar(
                            backgroundColor: Color(int.parse(colorHex, radix: 16)),
                            radius: 18,
                            child: _selectedColor == colorHex ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 20),

                      _input("Namn", _nameController, Icons.person),
                      const SizedBox(height: 10),

                      _input("E-post", _emailController, Icons.email),
                      const SizedBox(height: 10),

                      if (_editingId == null) ...[
                        _input("Lösenord (minst 6 tecken)", _passwordController, Icons.lock, isObscure: true),
                        const SizedBox(height: 10),
                      ],

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedRole,
                            isExpanded: true,
                            items: ['Barn', 'Ungdom', 'Förälder', 'Admin'].map((String value) {
                              return DropdownMenuItem<String>(value: value, child: Text(value));
                            }).toList(),
                            onChanged: (newValue) => setState(() => _selectedRole = newValue!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveMember,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.getDayAccentColor(),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  _editingId == null ? "Spara ny medlem" : "Uppdatera",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                
                // --- LISTA PÅ AKTUELLA MEDLEMMAR ---
                Text("Familjemedlemmar", style: AppTheme.sectionTitleStyle),
                const SizedBox(height: 12),
                
                if (_familyId == null)
                  const Center(child: CircularProgressIndicator())
                else
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('familyId', isEqualTo: _familyId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      
                      var docs = snapshot.data!.docs;
                      if (docs.isEmpty) return const Text("Inga medlemmar hittades.");

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var data = docs[index].data() as Map<String, dynamic>;
                          var name = data['name'] ?? 'Okänd';
                          var email = data['email'] ?? '';
                          var colorStr = data['color'] ?? 'ff2196f3';
                          Color avatarColor;
                          try {
                            avatarColor = Color(int.parse(colorStr.startsWith('0x') ? colorStr : '0xFF$colorStr'));
                          } catch (_) {
                            avatarColor = Colors.blue;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: avatarColor,
                                child: Text(name.toString().isNotEmpty ? name.toString()[0].toUpperCase() : '?', 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(email, style: const TextStyle(fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _editMember(docs[index]),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteMember(docs[index].id, name),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ))),
    );
  }

  Widget _input(String label, TextEditingController controller, IconData icon, {bool isObscure = false}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey.shade600),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}