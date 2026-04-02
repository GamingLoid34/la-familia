import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  final TextEditingController _itemController = TextEditingController();

  // Lägg till vara
  Future<void> _addItem() async {
    if (_itemController.text.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection('shopping_list').add({
      'item': _itemController.text.trim(),
      'is_done': false, // Inte köpt än
      'created_at': FieldValue.serverTimestamp(), // För sortering
    });

    _itemController.clear();
  }

  // Växla mellan köpt/inte köpt
  Future<void> _toggleItem(String id, bool currentStatus) async {
    await FirebaseFirestore.instance.collection('shopping_list').doc(id).update(
      {'is_done': !currentStatus},
    );
  }

  // Ta bort vara
  Future<void> _deleteItem(String id) async {
    await FirebaseFirestore.instance
        .collection('shopping_list')
        .doc(id)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inköpslista 🛒"),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              // --- INMATNINGSFÄLT ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Vad behöver vi handla?",
                          hintStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) =>
                            _addItem(), // Lägg till när man trycker Enter
                      ),
                    ),
                    const SizedBox(width: 10),
                    FloatingActionButton(
                      onPressed: _addItem,
                      backgroundColor: const Color(0xFF8BC34A),
                      child: const Icon(Icons.add, color: Colors.black),
                    ),
                  ],
                ),
              ),

              // --- LISTAN ---
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  // Vi sorterar så att "inte köpta" hamnar överst, sen sorterar vi på tid
                  stream: FirebaseFirestore.instance
                      .collection('shopping_list')
                      .orderBy('is_done')
                      .orderBy('created_at', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    var items = snapshot.data!.docs;
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          "Listan är tom! 🙌",
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        var data = items[index].data() as Map<String, dynamic>;
                        String id = items[index].id;
                        String itemText = data['item'] ?? '';
                        bool isDone = data['is_done'] ?? false;

                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: Checkbox(
                              value: isDone,
                              activeColor: const Color(0xFF8BC34A),
                              checkColor: Colors.black,
                              onChanged: (_) => _toggleItem(id, isDone),
                            ),
                            title: Text(
                              itemText,
                              style: TextStyle(
                                color: isDone ? Colors.grey : Colors.white,
                                decoration: isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                fontSize: 18,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _deleteItem(id),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
