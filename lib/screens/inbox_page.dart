import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../navigation/app_navigation.dart';
import '../providers/family_provider.dart';
import '../services/note_service.dart';
import '../utils/layout.dart';
import '../widgets/compose_note_sheet.dart';
import '../widgets/vardag_header.dart';

/// Snabbvägen från Hem (📝 bredvid vädret): ny anteckning med tangentbordet
/// uppe. Ingen dubblettfråga, som i Android. Vid lyckad sparning visas
/// "Sparad i Inkorgen." med **Öppna**.
Future<void> openQuickNote(BuildContext context) async {
  final p = context.read<FamilyProvider>();
  final me = p.currentUser;
  final fid = me?.familyId ?? '';
  if (me == null || !me.isParent || fid.isEmpty) return;
  final note = await showComposeNoteSheet(
    context,
    people: p.familyMembers,
    autoFocus: true,
    hint: 'Hamnar i Inkorgen. Där kan du göra om den till en aktivitet eller syssla.',
  );
  if (note == null || !context.mounted) return;
  try {
    await NoteService.add(
      familyId: fid,
      ownerUid: me.uid,
      text: note.text,
      isPrivate: note.isPrivate,
      aboutUids: note.aboutUids,
    );
    if (!context.mounted) return;
    showVardagSnack(
      context,
      'Sparad i Inkorgen.',
      actionLabel: 'Öppna',
      onAction: () => AppNavigation.openInMer(context, MerRoute.inbox),
    );
  } catch (e) {
    if (context.mounted) {
      showVardagSnack(context, 'Kunde inte spara: ${_errorText(e)}', isError: true);
    }
  }
}

String _errorText(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  if (e is FirebaseException) return e.message ?? e.code;
  return e.toString();
}

String _firstNames(List<UserModel> members, List<String> uids) {
  final names = <String>[];
  for (final uid in uids) {
    for (final m in members) {
      if (m.uid == uid) names.add(m.name.split(' ').first);
    }
  }
  return names.join(', ');
}

/// Inkorgen under Mer (Androids `InboxScreen`). Bara för vuxna.
class InboxPage extends StatefulWidget {
  /// Öppna "Ny anteckning" direkt när sidan visas.
  final bool openCompose;
  const InboxPage({super.key, this.openCompose = false});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  /// Anteckningar med en pågående åtgärd — skyddar mot dubbeltryck.
  final Set<String> _busy = {};

  /// Valda förslag per (anteckning, revision). En ny revision nollställer
  /// valet, så att gamla val aldrig följer med till nya förslag.
  final Map<String, Set<String>> _selected = {};

  @override
  void initState() {
    super.initState();
    if (widget.openCompose) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _compose());
    }
  }

  FamilyProvider get _p => context.read<FamilyProvider>();

  void _info(String m) => showVardagSnack(context, m);
  void _error(String m) => showVardagSnack(context, m, isError: true);

  /// Kör [action] för en anteckning, en i taget.
  Future<void> _run(String noteId, String failureText,
      Future<void> Function() action) async {
    if (_busy.contains(noteId)) return;
    setState(() => _busy.add(noteId));
    try {
      await action();
    } catch (e) {
      if (mounted) _error('$failureText: ${_errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy.remove(noteId));
    }
  }

  // ─── Ny anteckning med dubblettkontroll ────────────────────────────────
  Future<void> _compose() async {
    final me = _p.currentUser;
    final fid = me?.familyId ?? '';
    if (me == null || !me.isParent) {
      _error('Bara familjens vuxna kan använda inkorgen.');
      return;
    }
    if (fid.isEmpty) {
      _error('Ingen familj vald.');
      return;
    }
    final note = await showComposeNoteSheet(context, people: _p.familyMembers);
    if (note == null || !mounted) return;
    if (note.text.trim().isEmpty) {
      _error('Skriv eller klistra in något först.');
      return;
    }
    // Ett fel i dubblettkontrollen stoppar inte sparningen (som i Android).
    NoteModel? existing;
    try {
      final dups = await NoteService.findDuplicates(
          familyId: fid, uid: me.uid, text: note.text);
      existing = dups.isEmpty ? null : dups.first;
    } catch (_) {}
    if (!mounted) return;
    if (existing != null) {
      final when = existing.createdAt != null
          ? DateFormat('d MMMM', 'sv').format(existing.createdAt!)
          : null;
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Texten finns redan'),
          content: Text(when != null
              ? 'Du sparade samma text $when. Vill du spara den igen?'
              : 'Samma text finns redan i inkorgen. Vill du spara den igen?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Spara ändå')),
          ],
        ),
      );
      if (again != true || !mounted) return;
    }
    try {
      await NoteService.add(
        familyId: fid,
        ownerUid: me.uid,
        text: note.text,
        isPrivate: note.isPrivate,
        aboutUids: note.aboutUids,
      );
      if (mounted) _info('Sparad. Tolkningen startar.');
    } catch (e) {
      if (mounted) _error('Kunde inte spara: ${_errorText(e)}');
    }
  }

  // ─── Åtgärder på en anteckning ─────────────────────────────────────────
  Future<void> _retry(NoteModel n) async {
    final blocked = NoteStatusMachine.requestBlockedReason(n);
    if (blocked != null) {
      _error(blocked);
      return;
    }
    await _run(n.id, 'Kunde inte begära en ny tolkning',
        () => NoteService.requestInterpretation(n.id));
  }

  Future<void> _confirm(NoteModel n, List<String> actionIds) async {
    final revision = n.interpretation?.revision;
    if (revision == null || actionIds.isEmpty) {
      _error('Välj något att bekräfta först.');
      return;
    }
    await _run(n.id, 'Kunde inte bekräfta', () async {
      final result = await NoteService.confirmActions(
          noteId: n.id, revision: revision, actionIds: actionIds);
      if (!mounted) return;
      final s = result.summary();
      if (result.skipped.isNotEmpty) {
        await _showResult(n, result);
      } else if (s.isError) {
        _error(s.message);
      } else {
        _info(s.message);
      }
    });
  }

  /// Resultat per åtgärd, inklusive överhoppade och varför.
  Future<void> _showResult(NoteModel n, ConfirmResult r) {
    final actions = {
      for (final a in n.interpretation?.actions ?? const <NoteAction>[]) a.id: a
    };
    String label(String id) {
      final a = actions[id];
      if (a == null) return 'Förslag';
      return '${a.typeIcon} ${a.title}'.trim();
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Så gick det'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in r.applied)
                _ResultRow(
                    icon: a.alreadyDone ? '↺' : '✅',
                    title: label(a.actionId),
                    detail: a.alreadyDone ? 'Fanns redan.' : 'Sparad.'),
              for (final s in r.skipped)
                _ResultRow(
                    icon: '⚠️', title: label(s.actionId), detail: s.reason),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Stäng')),
        ],
      ),
    );
  }

  Future<void> _delete(NoteModel n, {required bool withCreated}) async {
    if (withCreated) {
      await _run(n.id, 'Kunde inte ta bort allt', () async {
        final removed = await NoteService.deleteWithCreated(n);
        if (!mounted) return;
        _info(switch (removed) {
          0 => 'Borttagen.',
          1 => 'Borttagen med 1 skapad post.',
          _ => 'Borttagen med $removed skapade poster.',
        });
      });
    } else {
      await _run(n.id, 'Kunde inte ta bort', () async {
        await NoteService.softDelete(n.id);
        if (!mounted) return;
        _info(n.linkedIds.isEmpty
            ? 'Borttagen.'
            : 'Borttagen. Skapade poster finns kvar.');
      });
    }
  }

  /// Frågar hur anteckningen ska tas bort. Returnerar sant om något valdes.
  Future<bool> _askDelete(NoteModel n) async {
    final hasCreated = n.linkedIds.isNotEmpty;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort anteckningen?'),
        content: Text(hasCreated
            ? 'Det som skapades från den kan tas bort samtidigt, eller ligga kvar.'
            : 'Anteckningen försvinner ur inkorgen.'),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          if (hasCreated)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB3261E)),
              child: const Text('Anteckningen och det som skapades'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'note'),
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            child: Text(hasCreated ? 'Bara anteckningen' : 'Ta bort'),
          ),
        ],
      ),
    );
    if (choice == null) return false;
    await _delete(n, withCreated: choice == 'all');
    return true;
  }

  Future<void> _edit(NoteModel n) async {
    final result = await showComposeNoteSheet(
      context,
      people: _p.familyMembers,
      title: 'Ändra anteckning',
      initialText: n.text,
      initialPrivate: n.isPrivate,
      initialAboutUids: n.aboutUids,
      hint: n.linkedIds.isNotEmpty
          ? 'Det som redan skapats från anteckningen ligger kvar. Den ändrade texten tolkas på nytt.'
          : 'Den ändrade texten tolkas på nytt.',
    );
    if (result == null || !mounted) return;
    if (result.text.trim().isEmpty) {
      _error('Anteckningen kan inte vara tom.');
      return;
    }
    await _run(n.id, 'Kunde inte spara ändringen', () async {
      final outcome = await NoteService.editNote(n,
          text: result.text,
          isPrivate: result.isPrivate,
          aboutUids: result.aboutUids);
      if (!mounted) return;
      switch (outcome) {
        case EditOutcome.unchanged:
          break; // Ingenting ändrat — ingen kopia, inget besked.
        case EditOutcome.replaced:
          _info('Ändrad. Tolkningen startar om.');
        case EditOutcome.oldNotRemoved:
          _error('Den ändrade anteckningen sparades, men den gamla kunde inte '
              'tas bort. Båda ligger nu i Inkorgen — ta bort den gamla för hand.');
      }
    });
  }

  Future<void> _openDetail(NoteModel n) => showProtectedSheet<void>(
        context,
        builder: (_) => _NoteDetailSheet(
          noteId: n.id,
          isBusy: (id) => _busy.contains(id),
          onDelete: (note) async {
            final nav = Navigator.of(context);
            if (await _askDelete(note)) nav.maybePop();
          },
          onEdit: (note) async {
            Navigator.of(context).maybePop();
            await _edit(note);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FamilyProvider>();
    final me = p.currentUser;
    final isParent = me?.isParent == true;
    final c = AppTheme.colors();

    Widget body;
    if (!isParent) {
      body = _CenterText('Inkorgen är till för familjens vuxna.', c.onPage);
    } else if (!p.notesLoaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.notesError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: VardagCard(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'Inkorgen kunde inte läsas. Det beror oftast på att behörigheterna inte är på plats än.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.onCardPrimary),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: p.retryAdultData,
                style: FilledButton.styleFrom(backgroundColor: c.accent),
                child: const Text('Försök igen'),
              ),
            ]),
          ),
        ),
      );
    } else {
      final now = DateTime.now();
      final visible = p.inboxNotes.where((n) => !n.isDeleted).toList();
      final review = visible.where((n) => n.needsReview).toList();
      final failed = visible.where((n) => n.failed || n.isStuck(now)).toList();
      final handled = visible
          .where((n) => !n.needsReview && !n.failed && !n.isStuck(now))
          .toList();
      if (visible.isEmpty) {
        body = _CenterText(
            'Klistra in ett veckobrev eller en påminnelse, så plockar appen ut det som behöver göras.',
            c.onPage);
      } else {
        body = ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (review.isNotEmpty) ...[
              const VardagSectionLabel('ATT GRANSKA'),
              for (final n in review)
                _ReviewCard(
                  note: n,
                  members: p.familyMembers,
                  busy: _busy.contains(n.id),
                  selected: _selected.putIfAbsent(
                      '${n.id}#${n.interpretation?.revision ?? 0}', () => {}),
                  onChanged: () => setState(() {}),
                  onOpen: () => _openDetail(n),
                  onRetry: () => _retry(n),
                  onConfirm: (ids) => _confirm(n, ids),
                  onDelete: () => _askDelete(n),
                ),
            ],
            if (failed.isNotEmpty) ...[
              const VardagSectionLabel('MISSLYCKADES'),
              for (final n in failed)
                _FailedCard(
                  note: n,
                  busy: _busy.contains(n.id),
                  onOpen: () => _openDetail(n),
                  onRetry: () => _retry(n),
                  onDelete: () => _delete(n, withCreated: false),
                ),
            ],
            if (handled.isNotEmpty) ...[
              const VardagSectionLabel('KLART'),
              for (final n in handled)
                _HandledCard(
                  note: n,
                  onOpen: () => _openDetail(n),
                  onDelete: () => _askDelete(n),
                ),
            ],
          ],
        );
      }
    }

    return Scaffold(
      backgroundColor: c.pageBackground,
      floatingActionButton: isParent
          ? FloatingActionButton(
              tooltip: 'Ny anteckning',
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              elevation: AppTheme.lowStimuli ? 0 : 6,
              onPressed: _compose,
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: WindowSize.of(context).isExpanded
                  ? WindowSize.settingsMaxWidth
                  : double.infinity),
          child: Column(children: [
            VardagTitleHeader(
                title: 'Inkorg', onBack: () => Navigator.of(context).maybePop()),
            Expanded(child: body),
          ]),
        ),
      ),
    );
  }
}

class _CenterText extends StatelessWidget {
  final String text;
  final Color color;
  const _CenterText(this.text, this.color);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: color)),
        ),
      );
}

class _ResultRow extends StatelessWidget {
  final String icon;
  final String title;
  final String detail;
  const _ResultRow(
      {required this.icon, required this.title, required this.detail});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 28, child: Text(icon)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(detail, style: TextStyle(color: AppTheme.getSubTextColor())),
            ]),
          ),
        ]),
      );
}

String _noteHeader(NoteModel n) =>
    n.isPrivate ? '🔒 Privat anteckning' : '📥 Anteckning';

class _ReviewCard extends StatefulWidget {
  final NoteModel note;
  final List<UserModel> members;
  final bool busy;
  final Set<String> selected;
  final VoidCallback onChanged;
  final VoidCallback onOpen;
  final VoidCallback onRetry;
  final void Function(List<String>) onConfirm;
  final VoidCallback onDelete;

  const _ReviewCard({
    required this.note,
    required this.members,
    required this.busy,
    required this.selected,
    required this.onChanged,
    required this.onOpen,
    required this.onRetry,
    required this.onConfirm,
    required this.onDelete,
  });

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _showText = false;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    final n = widget.note;
    final actions = n.interpretation?.actions ?? const <NoteAction>[];
    final chosen = actions
        .where((a) => widget.selected.contains(a.id) && !a.isBlocked)
        .map((a) => a.id)
        .toList();
    final question = n.interpretation?.question;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: VardagCard(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: widget.onOpen,
              child: Row(children: [
                Expanded(
                  child: Text(_noteHeader(n),
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: c.onCardPrimary)),
                ),
                TextButton(
                  onPressed: () => setState(() => _showText = !_showText),
                  child: Text(_showText ? 'Dölj text' : 'Visa text'),
                ),
              ]),
            ),
            if (_showText)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: SelectableText(n.text,
                    style: TextStyle(color: c.onCardPrimary)),
              )
            else
              InkWell(
                onTap: widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 6),
                  child: Text(n.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.onCardSecondary)),
                ),
              ),
            if (question != null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: Text('❓ $question',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: c.onCardPrimary)),
              ),
            if (actions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('Ingenting att göra i den här texten.',
                    style: TextStyle(color: c.onCardSecondary)),
              ),
            for (final a in actions)
              _ActionRow(
                action: a,
                selected: widget.selected.contains(a.id),
                enabled: !widget.busy,
                onChanged: (v) {
                  v ? widget.selected.add(a.id) : widget.selected.remove(a.id);
                  widget.onChanged();
                },
              ),
            if (n.isPrivate && actions.any((a) => !a.isBlocked))
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(
                    'Det du sparar blir synligt för familjen. Texten ovan förblir privat.',
                    style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
              ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: widget.busy ? null : widget.onDelete,
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB3261E)),
                  child: const Text('Ta bort'),
                ),
                TextButton(
                  onPressed: widget.busy ? null : widget.onRetry,
                  child: const Text('Tolka om'),
                ),
                FilledButton(
                  onPressed: widget.busy || chosen.isEmpty
                      ? null
                      : () => widget.onConfirm(chosen),
                  style: FilledButton.styleFrom(backgroundColor: c.accent),
                  child: widget.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Spara valda'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final NoteAction action;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ActionRow({
    required this.action,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    final sub = action.blockedReason ?? action.summary;
    return InkWell(
      onTap: action.isBlocked || !enabled ? null : () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 40,
            height: 40,
            child: action.isBlocked
                ? const Center(child: Text('⚠️'))
                : Checkbox(
                    value: selected,
                    activeColor: c.accent,
                    onChanged: enabled ? (v) => onChanged(v == true) : null,
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 9, right: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${action.typeIcon} ${action.title}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: c.onCardPrimary)),
                if (sub != null)
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12,
                          color: action.isBlocked
                              ? const Color(0xFF8A6D3B)
                              : c.onCardSecondary)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  final NoteModel note;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _FailedCard({
    required this.note,
    required this.busy,
    required this.onOpen,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: VardagCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: onOpen,
            child: Text(note.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.onCardPrimary)),
          ),
          const SizedBox(height: 6),
          Text('Tolkningen gick inte igenom. Texten finns kvar.',
              style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: busy ? null : onDelete,
              style:
                  TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
              child: const Text('Ta bort'),
            ),
            TextButton(
              onPressed: busy ? null : onRetry,
              child: Text(busy ? '…' : 'Försök igen'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _HandledCard extends StatelessWidget {
  final NoteModel note;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _HandledCard(
      {required this.note, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: VardagCard(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            child: Row(children: [
              Text(note.isBusy ? '⏳' : '✅', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(note.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: c.onCardPrimary)),
                  Text(note.isBusy ? 'Tolkas just nu…' : 'Behandlad',
                      style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
                ]),
              ),
              if (!note.isBusy)
                IconButton(
                  tooltip: 'Ta bort',
                  icon: Icon(Icons.delete_outline_rounded, color: c.onCardIcon),
                  onPressed: onDelete,
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Fullständig anteckning: markerbar originaltext, datum, berörda personer
/// och vad som hänt. **Ändra** och **Ta bort** syns direkt. Läser anteckningen
/// live, och stänger sig själv om den försvinner.
class _NoteDetailSheet extends StatelessWidget {
  final String noteId;
  final bool Function(String) isBusy;
  final void Function(NoteModel) onDelete;
  final void Function(NoteModel) onEdit;

  const _NoteDetailSheet({
    required this.noteId,
    required this.isBusy,
    required this.onDelete,
    required this.onEdit,
  });

  static String _linkText(NoteLink l) {
    switch (l.type) {
      case 'event':
        return '📅 En aktivitet skapades.';
      case 'task':
        return '📌 En uppgift skapades.';
      case 'checklist_item':
        return '☐ "${l.rowId ?? ''}" lades till i en packlista.';
      case 'exception':
        return '🚫 Ett tillfälle ställdes in${l.occurrenceDate != null ? ' (${l.occurrenceDate})' : ''}.';
      default:
        return '• Något skapades.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FamilyProvider>();
    final matches =
        p.inboxNotes.where((n) => n.id == noteId && !n.isDeleted).toList();
    if (matches.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final n = matches.first;
    final c = AppTheme.colors();
    final meta = <String>[
      if (n.createdAt != null)
        "Skriven ${DateFormat("d MMMM 'kl.' HH:mm", 'sv').format(n.createdAt!)}",
      if (n.aboutUids.isNotEmpty) 'Gäller ${_firstNames(p.familyMembers, n.aboutUids)}',
    ].join(' · ');
    final busy = isBusy(n.id) || n.isBusy;

    return SheetFrame(
      title: _noteHeader(n),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (meta.isNotEmpty)
            Text(meta, style: TextStyle(fontSize: 13, color: c.onCardSecondary)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: SelectableText(n.text,
                  style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
          ),
          const SizedBox(height: 14),
          Text(noteStatusText(n),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (n.failed && n.interpretationError != null)
            Text(n.interpretationError!,
                style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
          for (final l in n.linkedIds)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_linkText(l),
                  style: TextStyle(fontSize: 13, color: c.onCardSecondary)),
            ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => onDelete(n),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB3261E),
                  side: const BorderSide(color: Color(0x80B3261E)),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Ta bort'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => onEdit(n),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Ändra'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
