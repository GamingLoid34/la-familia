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
  bool _isLoading = false;

  final List<String> _colors = [
    'ff2196f3', 'fff44336', 'ff4caf50', 'ffff9800', 
    'ff9c27b0', 'ffe91e63', 'ff795548', 'ff607d8b'
  ];

  @override
  void initState() {
    super.initState();
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
  }

  void _editMember(Map<String, dynamic> data, String docId) {
    setState(() {
      _editingId = docId;
      _nameController.text = data['name'] ?? '';
      _emailController.text = data['email'] ?? '';
      _passwordController.clear(); 
      _selectedColor = data['color'] ?? 'ff2196f3';
      
      String rawRole = (data['role'] ?? 'Barn').toString().toLowerCase();
      if (rawRole == 'admin') {
        _selectedRole = 'Admin';
      } else if (rawRole == 'förälder') {
        _selectedRole = 'Förälder';
      } else {
        _selectedRole = 'Barn'; 
      }
    });
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

    setState(() => _isLoading = true);
    
    // Användardata som ska sparas i Firestore. INGET LÖSENORD HÄR!
    Map<String, dynamic> userData = {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'color': _selectedColor,
      'role': _selectedRole,
    };

    try {
      if (_editingId == null) {
        // **SÄKERHETSFIX: Skapa användare via Firebase Auth istället för att spara lösenord.**
        // En temporär Firebase-app används för att skapa en ny användare utan att logga ut den nuvarande admin-användaren.
        
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
        
        // **FÖRBÄTTRING: Använd UID från Auth som dokument-ID i Firestore.**
        // Detta skapar en direkt koppling mellan autentiseringsprofilen och användardatat.
        userData['created_at'] = FieldValue.serverTimestamp();
        userData['uid'] = uid; // Behålls för enkel åtkomst i regler och querys.
        
        await FirebaseFirestore.instance.collection('users').doc(uid).set(userData);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Medlem skapad säkert!")));
        
      } else {
        // Vid uppdatering ändras bara Firestore-datan, inte lösenordet.
        await FirebaseFirestore.instance.collection('users').doc(_editingId).update(userData);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Medlem uppdaterad!")));
      }
      _resetForm(); 
    } on FirebaseAuthException catch (e) {
      String msg = "Ett fel uppstod vid skapandet av kontot.";
      if (e.code == 'email-already-in-use') msg = "Denna e-postadress används redan.";
      if (e.code == 'invalid-email') msg = "E-postadressen är felaktigt formaterad.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Något gick helt fel: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMember(String docId) async {
    // VARNING: Detta raderar bara användarens data i Firestore, inte själva inloggningskontot i Firebase Auth.
    // För att helt radera en användare krävs admin-rättigheter via en Cloud Function.
    await FirebaseFirestore.instance.collection('users').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    Color textColor = AppTheme.getTextColor();
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Hantera Medlemmar", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Container(
        height: double.infinity, 
        decoration: AppTheme.getBackground(),
        child: SafeArea(
          child: SingleChildScrollView( 
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_editingId == null ? "Lägg till ny medlem" : "Redigera medlem", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 15),
                      const Text("Profilfärg", style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 12, children: _colors.map((colorHex) => GestureDetector(onTap: () => setState(() => _selectedColor = colorHex), child: CircleAvatar(backgroundColor: Color(int.parse(colorHex, radix: 16)), radius: 18, child: _selectedColor == colorHex ? const Icon(Icons.check, color: Colors.white, size: 16) : null))).toList()),
                      const SizedBox(height: 20),
                      
                      _input("Namn", _nameController, Icons.person),
                      const SizedBox(height: 10),
                      
                      _input("E-post", _emailController, Icons.email),
                      const SizedBox(height: 10),
                      
                      if (_editingId == null) ...[
                        _input("Lösenord (minst 6 tecken)", _passwordController, Icons.lock, isObscure: true),
                        const SizedBox(height: 10),
                      ],
                      
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)), child: DropdownButtonHideUnderline(child: DropdownBu