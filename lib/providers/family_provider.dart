import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/family_note.dart';
import '../models/user_model.dart';
import '../utils/date_utils.dart';
import '../utils/recurrence.dart';

class FamilyProvider extends ChangeNotifier {
  UserModel? _currentUser;
  List<UserModel> _familyMembers = [];
  List<QueryDocumentSnapshot> _chores = [];
  List<QueryDocumentSnapshot> _todayDateEvents = [];
  List<QueryDocumentSnapshot> _tomorrowDateEvents = [];
  List<QueryDocumentSnapshot> _recurringEvents = [];
  List<FamilyNote> _todayNotes = [];
  List<QueryDocumentSnapshot> _routines = [];
  List<QueryDocumentSnapshot> _todayMeals = [];

  bool _isLoading = true;

  StreamSubscription? _userSub;
  StreamSubscription? _familySub;
  StreamSubscription? _choresSub;
  StreamSubscription? _eventsSub;
  StreamSubscription? _tomorrowSub;
  StreamSubscription? _recurringSub;
  StreamSubscription? _notesSub;
  StreamSubscription? _routinesSub;
  StreamSubscription? _mealsSub;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get familyMembers => _familyMembers;
  List<QueryDocumentSnapshot> get chores => _chores;

  /// Dagens händelser: events med dagens datum + återkommande som
  /// infaller idag (expanderade i klienten, deduplicerade på doc-id).
  List<QueryDocumentSnapshot> get todayEvents {
    final now = DateTime.now();
    final seen = <String>{};
    final out = <QueryDocumentSnapshot>[];
    for (final doc in _todayDateEvents) {
      if (seen.add(doc.id)) out.add(doc);
    }
    for (final doc in _recurringEvents) {
      if (seen.contains(doc.id)) continue;
      if (recurringOccursOnDay(doc.data() as Map<String, dynamic>, now)) {
        seen.add(doc.id);
        out.add(doc);
      }
    }
    return out;
  }

  /// Morgondagens händelser — för "I morgon"-vyn på Hem (NPF: förutsägbarhet).
  List<QueryDocumentSnapshot> get tomorrowEvents {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final seen = <String>{};
    final out = <QueryDocumentSnapshot>[];
    for (final doc in _tomorrowDateEvents) {
      if (seen.add(doc.id)) out.add(doc);
    }
    for (final doc in _recurringEvents) {
      if (seen.contains(doc.id)) continue;
      if (recurringOccursOnDay(doc.data() as Map<String, dynamic>, tomorrow)) {
        seen.add(doc.id);
        out.add(doc);
      }
    }
    return out;
  }

  List<FamilyNote> get todayNotes => _todayNotes;

  /// Familjens morgon-/kvällsrutiner (ROADMAP Etapp 7).
  List<QueryDocumentSnapshot> get routines => _routines;

  /// Dagens middag(ar) — för "Ikväll"-kortet på Hem (ROADMAP Etapp 12).
  List<QueryDocumentSnapshot> get todayMeals => _todayMeals;

  bool get isLoading => _isLoading;

  /// Tvinga omritning av alla lyssnande vyer — används när globala
  /// UI-inställningar ändras (t.ex. lågstimuli-läget).
  void refreshUi() => notifyListeners();

  FamilyProvider() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _clearAll();
      } else {
        _initUser(user.uid);
      }
    });
  }

  void _clearAll() {
    _currentUser = null;
    _familyMembers = [];
    _chores = [];
    _todayDateEvents = [];
    _tomorrowDateEvents = [];
    _recurringEvents = [];
    _todayNotes = [];
    _isLoading = false;

    _userSub?.cancel();
    _familySub?.cancel();
    _choresSub?.cancel();
    _eventsSub?.cancel();
    _tomorrowSub?.cancel();
    _recurringSub?.cancel();
    _notesSub?.cancel();
    _routinesSub?.cancel();
    _routines = [];
    _mealsSub?.cancel();
    _todayMeals = [];

    notifyListeners();
  }

  void _initUser(String uid) {
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((snap) {
      if (snap.exists) {
        _currentUser = UserModel.fromMap(snap.id, snap.data()!);
        _subscribeToFamilyData(_currentUser!.familyId);
      } else {
        _currentUser = null;
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  void _subscribeToFamilyData(String? familyId) {
    if (familyId == null || familyId.isEmpty) {
      _familySub?.cancel();
      _choresSub?.cancel();
      _eventsSub?.cancel();
      _tomorrowSub?.cancel();
      _recurringSub?.cancel();
      _notesSub?.cancel();
      _routinesSub?.cancel();
      _routines = [];
      _mealsSub?.cancel();
      _todayMeals = [];
      _familyMembers = [];
      _chores = [];
      _todayDateEvents = [];
      _tomorrowDateEvents = [];
      _recurringEvents = [];
      _todayNotes = [];
      notifyListeners();
      return;
    }

    // Lyssna på familjemedlemmar
    _familySub?.cancel();
    _familySub = FirebaseFirestore.instance.collection('users')
        .where('familyId', isEqualTo: familyId)
        .snapshots().listen((snap) {
      _familyMembers = snap.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
      // Sortera: föräldrar först, sedan alfabetiskt
      _familyMembers.sort((a, b) {
        if (a.isParent && !b.isParent) return -1;
        if (!a.isParent && b.isParent) return 1;
        return a.name.compareTo(b.name);
      });
      notifyListeners();
    });

    // Lyssna på familjens sysslor
    _choresSub?.cancel();
    _choresSub = FirebaseFirestore.instance.collection('chores')
        .where('familyId', isEqualTo: familyId)
        .snapshots().listen((snap) {
      _chores = snap.docs;
      notifyListeners();
    });

    // Lyssna på dagens händelser (datum migrerade till paddat format 2026-06-11).
    _eventsSub?.cancel();
    final now = DateTime.now();
    _eventsSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now))
        .snapshots().listen((snap) {
      _todayDateEvents = snap.docs;
      notifyListeners();
    });

    // Morgondagens daterade händelser — för "I morgon"-vyn.
    _tomorrowSub?.cancel();
    _tomorrowSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now.add(const Duration(days: 1))))
        .snapshots().listen((snap) {
      _tomorrowDateEvents = snap.docs;
      notifyListeners();
    });

    // Återkommande händelser — expanderas i todayEvents-gettern.
    _recurringSub?.cancel();
    _recurringSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('isRecurring', isEqualTo: true)
        .snapshots().listen((snap) {
      _recurringEvents = snap.docs;
      notifyListeners();
    });

    // Rutiner (morgon/kväll) för hela familjen.
    _routinesSub?.cancel();
    _routinesSub = FirebaseFirestore.instance
        .collection('routines')
        .where('familyId', isEqualTo: familyId)
        .snapshots()
        .listen((snap) {
      _routines = snap.docs;
      notifyListeners();
    });

    // Dagens middag (Etapp 12).
    _mealsSub?.cancel();
    _mealsSub = FirebaseFirestore.instance
        .collection('meals')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now))
        .snapshots()
        .listen((snap) {
      _todayMeals = snap.docs;
      notifyListeners();
    });

    // Dagens familjenotiser (alltid zero-paddade — ny collection).
    _notesSub?.cancel();
    final today = dateKey(now);
    _notesSub = FirebaseFirestore.instance
        .collection('family_notes')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: today)
        .snapshots()
        .listen((snap) {
      _todayNotes = snap.docs.map((d) => FamilyNote.fromDoc(d)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _familySub?.cancel();
    _choresSub?.cancel();
    _eventsSub?.cancel();
    _tomorrowSub?.cancel();
    _recurringSub?.cancel();
    _notesSub?.cancel();
    _routinesSub?.cancel();
    _mealsSub?.cancel();
    super.dispose();
  }
}