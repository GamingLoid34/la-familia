import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/family_note.dart';
import '../models/user_model.dart';
import '../services/widget_service.dart';
import '../utils/date_utils.dart';
import '../utils/recurrence.dart';

class FamilyProvider extends ChangeNotifier {
  UserModel? _currentUser;
  List<UserModel> _familyMembers = [];
  List<QueryDocumentSnapshot> _chores = [];
  List<QueryDocumentSnapshot> _todayDateEvents = [];
  List<QueryDocumentSnapshot> _tomorrowDateEvents = [];
  List<QueryDocumentSnapshot> _recurringEvents = [];
  List<QueryDocumentSnapshot> _todayEventsCached = [];
  List<QueryDocumentSnapshot> _tomorrowEventsCached = [];
  List<FamilyNote> _todayNotes = [];
  List<QueryDocumentSnapshot> _routines = [];
  List<QueryDocumentSnapshot> _todayMeals = [];

  double? _homeLat;
  double? _homeLon;
  String? _homeName;
  Map<String, List<String>> _foodPrefs = const {
    'allergier': [],
    'ogillar': [],
    'gillar': [],
  };

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
  StreamSubscription? _familyDocSub;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get familyMembers => _familyMembers;
  List<QueryDocumentSnapshot> get chores => _chores;

  /// Dagens händelser (cachad — stabil referens för context.select).
  List<QueryDocumentSnapshot> get todayEvents => _todayEventsCached;

  /// Morgondagens händelser (cachad).
  List<QueryDocumentSnapshot> get tomorrowEvents => _tomorrowEventsCached;

  void _rebuildEventCaches() {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));

    final todaySeen = <String>{};
    final todayOut = <QueryDocumentSnapshot>[];
    for (final doc in _todayDateEvents) {
      if (todaySeen.add(doc.id)) todayOut.add(doc);
    }
    for (final doc in _recurringEvents) {
      if (todaySeen.contains(doc.id)) continue;
      if (recurringOccursOnDay(doc.data() as Map<String, dynamic>, now)) {
        todaySeen.add(doc.id);
        todayOut.add(doc);
      }
    }
    _todayEventsCached = todayOut;

    final tomSeen = <String>{};
    final tomOut = <QueryDocumentSnapshot>[];
    for (final doc in _tomorrowDateEvents) {
      if (tomSeen.add(doc.id)) tomOut.add(doc);
    }
    for (final doc in _recurringEvents) {
      if (tomSeen.contains(doc.id)) continue;
      if (recurringOccursOnDay(doc.data() as Map<String, dynamic>, tomorrow)) {
        tomSeen.add(doc.id);
        tomOut.add(doc);
      }
    }
    _tomorrowEventsCached = tomOut;
  }

  List<FamilyNote> get todayNotes => _todayNotes;

  /// Familjens morgon-/kvällsrutiner (ROADMAP Etapp 7).
  List<QueryDocumentSnapshot> get routines => _routines;

  /// Dagens middag(ar) — för "Ikväll"-kortet på Hem (ROADMAP Etapp 12).
  List<QueryDocumentSnapshot> get todayMeals => _todayMeals;

  double? get homeLat => _homeLat;
  double? get homeLon => _homeLon;
  String? get homeName => _homeName;
  bool get hasHomeLocation => _homeLat != null && _homeLon != null;
  Map<String, List<String>> get foodPrefs => _foodPrefs;
  List<String> get foodAllergier => _foodPrefs['allergier'] ?? const [];
  List<String> get foodOgillar => _foodPrefs['ogillar'] ?? const [];
  List<String> get foodGillar => _foodPrefs['gillar'] ?? const [];

  bool get isLoading => _isLoading;

  /// Tvinga omritning av alla lyssnande vyer — används när globala
  /// UI-inställningar ändras (t.ex. lågstimuli-läget).
  void refreshUi() => notifyListeners();

  /// Hemskärms-widgeten matas debounced vid varje dataändring (Etapp 13).
  Timer? _widgetDebounce;
  /// Coalescar burst av stream-updates (Fas 2½).
  Timer? _notifyTimer;
  bool _notifyPending = false;

  void _scheduleHomeWidgetUpdate() {
    _widgetDebounce?.cancel();
    _widgetDebounce = Timer(const Duration(seconds: 2), () {
      WidgetService.updateFromData(
        user: _currentUser,
        todayEvents: todayEvents,
        routines: _routines,
      );
    });
  }

  @override
  void notifyListeners() {
    if (_notifyTimer?.isActive ?? false) {
      _notifyPending = true;
      return;
    }
    super.notifyListeners();
    _scheduleHomeWidgetUpdate();
    _notifyTimer = Timer(const Duration(milliseconds: 50), () {
      if (_notifyPending) {
        _notifyPending = false;
        notifyListeners();
      }
    });
  }

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
    _todayEventsCached = [];
    _tomorrowEventsCached = [];
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
    _familyDocSub?.cancel();
    _homeLat = null;
    _homeLon = null;
    _homeName = null;
    _foodPrefs = const {
      'allergier': [],
      'ogillar': [],
      'gillar': [],
    };

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
      _familyDocSub?.cancel();
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
      _todayEventsCached = [];
      _tomorrowEventsCached = [];
      _todayNotes = [];
      _homeLat = null;
      _homeLon = null;
      _homeName = null;
      _foodPrefs = const {
        'allergier': [],
        'ogillar': [],
        'gillar': [],
      };
      notifyListeners();
      return;
    }

    // Familjedokument (hemposition m.m.)
    _familyDocSub?.cancel();
    _familyDocSub = FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .snapshots()
        .listen((snap) {
      if (snap.exists) {
        final d = snap.data()!;
        _homeLat = (d['homeLat'] as num?)?.toDouble();
        _homeLon = (d['homeLon'] as num?)?.toDouble();
        _homeName = d['homeName'] as String?;
        final prefs = d['foodPrefs'];
        if (prefs is Map) {
          List<String> listOf(String key) =>
              (prefs[key] as List?)?.whereType<String>().toList() ?? [];
          _foodPrefs = {
            'allergier': listOf('allergier'),
            'ogillar': listOf('ogillar'),
            'gillar': listOf('gillar'),
          };
        } else {
          _foodPrefs = const {
            'allergier': [],
            'ogillar': [],
            'gillar': [],
          };
        }
      } else {
        _homeLat = null;
        _homeLon = null;
        _homeName = null;
        _foodPrefs = const {
          'allergier': [],
          'ogillar': [],
          'gillar': [],
        };
      }
      notifyListeners();
    });

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
      _rebuildEventCaches();
      notifyListeners();
    });

    // Morgondagens daterade händelser — för "I morgon"-vyn.
    _tomorrowSub?.cancel();
    _tomorrowSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now.add(const Duration(days: 1))))
        .snapshots().listen((snap) {
      _tomorrowDateEvents = snap.docs;
      _rebuildEventCaches();
      notifyListeners();
    });

    // Återkommande händelser — expanderas i todayEvents-gettern.
    _recurringSub?.cancel();
    _recurringSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('isRecurring', isEqualTo: true)
        .snapshots().listen((snap) {
      _recurringEvents = snap.docs;
      _rebuildEventCaches();
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
    _widgetDebounce?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}