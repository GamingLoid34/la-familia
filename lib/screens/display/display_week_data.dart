import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/family_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/week_bucketing.dart';
import 'display_formatters.dart';
import 'display_log.dart';
import 'display_week_board.dart';

/// Jämför två listor av medlemmar baserat på uid-sekvens (FAS 2.2 Beslut 6).
/// Returnerar true om listorna innehåller exakt samma uids i samma ordning.
bool haveSameMemberUids(List<UserModel> a, List<UserModel> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].uid != b[i].uid) return false;
  }
  return true;
}

/// Hanterar Firestore-strömmar för vald vecka och matar Veckotavlan
/// med färdig-bucketad data.
class DisplayWeekData extends StatefulWidget {
  final String familyId;
  final DateTime weekStart;
  final DateTime now;
  final List<UserModel> members;
  final int weekOffset;
  final int weatherRefreshEpoch;

  const DisplayWeekData({
    super.key,
    required this.familyId,
    required this.weekStart,
    required this.now,
    required this.members,
    this.weekOffset = 0,
    this.weatherRefreshEpoch = 0,
  });

  @override
  State<DisplayWeekData> createState() => _DisplayWeekDataState();
}

class _DisplayWeekDataState extends State<DisplayWeekData> {
  StreamSubscription? _datedSub;
  StreamSubscription? _recurringSub;
  StreamSubscription? _shiftsSub;

  List<QueryDocumentSnapshot> _datedDocs = [];
  List<QueryDocumentSnapshot> _recurringDocs = [];
  List<QueryDocumentSnapshot> _shiftDocs = [];

  WeekBucketingResult? _lastKnownResult;
  bool _hasSyncError = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant DisplayWeekData oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId ||
        dateKey(oldWidget.weekStart) != dateKey(widget.weekStart) ||
        !haveSameMemberUids(oldWidget.members, widget.members)) {
      _subscribe();
    } else if (oldWidget.now.minute != widget.now.minute && _lastKnownResult != null) {
      // Ny minut: uppdatera renderingen
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cancelSubs();
    DisplayLog.instance.activeWeekSubscriptions = 0;
    super.dispose();
  }

  void _cancelSubs() {
    _datedSub?.cancel();
    _recurringSub?.cancel();
    _shiftsSub?.cancel();
  }

  void _subscribe() {
    _cancelSubs();
    if (widget.familyId.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasSyncError = false;
      });
      DisplayLog.instance.activeWeekSubscriptions = 0;
      return;
    }

    setState(() {
      _isLoading = _lastKnownResult == null;
      _hasSyncError = false;
    });

    DisplayLog.instance.log(
      'prenumeration',
      'Startar veckoprenumerationer för vecka ${dateKey(widget.weekStart)}',
    );
    DisplayLog.instance.activeWeekSubscriptions = 3;

    final db = FirebaseFirestore.instance;
    // Intervall från söndag före till söndag efter (samma säkerhetsmarginal som mobilen)
    final from = dateKey(widget.weekStart.subtract(const Duration(days: 1)));
    final to = dateKey(widget.weekStart.add(const Duration(days: 7)));

    // 1. Daterade händelser
    _datedSub = db
        .collection('planner_events')
        .where('familyId', isEqualTo: widget.familyId)
        .where('date', isGreaterThanOrEqualTo: from)
        .where('date', isLessThanOrEqualTo: to)
        .snapshots()
        .listen(
      (snap) {
        _datedDocs = snap.docs;
        _rebuildBuckets();
      },
      onError: (e, stack) {
        developer.log('DisplayWeekData: fel i daterade händelser',
            error: e, stackTrace: stack);
        DisplayLog.instance.log('strömfel', 'Fel i daterade händelser: $e');
        if (mounted) setState(() => _hasSyncError = true);
      },
    );

    // 2. Återkommande händelser
    _recurringSub = db
        .collection('planner_events')
        .where('familyId', isEqualTo: widget.familyId)
        .where('isRecurring', isEqualTo: true)
        .snapshots()
        .listen(
      (snap) {
        _recurringDocs = snap.docs;
        _rebuildBuckets();
      },
      onError: (e, stack) {
        developer.log('DisplayWeekData: fel i återkommande händelser',
            error: e, stackTrace: stack);
        DisplayLog.instance.log('strömfel', 'Fel i återkommande händelser: $e');
        if (mounted) setState(() => _hasSyncError = true);
      },
    );

    // 3. Arbetspass
    _shiftsSub = db
        .collection('work_shifts')
        .where('familyId', isEqualTo: widget.familyId)
        .snapshots()
        .listen(
      (snap) {
        _shiftDocs = snap.docs;
        _rebuildBuckets();
      },
      onError: (e, stack) {
        developer.log('DisplayWeekData: fel i arbetspass',
            error: e, stackTrace: stack);
        DisplayLog.instance.log('strömfel', 'Fel i arbetspass: $e');
        if (mounted) setState(() => _hasSyncError = true);
      },
    );
  }

  void _rebuildBuckets() {
    try {
      final seen = <String>{};
      final mergedEvents = <QueryDocumentSnapshot>[];
      for (final doc in _datedDocs) {
        if (seen.add(doc.id)) mergedEvents.add(doc);
      }
      for (final doc in _recurringDocs) {
        if (seen.add(doc.id)) mergedEvents.add(doc);
      }

      final result = bucketWeekData(
        members: widget.members,
        events: mergedEvents,
        shifts: _shiftDocs,
        weekStart: widget.weekStart,
      );

      if (mounted) {
        setState(() {
          _lastKnownResult = result;
          _isLoading = false;
          _hasSyncError = false;
        });
      }
    } catch (e, stack) {
      developer.log('DisplayWeekData: bucketing misslyckades',
          error: e, stackTrace: stack);
      if (mounted) setState(() => _hasSyncError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastKnownResult ??
        bucketWeekData(
          members: widget.members,
          events: const [],
          shifts: const [],
          weekStart: widget.weekStart,
        );

    final foldResult = foldFamilyEvents(result, widget.members);
    final provider = context.watch<FamilyProvider>();

    return DisplayWeekBoard(
      data: foldResult.bucketing,
      foldedDocIds: foldResult.foldedDocIds,
      weekStart: widget.weekStart,
      now: widget.now,
      members: widget.members,
      homeLat: provider.homeLat,
      homeLon: provider.homeLon,
      weekOffset: widget.weekOffset,
      weatherRefreshEpoch: widget.weatherRefreshEpoch,
      hasSyncError: _hasSyncError,
      isLoading: _isLoading,
    );
  }
}
