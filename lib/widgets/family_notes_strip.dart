import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/family_note.dart';
import '../providers/family_provider.dart';
import 'add_family_note_sheet.dart';

String _relativeTime(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return 'nyss';
  if (diff.inMinutes < 60) return 'för ${diff.inMinutes} min sedan';
  if (diff.inHours < 24) return 'för ${diff.inHours}h sedan';
  return 'för ${diff.inDays}d sedan';
}

/// Komprimerad dagstavla: ihopfälld pill, expandera inline. Startar alltid ihop.
class FamilyNotesStrip extends StatefulWidget {
  const FamilyNotesStrip({super.key});

  @override
  State<FamilyNotesStrip> createState() => _FamilyNotesStripState();
}

class _FamilyNotesStripState extends State<FamilyNotesStrip> {
  bool _expanded = false;
  /// Note-id:n som var synliga vid senaste expandering (för oläst-badge).
  Set<String> _seenIds = {};

  Future<void> _openAdd(BuildContext context, FamilyProvider provider) async {
    final user = provider.currentUser;
    final fid = user?.familyId;
    if (user == null || fid == null || fid.isEmpty) return;
    await AddFamilyNoteSheet.show(
      context,
      familyId: fid,
      user: user,
      todayNotes: provider.todayNotes,
    );
  }

  Future<void> _confirmDelete(BuildContext context, FamilyNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort notis?'),
        content: const Text('Notisen försvinner för hela familjen.'),
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
    if (ok != true) return;
    await FirebaseFirestore.instance
        .collection('family_notes')
        .doc(note.id)
        .delete();
  }

  void _toggle(List<FamilyNote> notes) {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _seenIds = notes.map((n) => n.id).toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FamilyProvider>(
      builder: (context, provider, _) {
        final notes = provider.todayNotes;
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final unread = notes.where((n) => !_seenIds.contains(n.id)).length;
        final dayColor = AppTheme.getDayAccentColor();

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _toggle(notes),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: dayColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('💬', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            notes.isEmpty
                                ? '+'
                                : '${notes.length} ${notes.length == 1 ? 'lapp' : 'lappar'} idag',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.getTextColor(),
                            ),
                          ),
                          if (!_expanded && notes.isNotEmpty && unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: dayColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 88,
                  child: notes.isEmpty
                      ? _EmptyNotesRow(
                          onAdd: () => _openAdd(context, provider))
                      : ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _AddNoteChip(
                                onTap: () => _openAdd(context, provider)),
                            const SizedBox(width: 10),
                            ...notes.map((n) {
                              final color = AppTheme.colorFromHex(
                                n.fromColor.isNotEmpty
                                    ? n.fromColor
                                    : AppTheme.memberColorPalette.first,
                              );
                              final isMine =
                                  myUid != null && n.fromUid == myUid;
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _NoteCard(
                                  note: n,
                                  accent: color,
                                  timeLabel: _relativeTime(n.createdAt),
                                  onTap: isMine
                                      ? () => _confirmDelete(context, n)
                                      : null,
                                ),
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EmptyNotesRow extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyNotesRow({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AddNoteChip(onTap: onAdd),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: AppTheme.cardDecoration(radius: 16),
              child: Text(
                'Inga noteringar idag. Lägg till en?',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddNoteChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AddNoteChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    return Material(
      color: dayColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 72,
          height: 88,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: dayColor, size: 28),
              const SizedBox(height: 4),
              Text(
                'Lägg till',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: dayColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final FamilyNote note;
  final Color accent;
  final String timeLabel;
  final VoidCallback? onTap;

  const _NoteCard({
    required this.note,
    required this.accent,
    required this.timeLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.cardDecoration(radius: 16).copyWith(
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.fromName.split(' ').first,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  note.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              Text(
                timeLabel,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
