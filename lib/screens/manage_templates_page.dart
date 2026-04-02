import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

class ManageTemplatesPage extends StatefulWidget {
  const ManageTemplatesPage({super.key});

  @override
  State<ManageTemplatesPage> createState() => _ManageTemplatesPageState();
}

class _ManageTemplatesPageState extends State<ManageTemplatesPage> {
  // För att lägga till ny mall
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _stepController = TextEditingController();
  List<String> _currentSteps = [];
  String? _editingId; // Om vi redigerar en befintlig

  void _addStep() {
    if (_stepController.text.isNotEmpty) {
      setState(() {
        _currentSteps.add(_stepController.text);
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
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Mallen måste ha ett namn")));
      return;
    }

    Map<String, dynamic> data = {
      'title': _titleController.text, // T.ex. "Städa"
      'steps': _currentSteps, // T.ex. ["Plocka golv", "Bädda"]
    };

    if (_editingId == null) {
      await FirebaseFirestore.instance.collection('chore_templates').add(data);
    } else {
      await FirebaseFirestore.instance
          .collection('chore_templates')
          .doc(_editingId)
          .update(data);
    }

    _resetForm();
  }

  void _editTemplate(DocumentSnapshot doc) {
    var data = doc.data() as Map;
    setState(() {
      _editingId = doc.id;
      _titleController.text = data['title'];
      _currentSteps = List<String>.from(data['steps'] ?? []);
    });
  }

  Future<void> _deleteTemplate(String docId) async {
    await FirebaseFirestore.instance
        .collection('chore_templates')
        .doc(docId)
        .delete();
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _titleController.clear();
      _stepController.clear();
      _currentSteps = [];
    });
    FocusScope.of(context).unfocus(); // Stäng tangentbordet
  }

  @override
  Widget build(BuildContext context) {
    Color textColor = AppTheme.getTextColor();

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
      body: Container(
        height: double.infinity,
        decoration: AppTheme.getBackground(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- FORMULÄR ---
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editingId == null ? "Skapa ny mall" : "Redigera mall",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
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
                      const SizedBox(height: 15),
                      const Text(
                        "Delmoment:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ..._currentSteps.asMap().entries.map(
                        (entry) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.check_box_outline_blank,
                            size: 18,
                          ),
                          title: Text(entry.value),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.red,
                              size: 18,
                            ),
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
                                hintText: "Lägg till steg...",
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addStep(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: Colors.blue,
                            ),
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
                                backgroundColor: Colors.blueAccent,
                              ),
                              child: const Text(
                                "SPARA",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
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
                  "Dina Mallar",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 10),

                // --- LISTA PÅ BEFINTLIGA MALLAR ---
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chore_templates')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    var docs = snapshot.data!.docs;

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        var data = docs[index].data() as Map;
                        List steps = data['steps'] ?? [];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            title: Text(
                              data['title'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text("${steps.length} delmoment"),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _editTemplate(docs[index]),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _deleteTemplate(docs[index].id),
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
      ),
    );
  }
}
