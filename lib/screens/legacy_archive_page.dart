import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/family_provider.dart';

class LegacyArchivePage extends StatefulWidget {
  const LegacyArchivePage({super.key});
  @override State<LegacyArchivePage> createState() => _ArchiveState();
}
class _ArchiveState extends State<LegacyArchivePage> {
  String selected = 'chores';
  static const categories = {'chore_log': 'Avklarade sysslor', 'chores': 'Sysslor och växter', 'shopping_items': 'Inköp',
    'meals': 'Mat', 'routines': 'Rutiner'};
  @override Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    final family = user?.familyId;
    final allowed = categories.entries.where((e) => e.key != 'tasks' || user?.isParent == true).toList();
    if (selected == 'tasks' && user?.isParent != true) selected = 'chores';
    return Scaffold(appBar: AppBar(title: const Text('Arkiverade verktyg')),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('Befintliga data är kvar. Här kan du läsa och kopiera dem, men inte ändra dem. Dessa verktyg visas inte i kalenderpiloten.'),
        DropdownButton<String>(value: selected, isExpanded: true,
          items: allowed.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => selected = v!)),
        if (family == null || family.isEmpty) const Text('Ingen familj vald.') else
          Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey('$family/$selected'),
            stream: FirebaseFirestore.instance.collection(selected).where('familyId', isEqualTo: family).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('Kunde inte läsa arkivet. Kontrollera nät och behörighet.');
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!.docs;
              return Column(children: [
                TextButton(onPressed: rows.isEmpty ? null : () async {
                  final text = JsonEncoder.withIndent('  ', (value) => value.toString()).convert(rows.map((d) => {'id': d.id,
                    ...d.data().map((key, value) => MapEntry(key, value is Timestamp ? value.toDate().toIso8601String() : value))}).toList());
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arkivet kopierat.')));
                }, child: const Text('Kopiera som text')),
                if (rows.isEmpty) const Text('Inga sparade poster i denna kategori.'),
                Expanded(child: ListView(children: rows.map((doc) {
                  final d = doc.data();
                  final title = (d['choreTitle'] ?? d['title'] ?? d['chore'] ?? d['name'] ?? d['item'] ?? 'Sparad post').toString();
                  final detail = [d['date'] ?? d['dueDate'], d['time'] ?? d['dueTime'], d['who'] ?? d['ownerName'], d['description']]
                    .where((v) => v != null && v.toString().isNotEmpty).join(' · ');
                  return ListTile(title: Text(title), subtitle: Text(detail));
                }).toList())),
              ]);
            },
          )),
      ])));
  }
}
