import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../data/vardagsplan_mall.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../utils/date_utils.dart';

/// Vardagsplanen (föräldravy): genererar ett komplett förslag på rutiner,
/// veckouppdrag och matvecka, låter dig justera allt — och skriver sedan in
/// det i appens vanliga collections så att det syns på Hem, i Agendan,
/// Familjeveckan, matplaneraren och hemskärms-widgeten.
///
/// Kan aktiveras hur många gånger som helst: allt planen skapar taggas med
/// `source: 'vardagsplan'` och uppdateras på plats istället för att dubblas.
class VardagsplanPage extends StatefulWidget {
  const VardagsplanPage({super.key});

  @override
  State<VardagsplanPage> createState() => _VardagsplanPageState();
}

class _VardagsplanPageState extends State<VardagsplanPage> {
  Map<String, PlanProfil>? _profiler;
  Vardagsplan? _plan;
  bool _aktiverar = false;

  /// Bumpas när förslaget byggs om — tvingar textfälten att ta nya värden.
  int _gen = 0;

  // Snabbval av piktogram för rutinsteg (samma anda som rutin-editorn).
  static const _stegEmojis = [
    '🪥', '🚿', '🧼', '👕', '🎒', '🥣', '💊', '📚',
    '🧸', '😴', '🧦', '🧴', '🍽️', '🧹', '🧽', '✅',
  ];

  void _sakerstallPlan(List<UserModel> medlemmar) {
    if (_plan != null || medlemmar.isEmpty) return;
    _profiler = {for (final m in medlemmar) m.uid: gissaProfil(m)};
    _plan = byggVardagsplan(medlemmar, _profiler!);
  }

  void _byggOm(List<UserModel> medlemmar) {
    setState(() {
      _plan = byggVardagsplan(medlemmar, _profiler ?? {});
      _gen++;
    });
  }

  // ─── AKTIVERA ─────────────────────────────────────────────────────────────

  DateTime _nastaDatumFor(int veckodag) {
    final nu = DateTime.now();
    final diff = (veckodag - nu.weekday) % 7;
    return DateTime(nu.year, nu.month, nu.day + diff);
  }

  Future<void> _aktivera(FamilyProvider provider) async {
    final plan = _plan;
    final fid = provider.currentUser?.familyId ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (plan == null || fid.isEmpty || uid == null) return;

    setState(() => _aktiverar = true);
    final db = FirebaseFirestore.instance;
    final medlemmar = provider.familyMembers;

    try {
      final batch = db.batch();
      var antalRutiner = 0;
      var antalUppdrag = 0;
      var antalMiddagar = 0;

      // 1. RUTINER — upsert per (ägare, morgon/kväll).
      final befintligaRutiner = <String, DocumentReference>{};
      for (final doc in provider.routines) {
        final d = doc.data() as Map<String, dynamic>;
        befintligaRutiner['${d['ownerUid']}|${d['type']}'] = doc.reference;
      }
      for (final r in plan.rutiner) {
        if (r.steg.isEmpty) continue;
        final data = {
          'familyId': fid,
          'ownerUid': r.ownerUid,
          'ownerName': r.ownerName,
          'type': r.typ,
          'steps': r.steg.map((s) => s.toRoutineStep()).toList(),
          'source': 'vardagsplan',
        };
        final ref = befintligaRutiner['${r.ownerUid}|${r.typ}'];
        if (ref != null) {
          batch.update(ref, data);
        } else {
          batch.set(db.collection('routines').doc(), {
            ...data,
            'doneDate': '',
            'doneSteps': <int>[],
          });
        }
        antalRutiner++;
      }

      // 2. VECKOUPPDRAG — återkommande planner_events, upsert via nyckel.
      final befintligaEvents = <String, DocumentReference>{};
      final eventSnap = await db
          .collection('planner_events')
          .where('familyId', isEqualTo: fid)
          .where('source', isEqualTo: 'vardagsplan')
          .get();
      for (final doc in eventSnap.docs) {
        final key = doc.data()['vardagsplanKey'] as String?;
        if (key != null) befintligaEvents[key] = doc.reference;
      }

      final anvandaNycklar = <String>{};
      for (final u in plan.uppdrag) {
        if (u.titel.trim().isEmpty) continue;
        anvandaNycklar.add(u.nyckel);
        final datum = _nastaDatumFor(u.veckodag);
        final persons = medlemmar
            .where((m) => u.personUids.contains(m.uid))
            .map((m) => m.name)
            .toList();
        final data = <String, dynamic>{
          'title': u.titel.trim(),
          'piktogram': u.piktogram,
          'type': 'activity',
          'date': dateKey(datum),
          'time': u.tid,
          'persons': persons,
          'personUids': u.personUids,
          'checklist':
              u.checklista.map((c) => {'item': c, 'isDone': false}).toList(),
          'isPending': false,
          'familyId': fid,
          'isRecurring': true,
          'recurrence': {
            'type': 'weekly',
            'startDate': dateKey(datum),
            'endDate': null,
            'exceptions': <String>[],
          },
          'source': 'vardagsplan',
          'vardagsplanKey': u.nyckel,
        };
        final ref = befintligaEvents[u.nyckel];
        if (ref != null) {
          batch.update(ref, data);
        } else {
          batch.set(db.collection('planner_events').doc(), {
            ...data,
            'createdBy': uid,
            'createdByUid': uid,
          });
        }
        antalUppdrag++;
      }
      // Uppdrag som tagits bort ur planen → ta bort ur agendan.
      befintligaEvents.forEach((key, ref) {
        if (!anvandaNycklar.contains(key)) batch.delete(ref);
      });

      // 3. MATVECKAN — fyll 14 dagar framåt. Manuellt inlagda rätter vinner.
      final idag = DateTime.now();
      final dagar = [
        for (var i = 0; i < 14; i++)
          DateTime(idag.year, idag.month, idag.day + i),
      ];
      final nycklar = dagar.map(dateKey).toList();
      final befintligaMal = <String, QueryDocumentSnapshot>{};
      for (final del in [nycklar.sublist(0, 7), nycklar.sublist(7)]) {
        final snap = await db
            .collection('meals')
            .where('familyId', isEqualTo: fid)
            .where('date', whereIn: del)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          befintligaMal[d['date'] as String? ?? ''] = doc;
        }
      }
      for (final dag in dagar) {
        final maltid = plan.matvecka
            .where((m) => m.veckodag == dag.weekday && m.titel.trim().isNotEmpty)
            .toList();
        if (maltid.isEmpty) continue;
        final m = maltid.first;
        final key = dateKey(dag);
        final befintlig = befintligaMal[key];
        if (befintlig == null) {
          batch.set(db.collection('meals').doc(), {
            'familyId': fid,
            'date': key,
            'title': m.titel.trim(),
            'emoji': m.emoji,
            'source': 'vardagsplan',
            'createdAt': FieldValue.serverTimestamp(),
          });
          antalMiddagar++;
        } else if ((befintlig.data() as Map<String, dynamic>)['source'] ==
            'vardagsplan') {
          batch.update(befintlig.reference,
              {'title': m.titel.trim(), 'emoji': m.emoji});
          antalMiddagar++;
        }
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Vardagsplanen är igång! 🌟  $antalRutiner rutiner · '
              '$antalUppdrag veckouppdrag · $antalMiddagar middagar'),
          backgroundColor: const Color(0xFF6BAE75),
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context);
    } catch (e, stack) {
      developer.log('Vardagsplan: aktivering misslyckades',
          error: e, stackTrace: stack);
      if (mounted) {
        setState(() => _aktiverar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Kunde inte aktivera: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── HJÄLPARE ─────────────────────────────────────────────────────────────

  Future<String?> _valjEmoji(List<String> emojis) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: emojis
                .map((e) => GestureDetector(
                      onTap: () => Navigator.pop(ctx, e),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _laggTillSteg(PlanRutin rutin) async {
    final ctrl = TextEditingController();
    var emoji = '✅';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nytt steg'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'T.ex. Kamma håret'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _stegEmojis
                    .map((e) => GestureDetector(
                          onTap: () => setD(() => emoji = e),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: emoji == e
                                  ? AppTheme.getDayAccentColor()
                                      .withValues(alpha: 0.2)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child:
                                Text(e, style: const TextStyle(fontSize: 20)),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lägg till')),
          ],
        ),
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      setState(() => rutin.steg.add(PlanSteg(emoji, ctrl.text.trim())));
    }
    ctrl.dispose();
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final medlemmar = provider.familyMembers;
    _sakerstallPlan(medlemmar);

    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);
    final dayColor = AppTheme.getDayAccentColor();
    final plan = _plan;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: AppTheme.getBackground(),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    decoration: AppTheme.headerDecoration(),
                    padding: AppTheme.paddingBelowStatusBar(context),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back_ios_rounded,
                            color: textColor),
                      ),
                      const SizedBox(width: 12),
                      Text('Vardagsplan',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: textColor)),
                    ]),
                  ),
                ),
                if (plan == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _introKort(),
                        const SizedBox(height: 20),
                        _profilSektion(medlemmar),
                        const SizedBox(height: 20),
                        Text('RUTINER — MORGON & KVÄLL',
                            style: AppTheme.sectionLabelStyle),
                        const SizedBox(height: 8),
                        ...plan.rutiner.map(_rutinKort),
                        const SizedBox(height: 20),
                        Text('VECKOUPPDRAG — ÅTERKOMMANDE I AGENDAN',
                            style: AppTheme.sectionLabelStyle),
                        const SizedBox(height: 8),
                        ...plan.uppdrag.map((u) => _uppdragKort(u, medlemmar)),
                        _laggTillUppdragKnapp(dayColor),
                        const SizedBox(height: 20),
                        Text('MATVECKAN — SAMMA VARJE VECKA',
                            style: AppTheme.sectionLabelStyle),
                        const SizedBox(height: 8),
                        _matveckaKort(),
                        const SizedBox(height: 24),
                        _aktiveraKnapp(provider, dayColor),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Planen kan justeras och aktiveras igen när som '
                            'helst — allt uppdateras utan dubbletter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ),
                        const SizedBox(height: 120),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _introKort() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: const Text(
        'Ett färdigt förslag på hur vardagen kan rulla: rutiner för alla, '
        'fasta veckouppdrag och en matvecka som upprepas. Justera tills det '
        'känns rätt — tryck sedan Aktivera så läggs allt in i appen.\n\n'
        'Rutiner är trygghet, inte krav. Gott nog räcker. 💛',
        style: TextStyle(fontSize: 13, height: 1.5),
      ),
    );
  }

  Widget _profilSektion(List<UserModel> medlemmar) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VILKA ÄR NI?', style: AppTheme.sectionLabelStyle),
          const SizedBox(height: 4),
          Text(
            'Profilen styr förslaget. Byter du profil byggs förslaget om '
            '(egna ändringar nollställs).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          ...medlemmar.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(m.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    SegmentedButton<PlanProfil>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: PlanProfil.values
                          .map((p) => ButtonSegment(
                              value: p,
                              label: Text(planProfilLabel(p),
                                  style: const TextStyle(fontSize: 11))))
                          .toList(),
                      selected: {
                        _profiler?[m.uid] ?? gissaProfil(m),
                      },
                      onSelectionChanged: (s) {
                        _profiler ??= {};
                        _profiler![m.uid] = s.first;
                        _byggOm(medlemmar);
                      },
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _rutinKort(PlanRutin r) {
    final isMorning = r.typ == 'morning';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(isMorning ? '🌅' : '🌙',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.ownerName} — ${isMorning ? 'morgon' : 'kväll'}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.add_circle_outline_rounded,
                  size: 20, color: AppTheme.getDayAccentColor()),
              onPressed: () => _laggTillSteg(r),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: r.steg
                .map((s) => Chip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text('${s.piktogram} ${s.titel}',
                          style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => setState(() => r.steg.remove(s)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _uppdragKort(PlanUppdrag u, List<UserModel> medlemmar) {
    final plan = _plan!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onTap: () async {
                final e = await _valjEmoji(const [
                  '🗑️', '🧺', '🧹', '🛒', '🤝', '🍳', '🐕', '🌿',
                  '🚗', '📞', '🧽', '✅',
                ]);
                if (e != null) setState(() => u.piktogram = e);
              },
              child: Text(u.piktogram, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: ValueKey('uppdrag-$_gen-${u.nyckel}'),
                initialValue: u.titel,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Vad ska göras?',
                ),
                onChanged: (v) => u.titel = v,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: Colors.grey.shade400),
              onPressed: () => setState(() => plan.uppdrag.remove(u)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            DropdownButton<int>(
              value: u.veckodag,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              items: [
                for (var d = 1; d <= 7; d++)
                  DropdownMenuItem(value: d, child: Text(veckodagsNamn[d])),
              ],
              onChanged: (v) =>
                  setState(() => u.veckodag = v ?? u.veckodag),
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: () async {
                final delar = u.tid.split(':');
                final vald = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: int.tryParse(delar[0]) ?? 17,
                    minute:
                        delar.length > 1 ? int.tryParse(delar[1]) ?? 0 : 0,
                  ),
                );
                if (vald != null) {
                  setState(() => u.tid =
                      '${vald.hour.toString().padLeft(2, '0')}:${vald.minute.toString().padLeft(2, '0')}');
                }
              },
              child: Row(children: [
                Icon(Icons.schedule_rounded,
                    size: 15, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(u.tid, style: const TextStyle(fontSize: 13)),
              ]),
            ),
            if (u.checklista.isNotEmpty) ...[
              const SizedBox(width: 16),
              Text('📋 ${u.checklista.length} punkter',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: medlemmar
                .map((m) => FilterChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(m.name,
                          style: const TextStyle(fontSize: 11)),
                      selected: u.personUids.contains(m.uid),
                      onSelected: (val) => setState(() {
                        if (val) {
                          u.personUids.add(m.uid);
                        } else {
                          u.personUids.remove(m.uid);
                        }
                      }),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _laggTillUppdragKnapp(Color dayColor) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Lägg till veckouppdrag',
            style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: dayColor,
          side: BorderSide(color: dayColor.withValues(alpha: 0.4)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => setState(() {
          _plan!.uppdrag.add(PlanUppdrag(
            titel: '',
            piktogram: '✅',
            veckodag: 1,
            tid: '17:00',
            personUids: [],
            nyckel: 'egen-${DateTime.now().millisecondsSinceEpoch}',
          ));
        }),
      ),
    );
  }

  Widget _matveckaKort() {
    final plan = _plan!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Column(
        children: plan.matvecka
            .map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () async {
                        final e = await _valjEmoji(matEmojis);
                        if (e != null) setState(() => m.emoji = e);
                      },
                      child:
                          Text(m.emoji, style: const TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 34,
                      child: Text(
                        veckodagsNamn[m.veckodag].substring(0, 3),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade500),
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('mat-$_gen-${m.veckodag}'),
                        initialValue: m.titel,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Lämna tomt = ingen planerad rätt',
                        ),
                        onChanged: (v) => m.titel = v,
                      ),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  Widget _aktiveraKnapp(FamilyProvider provider, Color dayColor) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _aktiverar ? null : () => _aktivera(provider),
        style: ElevatedButton.styleFrom(
          backgroundColor: dayColor,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _aktiverar
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('Aktivera vardagsplanen 🌟',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
