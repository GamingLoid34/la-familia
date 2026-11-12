import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/family_provider.dart';
import '../utils/event_actions.dart';
import '../utils/permissions.dart';
import '../utils/recurrence.dart';
import '../widgets/activity_detail_sheet.dart';

class RecurringActivitiesPage extends StatelessWidget {
  const RecurringActivitiesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    final family = user?.familyId;
    if (user == null || family == null || family.isEmpty) {
      return const Scaffold(body: Center(child: Text('Ingen familj vald.')));
    }
    return _RecurringActivitiesList(
      key: ValueKey('${user.uid}/$family'),
      familyId: family,
    );
  }
}

class _RecurringActivitiesList extends StatefulWidget {
  const _RecurringActivitiesList({super.key, required this.familyId});
  final String familyId;
  @override
  State<_RecurringActivitiesList> createState() =>
      _RecurringActivitiesListState();
}

class _RecurringActivitiesListState extends State<_RecurringActivitiesList> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _events;

  @override
  void initState() {
    super.initState();
    _events = context
        .read<FamilyProvider>()
        .plannerEvents()
        .where('familyId', isEqualTo: widget.familyId)
        .where('isRecurring', isEqualTo: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    if (user == null || user.familyId != widget.familyId) {
      return const Scaffold(body: Center(child: Text('Ingen familj vald.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Återkommande')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _events,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Kunde inte läsa återkommande aktiviteter.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs.toList()
            ..sort(
              (a, b) => (a.data()['title'] as String? ?? '').compareTo(
                b.data()['title'] as String? ?? '',
              ),
            );
          if (docs.isEmpty) {
            return const Center(child: Text('Inget upprepas just nu.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Aktiviteter som upprepas i familjens kalender.'),
              ...docs.map((doc) {
                final data = doc.data();
                final names = (data['persons'] as List? ?? [])
                    .whereType<String>()
                    .join(', ');
                final subtitle = [
                  recurrenceLabel(data),
                  if (names.isNotEmpty) names,
                  if ((data['time'] as String? ?? '').isNotEmpty)
                    data['time'] as String,
                ].join(' · ');
                return Card(
                  child: ListTile(
                    leading: Text(
                      data['piktogram'] as String? ?? '📅',
                      style: const TextStyle(fontSize: 23),
                    ),
                    title: Text(data['title'] as String? ?? 'Aktivitet'),
                    subtitle: Text(subtitle),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ActivityDetailSheet(docSnapshot: doc),
                    ),
                    trailing: canEditDoc(user, data)
                        ? PopupMenuButton<String>(
                            onSelected: (action) => handleEventMenuAction(
                              context,
                              action: action,
                              doc: doc,
                              listDay: DateTime.now(),
                              familyMembers: provider.familyMembers,
                              familyId: widget.familyId,
                            ),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Redigera'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Ta bort'),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
