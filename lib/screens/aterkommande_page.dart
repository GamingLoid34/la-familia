import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/family_provider.dart';
import '../services/notification_service.dart';
import '../utils/aterkommande_lista.dart';
import '../utils/layout.dart';
import '../utils/permissions.dart';
import '../widgets/vardag_header.dart';

/// "Återkommande" under Mer (Androids `AterkommandeScreen`): aktiviteter och
/// sysslor som upprepas, tillsammans, med titel, vem, när och typ. Alla får
/// se listan; Ta bort (alla gånger, inklusive påminnelser) följer
/// rättigheterna — förälder/admin eller den som skapade posten.
class AterkommandePage extends StatefulWidget {
  const AterkommandePage({super.key});

  @override
  State<AterkommandePage> createState() => _AterkommandePageState();
}

class _AterkommandePageState extends State<AterkommandePage> {
  final Set<String> _deleting = {};

  Future<void> _delete(AterkommandeRad rad) async {
    if (_deleting.contains(rad.id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ta bort "${rad.titel}"?'),
        content: const Text(
            'Alla gånger tas bort, även kommande påminnelser. Det här går inte att ångra.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E)),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting.add(rad.id));
    try {
      final coll = rad.typ == AterkommandeTyp.aktivitet ? 'planner_events' : 'chores';
      await FirebaseFirestore.instance.collection(coll).doc(rad.id).delete();
      if (rad.typ == AterkommandeTyp.aktivitet) {
        await NotificationService.cancelActivityReminders(rad.id, rad.raw);
      } else {
        await NotificationService.cancelChoreReminders(rad.id, rad.raw);
      }
      if (mounted) showVardagSnack(context, 'Borttagen.');
    } catch (e, stack) {
      developer.log('Kunde inte ta bort återkommande', error: e, stackTrace: stack);
      if (mounted) showVardagSnack(context, 'Kunde inte ta bort: $e', isError: true);
    } finally {
      if (mounted) setState(() => _deleting.remove(rad.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FamilyProvider>();
    final me = p.currentUser;
    final c = AppTheme.colors();
    final rader = byggAterkommandeLista(
      events: [
        for (final d in p.recurringEvents) (d.id, d.data() as Map<String, dynamic>),
      ],
      chores: [
        for (final d in p.chores) (d.id, d.data() as Map<String, dynamic>),
      ],
      members: p.familyMembers,
    );

    Widget body;
    if (p.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (rader.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(aterkommandeTom,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: c.onPage)),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: Text(aterkommandeIngress,
                style: TextStyle(color: c.onPageSecondary, fontSize: 13)),
          ),
          VardagCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (var i = 0; i < rader.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 56, color: c.divider),
                _Row(
                  rad: rader[i],
                  canDelete: canEditDoc(me, rader[i].raw),
                  deleting: _deleting.contains(rader[i].id),
                  onDelete: () => _delete(rader[i]),
                ),
              ],
            ]),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: c.pageBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: WindowSize.of(context).isExpanded
                  ? WindowSize.settingsMaxWidth
                  : double.infinity),
          child: Column(children: [
            VardagTitleHeader(
                title: aterkommandeRubrik,
                onBack: () => Navigator.of(context).maybePop()),
            Expanded(child: body),
          ]),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final AterkommandeRad rad;
  final bool canDelete;
  final bool deleting;
  final VoidCallback onDelete;

  const _Row({
    required this.rad,
    required this.canDelete,
    required this.deleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(children: [
        SizedBox(
            width: 28,
            child: Text(rad.piktogram, style: const TextStyle(fontSize: 20))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(rad.titel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: c.onCardPrimary)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(rad.typ.etikett,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: c.onCardPrimary)),
              ),
            ]),
            Text('${rad.vem} · ${rad.nar}',
                style: TextStyle(fontSize: 12, color: c.onCardSecondary)),
          ]),
        ),
        if (canDelete)
          deleting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB3261E)),
                  child: const Text('Ta bort'),
                ),
      ]),
    );
  }
}
