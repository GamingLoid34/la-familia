import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../app_theme.dart';

class ManageTemplatesPage extends StatefulWidget {
  const ManageTemplatesPage({super.key});

  @override
  State<ManageTemplatesPage> createState() => _ManageTemplatesPageState();
}

class _ManageTemplatesPageState extends State<ManageTemplatesPage> {
  String _templateType = 'chore'; // 'chore' eller 'activity'
  String _familyId = '';

  // Controllers för formuläret
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _stepController = TextEditingController();
  final TextEditingController _pikController = TextEditingController(); // För aktiviteter

  List<String> _currentSteps = []; // Används som checklist för aktiviteter eller steg för sysslor
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _pikController.text = '📅'; // Standard-emoji
    _loadFamilyId();
  }

  Future<void> _loadFamilyId() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final fid = doc.data()?['familyId'] as String? ?? '';
      if (mounted) setState(() => _familyId = fid);
    } catch (_) {}
  }

  void _addStep() {
    if (_stepController.text.isNotEmpty) {
      setState(() {
        _currentSteps.add(_stepController.text.trim());
        _stepController.clear();
      });
    }
  }

  void _removeStep(int index) {
    setState(() {
      _currentSteps.removeAt(index);
    });
  }

  Future<void> _saveTemplate() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mallen måste ha ett namn"))
      );
      return;
    }

    final collection = _templateType == 'chore' ? 'chore_templates' : 'activity_templates';
    
    Map<String, dynamic> data = {
      'title': _titleController.text.trim(),
      'familyId': _familyId,
    };

    if (_templateType == 'chore') {
      data['steps'] = _currentSteps;
    } else {
      data['piktogram'] = _pikController.text.trim().isEmpty ? '📅' : _pikController.text.trim();
      data['checklist'] = _currentSteps;
    }

    if (_editingId == null) {
      await FirebaseFirestore.instance.collection(collection).add(data);
    } else {
      await FirebaseFirestore.instance.collection(collection).doc(_editingId).update(data);
    }

    _resetForm();
  }

  void _editTemplate(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    setState(() {
      _editingId = doc.id;
      _titleController.text = data['title'] ?? '';
      
      if (_templateType == 'chore') {
        _currentSteps = List<String>.from(data['steps'] ?? []);
      } else {
        _pikController.text = data['piktogram'] ?? '📅';
        _currentSteps = List<String>.from(data['checklist'] ?? []);
      }
    });
  }

  Future<void> _deleteTemplate(String docId) async {
    final collection = _templateType == 'chore' ? 'chore_templates' : 'activity_templates';
    await FirebaseFirestore.instance.collection(collection).doc(docId).delete();
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _titleController.clear();
      _stepController.clear();
      _pikController.text = '📅';
      _currentSteps = [];
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    Color textColor = AppTheme.getTextColor();
    final dayColor = AppTheme.getDayAccentColor();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Hantera Mallar",
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Välj typ av mall
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'chore', label: Text('Sysslor')),
                      ButtonSegment(value: 'activity', label: Text('Aktiviteter')),
                    ],
                    selected: {_templateType},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        _templateType = newSelection.first;
                        _resetForm();
                      });
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return dayColor;
                        return Colors.white;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return Colors.white;
                        return AppTheme.getTextColor();
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // --- FORMULÄR ---
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editingId == null 
                            ? "Skapa ny ${_templateType == 'chore' ? 'sysslomall' : 'aktivitetsmall'}" 
                            : "Redigera mall",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),

                      if (_templateType == 'activity') ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _pikController,
                                decoration: InputDecoration(
                                  labelText: "Emoji",
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                style: const TextStyle(fontSize: 24),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _titleController,
                                decoration: InputDecoration(
                                  labelText: "Aktivitet (t.ex. Fotboll)",
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: "Rubrik (t.ex. Städa rummet)",
                            filled: true,
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 15),
                      Text(
                        _templateType == 'chore' ? "Delmoment:" : "Packlista / Förberedelser:",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ..._currentSteps.asMap().entries.map(
                        (entry) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.check_box_outline_blank, size: 18),
                          title: Text(entry.value),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 18),
                            onPressed: () => _removeStep(entry.key),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _stepController,
                              decoration: const InputDecoration(
                                hintText: "Lägg till objekt...",
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addStep(),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle, color: dayColor),
                            onPressed: _addStep,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (_editingId != null)
                            Expanded(
                              child: TextButton(
                                onPressed: _resetForm,
                                child: const Text("Avbryt"),
                              ),
                            ),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saveTemplate,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dayColor,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text(
                                "SPARA",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                Text(
                  _templateType == 'chore' ? "Dina Sysslomallar" : "Dina Aktivitetsmallar",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 10),

                // --- LISTA PÅ BEFINTLIGA MALLAR ---
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection(_templateType == 'chore' ? 'chore_templates' : 'activity_templates')
                      // Hämta mallar som saknar familyId (gamla) ELLER som tillhör denna familj
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    var docs = snapshot.data!.docs.where((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final fid = d['familyId'] as String? ?? '';
                      return fid.isEmpty || fid == _familyId;
                    }).toList();

                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text("Inga mallar skapade ännu.", style: TextStyle(color: Colors.grey.shade600)),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        var data = docs[index].data() as Map<String, dynamic>;
                        List items = _templateType == 'chore' ? (data['steps'] ?? []) : (data['checklist'] ?? []);
                        String pik = data['piktogram'] ?? '📋';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            leading: _templateType == 'activity' 
                              ? Text(pik, style: const TextStyle(fontSize: 24))
                              : const Icon(Icons.list_alt),
                            title: Text(
                              data['title'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text("${items.length} objekt"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _editTemplate(docs[index]),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteTemplate(docs[index].id),
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
}