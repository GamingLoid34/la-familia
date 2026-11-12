import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/family_provider.dart';

/// Snabb emoji-reaktion på ett planerat event (max 1 per medlem).
class EventReactionsRow extends StatelessWidget {
  final DocumentReference eventRef;

  static const reactionEmojis = ['💪', '❤️', '🎉', '🍀', '🚗', '🥐'];

  const EventReactionsRow({super.key, required this.eventRef});

  Map<String, Map<String, dynamic>> _parseReactions(Map<String, dynamic>? raw) {
    if (raw == null) return {};
    final out = <String, Map<String, dynamic>>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is Map) {
        out[e.key] = Map<String, dynamic>.from(v);
      }
    }
    return out;
  }

  Future<void> _toggleReaction(
    BuildContext context,
    String emoji,
    Map<String, Map<String, dynamic>> reactions,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final provider = context.read<FamilyProvider>();
    final me = provider.currentUser;
    if (me == null) return;

    final existing = reactions[uid];
    final existingEmoji = existing?['emoji'] as String?;

    try {
      if (existingEmoji == emoji) {
        await eventRef.update({'reactions.$uid': FieldValue.delete()});
      } else {
        await eventRef.update({
          'reactions.$uid': {
            'emoji': emoji,
            'name': me.name,
            'color': me.color,
            'at': FieldValue.serverTimestamp(),
          },
        });
      }
    } catch (e, stack) {
      developer.log('EventReactionsRow toggle error',
          error: e, stackTrace: stack);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara reaktion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _chipsLabel(Map<String, Map<String, dynamic>> reactions) {
    if (reactions.isEmpty) return '';
    return reactions.values
        .map((r) {
          final name = (r['name'] as String?) ?? '';
          final emoji = (r['emoji'] as String?) ?? '';
          if (name.isEmpty) return emoji;
          return '$name $emoji';
        })
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: eventRef.snapshots(),
      builder: (context, snap) {
        final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
        final reactions = _parseReactions(
          data['reactions'] as Map<String, dynamic>?,
        );
        final myReaction = myUid != null ? reactions[myUid] : null;
        final myEmoji = myReaction?['emoji'] as String?;
        final chips = _chipsLabel(reactions);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('REAKTIONER', style: AppTheme.sectionLabelStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: reactionEmojis.map((emoji) {
                final selected = myEmoji == emoji;
                return Material(
                  color: selected
                      ? dayColor.withValues(alpha: 0.2)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _toggleReaction(context, emoji, reactions),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                chips,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
