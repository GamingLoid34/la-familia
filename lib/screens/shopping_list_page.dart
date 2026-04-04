import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../app_theme.dart';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});
  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  final _ctrl = TextEditingController();
  String _familyId = '';

  // Stream — no composite index required: sort client-side
  final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('shopping_items')
      .snapshots();

  @override
  void initState() {
    super.initState();
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

  Future<void> _addItem() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      await FirebaseFirestore.instance.collection('shopping_items').add({
        'title': text,
        'isDone': false,
        'timestamp': FieldValue.serverTimestamp(),
        'familyId': _familyId,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggle(String id, bool current) async {
    await FirebaseFirestore.instance
        .collection('shopping_items')
        .doc(id)
        .update({'isDone': !current});
  }

  Future<void> _delete(String id) async {
    await FirebaseFirestore.instance
        .collection('shopping_items')
        .doc(id)
        .delete();
  }

  void _showAddDialog() {
    _ctrl.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Lägg till vara'),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Vad behöver vi handla?',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (_) {
            _addItem();
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.getDayAccentColor(),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              _addItem();
              Navigator.pop(ctx);
            },
            child: const Text('Lägg till'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    return Scaffold(
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
        decoration: AppTheme.getBackground(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: dayColor,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_rounded,
                        color: textColor),
                  ),
                  const SizedBox(width: 12),
                  Text('Inköpslista 🛒',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: textColor)),
                ]),
              ),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: _stream,
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('Fel: ${snap.error}',
                            style: const TextStyle(color: Colors.red)),
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                final docs = (snap.data?.docs ?? [])
                  ..sort((a, b) {
                    // Not-done items first
                    final aDone = (a.data() as Map)['isDone'] == true ? 1 : 0;
                    final bDone = (b.data() as Map)['isDone'] == true ? 1 : 0;
                    return aDone.compareTo(bDone);
                  });

                if (docs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(children: [
                        const Text('🛒', style: TextStyle(fontSize: 52)),
                        const SizedBox(height: 16),
                        Text('Listan är tom!',
                            style: AppTheme.sectionTitleStyle),
                        const SizedBox(height: 8),
                        Text('Tryck + för att lägga till en vara.',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 13)),
                      ]),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final doc = docs[i];
                      final d = doc.data() as Map<String, dynamic>;
                      final title = d['title'] as String? ?? '';
                      final isDone = d['isDone'] == true;

                      return Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        decoration: AppTheme.cardDecoration(radius: 16),
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          leading: GestureDetector(
                            onTap: () => _toggle(doc.id, isDone),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: isDone ? dayColor : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDone
                                      ? dayColor
                                      : Colors.grey.shade400,
                                  width: 2,
                                ),
                              ),
                              child: isDone
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 16)
                                  : null,
                            ),
                          ),
                          title: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isDone
                                  ? Colors.grey.shade400
                                  : AppTheme.getTextColor(),
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded,
                                color: Colors.grey.shade400, size: 20),
                            onPressed: () => _delete(doc.id),
                          ),
                          onTap: () => _toggle(doc.id, isDone),
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ))),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: dayColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
