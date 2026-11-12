import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../data/vardagsplan_mall.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';

/// Vardagsplanen (föräldravy): genererar ett komplett förslag på rutiner,
/// veckouppdrag och matvecka, låter dig justera allt — och skriver sedan in
/// det i appens vanliga collections så att det syns på Hem, i Agendan,
/// Familjeveckan, matplaneraren och hemskärms-widgeten.
///
/// Aktiveras för EN vald vecka. Poster taggas `source: 'vardagsplan'`.
/// Ny aktivering för samma vecka ersätter den veckans vardagsplan-poster.
class VardagsplanPage extends StatefulWidget {
  const VardagsplanPage({super.key});

  @override
  State<VardagsplanPage> createState() => _VardagsplanPageState();
}

class _VardagsplanPageState extends State<VardagsplanPage> {
  Map<String, PlanProfil>? _profiler;
  Vardagsplan? _plan;
  bool _aktiverar = false;
  bool _loadingPlans = true;
  bool _plansLoadStarted = false;
  List<_ActiveWeekPlan> _activeWeeks = [];

  /// Måndag för målveckan (default: nästa ISO-vecka).
  late DateTime _weekStart;

  /// Bumpas när förslaget byggs om — tvingar textfälten att ta nya värden.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final thisMon = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    _weekStart = thisMon.add(const Duration(days: 7));
  }

  DateTime get _weekEnd =>
      DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6);

  String get _weekLabel {
    final w = isoWeekNumber(_weekStart);
    final fmt = DateFormat('d MMM', 'sv');
    final a = fmt.format(_weekStart);
    final b = fmt.format(_weekEnd);
    return 'Gäller v.$w, $a–$b';
  }

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

  DateTime _datumIVecka(int veckodag) => DateTime(
        _weekStart.year,
        _weekStart.month,
        _weekStart.day + (veckodag - 1),
      );

  Future<void> _refreshActivePlans(String fid) async {
    if (fid.isEmpty) {
      if (mounted) {
        setState(() {
          _activeWeeks = [];
          _loadingPlans = false;
        });
      }
      return;
    }
    setState(() => _loadingPlans = true);
    final db = FirebaseFirestore.instance;
    final eventSnap = await db
        .collection('planner_events')
        .where('familyId', isEqualTo: fid)
        .where('source', isEqualTo: 'vardagsplan')
        .get();
    final mealSnap = await db
        .collection('meals')
        .where('familyId', isEqualTo: fid)
        .where('source', isEqualTo: 'vardagsplan')
        .get();
    final choreSnap = await db
        .collection('chores')
        .where('familyId', isEqualTo: fid)
        .where('source', isEqualTo: 'vardagsplan')
        .get();

    final today = DateTime.now();
    final todayKey = dateKey(DateTime(today.year, today.month, today.day));

    final byWeek = <String, _ActiveWeekPlan>{};

    void touch(String? rawDate,
        {int events = 0, int meals = 0, int chores = 0, int openEnded = 0}) {
      if (rawDate == null || rawDate.isEmpty) return;
      final d = parseDate(rawDate);
      if (d == null) return;
      final mon = DateTime(d.year, d.month, d.day - (d.weekday - 1));
      final key = dateKey(mon);
      final cur = byWeek.putIfAbsent(
        key,
        () => _ActiveWeekPlan(
          weekStart: mon,
          events: 0,
          meals: 0,
          chores: 0,
          openEndedRecurring: 0,
        ),
      );
      cur.events += events;
      cur.meals += meals;
      cur.chores += chores;
      cur.openEndedRecurring += openEnded;
    }

    for (final doc in eventSnap.docs) {
      final d = doc.data();
      final date = d['date'] as String? ??
          ((d['recurrence'] as Map?)?['startDate'] as String?);
      final recurring = d['isRecurring'] == true;
      final end = (d['recurrence'] as Map?)?['endDate'];
      final open = recurring && end == null;
      if (date == null) continue;
      if (open || date.compareTo(todayKey) >= 0) {
        touch(date, events: 1, openEnded: open ? 1 : 0);
      }
    }
    for (final doc in mealSnap.docs) {
      final date = doc.data()['date'] as String?;
      if (date != null && date.compareTo(todayKey) >= 0) {
        touch(date, meals: 1);
      }
    }
    for (final doc in choreSnap.docs) {
      final d = doc.data();
      final date = d['dueDate'] as String? ??
          ((d['recurrence'] as Map?)?['startDate'] as String?);
      if (date != null && date.compareTo(todayKey) >= 0) {
        touch(date, chores: 1);
      }
    }

    final list = byWeek.values.toList()
      ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    if (!mounted) return;
    setState(() {
      _activeWeeks = list;
      _loadingPlans = false;
    });
  }

  Future<_DeleteCounts> _countVardagsplanInRange({
    required String fid,
    required String fromKey,
    String? toKey,
    required bool includeOpenRecurring,
  }) async {
    final db = FirebaseFirestore.instance;
    final eventSnap = await db
        .collection('planner_events')
        .where('familyId', isEqualTo: fid)
        .where('source', isEqualTo: 'vardagsplan')
        .get();
    final mealSnap = await db
        .collection('meals')
        .where('familyId', isEqualTo: fid)
        .where('source', isEqualTo: 'vardagsplan')
        .get();
    final choreSnap = await db
        .collection('chores')
        .where('familyId', isEqualTo: fid)
        .where('source', isEqualTo: 'vardagsplan')
        .get();

    var events = 0, meals = 0, chores = 0;
    final eventRefs = <DocumentReference>[];
    final mealRefs = <DocumentReference>[];
    final choreRefs = <DocumentReference>[];

    bool inRange(String? date) {
      if (date == null || date.isEmpty) return false;
      if (date.compareTo(fromKey) < 0) return false;
      if (toKey != null && date.compareTo(toKey) > 0) return false;
      return true;
    }

    for (final doc in eventSnap.docs) {
      final d = doc.data();
      final date = d['date'] as String?;
      final recurring = d['isRecurring'] == true;
      final end = (d['recurrence'] as Map?)?['endDate'];
      final open = recurring && end == null;
      if (inRange(date) || (includeOpenRecurring && open)) {
        events++;
        eventRefs.add(doc.reference);
      }
    }
    for (final doc in mealSnap.docs) {
      final date = doc.data()['date'] as String?;
      if (inRange(date)) {
        meals++;
        mealRefs.add(doc.reference);
      }
    }
    for (final doc in choreSnap.docs) {
      final d = doc.data();
      final date = d['dueDate'] as String? ??
          ((d['recurrence'] as Map?)?['startDate'] as String?);
      final recurring = d['isRecurring'] == true;
      final end = (d['recurrence'] as Map?)?['endDate'];
      final open = recurring && end == null;
      if (inRange(date) || (includeOpenRecurring && open)) {
        chores++;
        choreRefs.add(doc.reference);
      }
    }
    return _DeleteCounts(
      events: events,
      meals: meals,
      chores: chores,
      eventRefs: eventRefs,
      mealRefs: mealRefs,
      choreRefs: choreRefs,
    );
  }

  Future<void> _deleteRefs(_DeleteCounts c) async {
    final db = FirebaseFirestore.instance;
    final all = [...c.eventRefs, ...c.mealRefs, ...c.choreRefs];
    for (var i = 0; i < all.length; i += 400) {
      final batch = db.batch();
      for (final ref in all.sublist(i, i + 400 > all.length ? all.length : i + 400)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  Future<bool> _confirmDangerDelete({
    required String title,
    required _DeleteCounts counts,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DelayedConfirmDialog(
        title: title,
        body:
            'Tar bort ${counts.events} uppdrag, ${counts.meals} middagar, '
            '${counts.chores} sysslor — kan inte ångras',
      ),
    );
    return ok == true;
  }

  Future<void> _taBortVecka(String fid, DateTime weekStart) async {
    final end = DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
    final counts = await _countVardagsplanInRange(
      fid: fid,
      fromKey: dateKey(weekStart),
      toKey: dateKey(end),
      includeOpenRecurring: false,
    );
    if (counts.total == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inget att ta bort för den veckan.')),
      );
      return;
    }
    final ok = await _confirmDangerDelete(
      title: 'Ta bort veckans plan?',
      counts: counts,
    );
    if (!ok) return;
    await _deleteRefs(counts);
    await _refreshActivePlans(fid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tog bort ${counts.total} poster.'),
        backgroundColor: const Color(0xFF6BAE75),
      ),
    );
  }

  Future<void> _taBortAllaFramtida(String fid) async {
    final today = DateTime.now();
    final todayKey = dateKey(DateTime(today.year, today.month, today.day));
    final counts = await _countVardagsplanInRange(
      fid: fid,
      fromKey: todayKey,
      toKey: null,
      includeOpenRecurring: true,
    );
    if (counts.total == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inga framtida vardagsplan-poster.')),
      );
      return;
    }
    final ok = await _confirmDangerDelete(
      title: 'Ta bort ALLA framtida?',
      counts: counts,
    );
    if (!ok) return;
    await _deleteRefs(counts);
    await _refreshActivePlans(fid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tog bort ${counts.total} framtida poster.'),
        backgroundColor: const Color(0xFF6BAE75),
      ),
    );
  }

  Future<void> _aktivera(FamilyProvider provider) async {
    final plan = _plan;
    final fid = provider.currentUser?.familyId ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (plan == null || fid.isEmpty || uid == null) return;

    setState(() => _aktiverar = true);
    final db = FirebaseFirestore.instance;
    final medlemmar = provider.familyMembers;
    final fromKey = dateKey(_weekStart);
    final toKey = dateKey(_weekEnd);

    try {
      // Ersätt befintliga vardagsplan-poster i vald vecka.
      final existing = await _countVardagsplanInRange(
        fid: fid,
        fromKey: fromKey,
        toKey: toKey,
        includeOpenRecurring: false,
      );
      await _deleteRefs(existing);

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

      // 2. VECKOUPPDRAG — återkommande sysslor med endDate = veckans söndag.
      final choreNotifs = <({String id, Map<String, dynamic> data})>[];
      for (final u in plan.uppdrag) {
        if (u.titel.trim().isEmpty) continue;
        final datum = _datumIVecka(u.veckodag);
        final startKey = dateKey(datum);
        final endKey = dateKey(_weekEnd);
        final persons = medlemmar
            .where((m) => u.personUids.contains(m.uid))
            .toList();
        final whoName = persons.isEmpty ? '' : persons.first.name;
        final whoUid = persons.isEmpty ? '' : persons.first.uid;
        final whoColor = persons.isEmpty ? '' : persons.first.color;
        final rotation = u.personUids.where((id) => id.isNotEmpty).toList();
        final choreData = <String, dynamic>{
          'chore': u.titel.trim(),
          'piktogram': u.piktogram,
          'who': whoName,
          'whoUid': whoUid,
          'whoColor': whoColor,
          'isDone': false,
          'doneDates': <String>[],
          'points': 10,
          'isRecurring': true,
          'recurrence': {
            'type': 'weekly',
            'startDate': startKey,
            'endDate': endKey,
            'exceptions': <String>[],
          },
          'dueDate': startKey,
          if (u.tid.isNotEmpty) 'dueTime': u.tid,
          'rotationUids': rotation,
          'familyId': fid,
          'source': 'vardagsplan',
          'vardagsplanKey': '${u.nyckel}|$fromKey',
          'createdByUid': uid,
        };
        final choreRef = db.collection('chores').doc();
        batch.set(choreRef, choreData);
        choreNotifs.add((id: choreRef.id, data: choreData));
        antalUppdrag++;
      }

      // 3. MATVECKAN — bara vald veckas 7 dagar.
      final nycklar = [
        for (var i = 0; i < 7; i++)
          dateKey(DateTime(
              _weekStart.year, _weekStart.month, _weekStart.day + i)),
      ];
      final befintligaMal = <String, QueryDocumentSnapshot>{};
      final snap = await db
          .collection('meals')
          .where('familyId', isEqualTo: fid)
          .where('date', whereIn: nycklar)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        befintligaMal[d['date'] as String? ?? ''] = doc;
      }
      for (var i = 0; i < 7; i++) {
        final dag = DateTime(
            _weekStart.year, _weekStart.month, _weekStart.day + i);
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
        // Manuella middagar (utan source vardagsplan) lämnas orörda.
      }

      await batch.commit();
      for (final c in choreNotifs) {
        await NotificationService.scheduleChoreReminders(
          docId: c.id,
          data: c.data,
        );
      }
      await _refreshActivePlans(fid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Vardagsplan $_weekLabel  ·  $antalRutiner rutiner · '
              '$antalUppdrag sysslor · $antalMiddagar middagar'),
          backgroundColor: const Color(0xFF6BAE75),
          duration: const Duration(seconds: 4),
        ),
      );
      setState(() => _aktiverar = false);
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
    final fid = provider.currentUser?.familyId ?? '';
    if (!_plansLoadStarted && fid.isNotEmpty) {
      _plansLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshActivePlans(fid);
      });
    }

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
                        const SizedBox(height: 16),
                        _weekPicker(dayColor),
                        const SizedBox(height: 16),
                        _aktivaPlanerSektion(
                            provider.currentUser?.familyId ?? '', dayColor),
                        const SizedBox(height: 20),
                        _profilSektion(medlemmar),
                        const SizedBox(height: 20),
                        Text('RUTINER — MORGON & KVÄLL',
                            style: AppTheme.sectionLabelStyle),
                        const SizedBox(height: 8),
                        ...plan.rutiner.map(_rutinKort),
                        const SizedBox(height: 20),
                        Text('VECKOUPPDRAG — I VALD VECKA',
                            style: AppTheme.sectionLabelStyle),
                        const SizedBox(height: 8),
                        ...plan.uppdrag.map((u) => _uppdragKort(u, medlemmar)),
                        _laggTillUppdragKnapp(dayColor),
                        const SizedBox(height: 20),
                        Text('MATVECKAN — FÖR VALD VECKA',
                            style: AppTheme.sectionLabelStyle),
                        const SizedBox(height: 8),
                        _matveckaKort(),
                        const SizedBox(height: 24),
                        _aktiveraKnapp(provider, dayColor),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Aktivering skriver bara vald vecka. Ny aktivering '
                            'för samma vecka ersätter den veckans vardagsplan-poster.',
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

  Widget _weekPicker(Color dayColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(() {
              _weekStart = DateTime(
                  _weekStart.year, _weekStart.month, _weekStart.day - 7);
            }),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _weekLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
                TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    final thisMon = DateTime(
                        now.year, now.month, now.day - (now.weekday - 1));
                    setState(
                        () => _weekStart = thisMon.add(const Duration(days: 7)));
                  },
                  child: Text('Nästa vecka',
                      style: TextStyle(
                          color: dayColor, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => setState(() {
              _weekStart = DateTime(
                  _weekStart.year, _weekStart.month, _weekStart.day + 7);
            }),
          ),
        ],
      ),
    );
  }

  Widget _aktivaPlanerSektion(String fid, Color dayColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AKTIVA VARDAGSPLANER', style: AppTheme.sectionLabelStyle),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: fid.isEmpty ? null : () => _taBortAllaFramtida(fid),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
              ),
              child: const Text('Ta bort ALLA framtida vardagsplan-poster'),
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingPlans)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_activeWeeks.isEmpty)
            Text('Inga framtida vardagsplan-poster just nu.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
          else
            ..._activeWeeks.map((w) {
              final wn = isoWeekNumber(w.weekStart);
              final parts = <String>[];
              if (w.events > 0) parts.add('${w.events} uppdrag');
              if (w.meals > 0) parts.add('${w.meals} middagar');
              if (w.chores > 0) parts.add('${w.chores} sysslor');
              final open = w.openEndedRecurring > 0
                  ? ' · ⚠ ${w.openEndedRecurring} öppna serier'
                  : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'v.$wn: ${parts.isEmpty ? 'tom' : parts.join(' · ')}$open',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _taBortVecka(fid, w.weekStart),
                      child: Text('Ta bort',
                          style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ],
                ),
              );
            }),
        ],
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
            : Text('Aktivera $_weekLabel 🌟',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _ActiveWeekPlan {
  final DateTime weekStart;
  int events;
  int meals;
  int chores;
  int openEndedRecurring;

  _ActiveWeekPlan({
    required this.weekStart,
    required this.events,
    required this.meals,
    required this.chores,
    required this.openEndedRecurring,
  });
}

class _DeleteCounts {
  final int events;
  final int meals;
  final int chores;
  final List<DocumentReference> eventRefs;
  final List<DocumentReference> mealRefs;
  final List<DocumentReference> choreRefs;

  const _DeleteCounts({
    required this.events,
    required this.meals,
    required this.chores,
    required this.eventRefs,
    required this.mealRefs,
    required this.choreRefs,
  });

  int get total => events + meals + chores;
}

class _DelayedConfirmDialog extends StatefulWidget {
  final String title;
  final String body;

  const _DelayedConfirmDialog({required this.title, required this.body});

  @override
  State<_DelayedConfirmDialog> createState() => _DelayedConfirmDialogState();
}

class _DelayedConfirmDialogState extends State<_DelayedConfirmDialog> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Text(widget.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: _ready ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(_ready ? 'Ta bort' : 'Vänta…'),
        ),
      ],
    );
  }
}
