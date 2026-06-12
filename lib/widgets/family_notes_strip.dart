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

/// Horisontell dagstavla med familjens korta notiser (Familjen-fliken).
class FamilyNotesStrip extends StatelessWidget {
  const FamilyNotesStrip({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Consumer<FamilyProvider>(
      builder: (context, provider, _) {
        final notes = provider.todayNotes;
        final myUid = FirebaseAuth.instance.currentUser?.uid;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DAGSTAVLA', style: AppTheme.sectionLabelStyle),
              const SizedBox(height: 8),
              SizedBox(
                height: 88,
                child: notes.isEmpty
                    ? _EmptyNotesRow(onAdd: () => _openAdd(context, provider))
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: AppTheme.cardDecoration(radius: 16).copyWith(
          border: Border(
            left: BorderSide(color: accent, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.fromName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  timeLabel,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                note.text,
                style: const TextStyle(fontSize: 13, height: 1.25),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
