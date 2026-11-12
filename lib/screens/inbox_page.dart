import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/inbox_note.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/date_utils.dart' show dateKey;
import '../utils/planning_list_sort.dart';
import '../utils/inbox_list_sort.dart';
import '../widgets/planning_list_controls.dart';

/// Same two privacy-scoped note queries as Android; children never start them.
class InboxPage extends StatelessWidget {
  const InboxPage({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    if (user == null ||
        !user.isParent ||
        user.familyId?.isNotEmpty != true ||
        FirebaseAuth.instance.currentUser?.uid != user.uid) {
      return const Scaffold(
        body: Center(child: Text('Inkorgen är till för familjens vuxna.')),
      );
    }
    return _InboxContent(
      key: ValueKey('${user.uid}/${user.familyId}'),
      familyId: user.familyId!,
      uid: user.uid,
      members: provider.familyMembers,
    );
  }
}

class _InboxContent extends StatefulWidget {
  const _InboxContent({
    super.key,
    required this.familyId,
    required this.uid,
    required this.members,
  });
  final String familyId, uid;
  final List<UserModel> members;
  @override
  State<_InboxContent> createState() => _InboxContentState();
}

class _InboxContentState extends State<_InboxContent> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _shared, _mine;
  PlanningListSort _sort = PlanningListSort.date;
  String? _personUid;
  @override
  void initState() {
    super.initState();
    final notes = FirebaseFirestore.instance
        .collection('notes')
        .where('familyId', isEqualTo: widget.familyId);
    _shared = notes.where('visibility', isEqualTo: 'family').snapshots();
    _mine = notes.where('ownerUid', isEqualTo: widget.uid).snapshots();
  }

  void _compose(List<QueryDocumentSnapshot<Map<String, dynamic>>> notes) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteComposer(
        familyId: widget.familyId,
        uid: widget.uid,
        members: widget.members,
        knownHashes: notes
            .map((n) => n.data()['contentHash'])
            .whereType<String>()
            .toSet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inkorg')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _shared,
      builder: (context, shared) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _mine,
        builder: (context, mine) {
          if (shared.hasError || mine.hasError) {
            return const Center(
              child: Text(
                'Inkorgen kunde inte läsas. Kontrollera anslutningen och försök igen.',
              ),
            );
          }
          if (!shared.hasData || !mine.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
          for (final doc in [...shared.data!.docs, ...mine.data!.docs]) {
            if (doc.data()['deletedAt'] == null) byId[doc.id] = doc;
          }
          final notes = byId.values.toList();
          final personUid = widget.members.any((m) => m.uid == _personUid)
              ? _personUid
              : null;
          final sections = <Widget>[];
          final now = DateTime.now();
          for (final section in InboxListSection.values) {
            final groups = groupPlanningList(
              notes
                  .where((doc) => inboxListSection(doc.data(), now) == section)
                  .map((doc) {
                    final data = doc.data();
                    return PlanningListItem(
                      value: doc,
                      id: doc.id,
                      title: (data['title'] ?? data['text'] ?? '').toString(),
                      date: inboxListDate(data),
                      aboutUids: planningAboutUids(data),
                    );
                  })
                  .toList(),
              sort: _sort,
              members: widget.members,
              personUid: personUid,
              newestFirst: true,
            );
            if (groups.isEmpty) continue;
            sections.add(
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(
                  section.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            );
            for (final group in groups) {
              if (group.label != null) {
                sections.add(
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      group.label!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                );
              }
              sections.addAll(group.items.map(_noteCard));
            }
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: () => _compose(notes),
                icon: const Icon(Icons.add),
                label: const Text('Klistra in veckobrev eller anteckning'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Granska förslagen innan något läggs till i kalendern eller som uppgift.',
              ),
              const SizedBox(height: 16),
              PlanningListControls(
                sort: _sort,
                onSort: (value) => setState(() => _sort = value),
                personUid: personUid,
                onPerson: (value) => setState(() => _personUid = value),
                members: widget.members,
              ),
              if (_sort == PlanningListSort.week)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Vecka utifrån publiceringsdatum eller när brevet lades till.',
                  ),
                ),
              if (sections.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    personUid == null
                        ? 'Inkorgen är tom.'
                        : 'Inga veckobrev eller anteckningar för den valda personen.',
                  ),
                ),
              ...sections,
            ],
          );
        },
      ),
    ),
  );

  Widget _noteCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = (data['title'] as String?)?.trim();
    final text = (data['text'] as String?)?.trim() ?? '';
    final date = inboxListDate(data);
    final people = planningAboutUids(data);
    final detail = [
      _noteStatus(data),
      if (date != null) dateKey(date),
      if (people.isNotEmpty) planningPeopleLabel(people, widget.members),
    ].join(' · ');
    return Card(
      key: ValueKey('note-${doc.id}'),
      child: ListTile(
        leading: Icon(
          data['visibility'] == 'private'
              ? Icons.lock_outline
              : Icons.inbox_outlined,
        ),
        title: Text(
          title?.isNotEmpty == true ? title! : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(detail),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _NoteDetail(
            note: doc,
            uid: widget.uid,
            familyId: widget.familyId,
          ),
        ),
      ),
    );
  }
}

String _noteStatus(Map<String, dynamic> data) {
  if (inboxInterpretationStuck(data, DateTime.now())) {
    return 'Tolkningen misslyckades';
  }
  switch (data['status']) {
    case 'saved':
      return data['requestId'] == null ? 'Ej tolkad' : 'Väntar på tolkning';
    case 'interpreting':
      return 'Tolkas';
    case 'needs_review':
      return 'Förslag att granska';
    case 'failed':
      return 'Tolkningen misslyckades';
    case 'confirmed':
      return 'Bekräftad';
    case 'dismissed':
      return 'Avfärdad';
    default:
      return 'Anteckning';
  }
}

class _NoteComposer extends StatefulWidget {
  const _NoteComposer({
    required this.familyId,
    required this.uid,
    required this.members,
    required this.knownHashes,
  });
  final String familyId, uid;
  final List<UserModel> members;
  final Set<String> knownHashes;
  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  final _text = TextEditingController();
  final _about = <String>{};
  late final DocumentReference<Map<String, dynamic>> _ref;
  final _requestId = const Uuid().v4();
  bool _private = false, _saving = false, _uncertain = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _ref = FirebaseFirestore.instance.collection('notes').doc();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool _sameSession() {
    final user = context.read<FamilyProvider>().currentUser;
    return user?.uid == widget.uid &&
        user?.familyId == widget.familyId &&
        user?.isParent == true &&
        FirebaseAuth.instance.currentUser?.uid == widget.uid;
  }

  Future<void> _save() async {
    if (_saving || _uncertain || !_sameSession()) return;
    final text = _text.text.trim();
    if (text.isEmpty || text.length > 10000) {
      setState(
        () => _error = text.isEmpty
            ? 'Skriv eller klistra in något först.'
            : 'Texten får vara högst 10 000 tecken.',
      );
      return;
    }
    if (widget.knownHashes.contains(noteContentHash(text))) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Texten finns redan i inkorgen'),
          content: const Text('Vill du spara den en gång till?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Spara ändå'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted || !_sameSession()) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fields = newInboxNote(
        familyId: widget.familyId,
        uid: widget.uid,
        text: text,
        isPrivate: _private,
        aboutUids: _about.toList(),
        requestId: _requestId,
        createdAt: FieldValue.serverTimestamp(),
      );
      await _ref.set(fields).timeout(const Duration(seconds: 10));
      if (mounted && _sameSession()) Navigator.pop(context);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error =
              'Sparningen kunde inte bekräftas. Stäng formuläret och kontrollera inkorgen.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Sparningen kunde inte bekräftas. Kontrollera inkorgen innan du försöker igen.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      final current = context.watch<FamilyProvider>().currentUser;
      if (snapshot.data?.uid != widget.uid ||
          current?.uid != widget.uid ||
          current?.familyId != widget.familyId) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Kontot har bytts. Öppna inkorgen igen.'),
          ),
        );
      }
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ny anteckning',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  minLines: 4,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Klistra in texten',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Vem gäller det?'),
                Wrap(
                  spacing: 8,
                  children: widget.members
                      .map(
                        (m) => FilterChip(
                          label: Text(m.name),
                          selected: _about.contains(m.uid),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _about.add(m.uid);
                            } else {
                              _about.remove(m.uid);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
                SwitchListTile(
                  title: const Text('Privat anteckning'),
                  value: _private,
                  subtitle: const Text(
                    'Originalet visas bara för dig. Bekräftade förslag kan bli gemensamma.',
                  ),
                  onChanged: (value) => setState(() => _private = value),
                ),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving || _uncertain ? null : _save,
                  child: Text(_saving ? 'Sparar…' : 'Spara och tolka'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _NoteDetail extends StatefulWidget {
  const _NoteDetail({
    required this.note,
    required this.uid,
    required this.familyId,
  });
  final QueryDocumentSnapshot<Map<String, dynamic>> note;
  final String uid, familyId;
  @override
  State<_NoteDetail> createState() => _NoteDetailState();
}

class _NoteDetailState extends State<_NoteDetail> {
  final _selected = <String>{};
  bool _busy = false;
  String? _message;
  bool _sameSession() {
    final user = context.read<FamilyProvider>().currentUser;
    return user?.uid == widget.uid &&
        user?.familyId == widget.familyId &&
        user?.isParent == true &&
        FirebaseAuth.instance.currentUser?.uid == widget.uid;
  }

  Future<void> _retry() async {
    if (_busy || !_sameSession()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.note.reference.update({
        'status': 'saved',
        'requestId': const Uuid().v4(),
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Kunde inte begära tolkning. Försök igen.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(
    Map<String, dynamic> note,
    List<Map<String, dynamic>> actions,
  ) async {
    if (_busy || !_sameSession()) return;
    final valid = actions
        .where((a) => a['blockedReason'] == null && _selected.contains(a['id']))
        .map((a) => a['id'] as String)
        .toList();
    final revision = (note['interpretation'] as Map?)?['revision'];
    if (valid.isEmpty || revision is! num) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('confirmNoteActions')
          .call({
            'noteId': widget.note.id,
            'revision': revision.toInt(),
            'actionIds': valid,
          });
      final data = result.data as Map? ?? {};
      final applied = (data['applied'] as List? ?? []).length;
      final skipped = (data['skipped'] as List? ?? [])
          .whereType<Map>()
          .toList();
      final reason = skipped.isNotEmpty
          ? skipped.first['reason']?.toString()
          : null;
      if (mounted) {
        setState(
          () => _message = applied == 0
              ? (reason ?? 'Inget kunde sparas.')
              : '$applied förslag sparade.${reason == null ? '' : ' $reason'}',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Kunde inte bekräfta förslagen. Kontrollera anslutningen och försök igen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || !_sameSession()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort anteckningen?'),
        content: const Text(
          'Aktiviteter och uppgifter som redan skapats finns kvar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || !_sameSession()) return;
    setState(() => _busy = true);
    try {
      await widget.note.reference.update({
        'deletedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Kunde inte ta bort anteckningen.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, auth) {
      final current = context.watch<FamilyProvider>().currentUser;
      if (auth.data?.uid != widget.uid ||
          current?.uid != widget.uid ||
          current?.familyId != widget.familyId) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Kontot har bytts. Öppna inkorgen igen.'),
          ),
        );
      }
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: widget.note.reference.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Anteckningen kunde inte läsas.'),
              ),
            );
          }
          final note = snapshot.data?.data() ?? widget.note.data();
          final actions = pendingNoteActions(note);
          final status = note['status'];
          final since = note['interpretingSince'];
          final stuck =
              status == 'interpreting' &&
              since is Timestamp &&
              DateTime.now().difference(since.toDate()) >
                  const Duration(minutes: 5);
          final canRetry =
              status == 'failed' ||
              (status == 'saved' && note['requestId'] == null) ||
              stuck;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      note['visibility'] == 'private'
                          ? '🔒 Privat anteckning'
                          : '📥 Anteckning',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    SelectableText(note['text'] as String? ?? ''),
                    const SizedBox(height: 8),
                    Text(_noteStatus(note)),
                    if (status == 'needs_review') ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Välj vad som ska sparas. Aktiviteter och uppgifter som skapas blir gemensamma för familjen.',
                      ),
                      ...actions.map((action) {
                        final id = action['id'] as String;
                        final blocked = action['blockedReason'] as String?;
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(action['title'] as String? ?? 'Förslag'),
                          subtitle: (blocked ?? action['summary']) == null
                              ? null
                              : Text((blocked ?? action['summary']).toString()),
                          value: _selected.contains(id),
                          onChanged: blocked != null || _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected == true) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                }),
                        );
                      }),
                      FilledButton(
                        onPressed: _busy || _selected.isEmpty
                            ? null
                            : () => _confirm(note, actions),
                        child: const Text('Spara valda förslag'),
                      ),
                    ],
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_message!),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _busy ? null : _delete,
                          child: const Text('Ta bort'),
                        ),
                        const Spacer(),
                        if (canRetry)
                          OutlinedButton(
                            onPressed: _busy ? null : _retry,
                            child: const Text('Tolka igen'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
