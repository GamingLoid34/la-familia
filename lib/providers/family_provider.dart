import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/family_note.dart';
import '../models/user_model.dart';
import '../services/widget_service.dart';
import '../utils/date_utils.dart';
import '../utils/recurrence.dart';

class FamilyProvider extends ChangeNotifier with WidgetsBindingObserver {
  bool _syncError = false;
  DateTime? _lastSyncAt;

  bool get syncError => _syncError;
  DateTime? get lastSyncAt => _lastSyncAt;

  void _handleStreamSuccess() {
    _syncError = false;
    _lastSyncAt = DateTime.now();
  }

  void _handleStreamError(String streamName, Object e, StackTrace stack) {
    developer.log('FamilyProvider: fel i $streamName', error: e, stackTrace: stack);
    _syncError = true;
    notifyListeners();
  }
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

  /// Familj som datumprenumerationerna gäller.
  String? _activeFamilyId;
  /// dateKey som dagens/morgondagens queries är låsta till.
  String? _subscribedDateKey;
  Timer? _midnightTimer;

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

  /// Återkommande händelser i familjen.
  List<QueryDocumentSnapshot> get recurringEvents => _recurringEvents;

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
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _clearAll();
      } else {
        _initUser(user.uid);
      }
    });
  }

  int get activeSubscriptionsCount {
    var count = 0;
    if (_userSub != null) count++;
    if (_familyDocSub != null) count++;
    if (_familySub != null) count++;
    if (_choresSub != null) count++;
    if (_recurringSub != null) count++;
    if (_routinesSub != null) count++;
    if (_eventsSub != null) count++;
    if (_tomorrowSub != null) count++;
    if (_mealsSub != null) count++;
    if (_notesSub != null) count++;
    return count;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ensureDateSubscriptionsFresh();
    }
  }

  /// Om dateKey ändrats sedan senaste prenumeration → re-prenumerera
  /// dagens/morgondagens events, meals och notes.
  /// Kan tvingas vid t.ex. uppvaknande från sömn med [force].
  void ensureDateSubscriptionsFresh({bool force = false}) {
    final today = dateKey(DateTime.now());
    if (!force && _subscribedDateKey == today) return;
    _resubscribeDateBound();
  }

  void _scheduleMidnightResubscribe() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      _resubscribeDateBound();
      _scheduleMidnightResubscribe();
    });
  }

  void _resubscribeDateBound() {
    final fid = _activeFamilyId;
    if (fid == null || fid.isEmpty) return;
    _subscribeDateBound(fid);
    _rebuildEventCaches();
    notifyListeners();
  }

  void _clearAll() {
    _syncError = false;
    _lastSyncAt = null;
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
    _midnightTimer?.cancel();
    _activeFamilyId = null;
    _subscribedDateKey = null;
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
      _handleStreamSuccess();
      if (snap.exists) {
        _currentUser = UserModel.fromMap(snap.id, snap.data()!);
        _subscribeToFamilyData(_currentUser!.familyId);
      } else {
        _currentUser = null;
      }
      _isLoading = false;
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('users', e, stack));
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
      _midnightTimer?.cancel();
      _activeFamilyId = null;
      _subscribedDateKey = null;
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

    _activeFamilyId = familyId;

    // Familjedokument (hemposition m.m.)
    _familyDocSub?.cancel();
    _familyDocSub = FirebaseFirestore.instance
        .collection('families')
        .doc(familyId)
        .snapshots()
        .listen((snap) {
      _handleStreamSuccess();
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
    }, onError: (e, stack) => _handleStreamError('families', e, stack));

    // Lyssna på familjemedlemmar
    _familySub?.cancel();
    _familySub = FirebaseFirestore.instance.collection('users')
        .where('familyId', isEqualTo: familyId)
        .snapshots().listen((snap) {
      _handleStreamSuccess();
      _familyMembers = snap.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
      // Sortera: föräldrar först, sedan alfabetiskt
      _familyMembers.sort((a, b) {
        if (a.isParent && !b.isParent) return -1;
        if (!a.isParent && b.isParent) return 1;
        return a.name.compareTo(b.name);
      });
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('familyMembers', e, stack));

    // Lyssna på familjens sysslor
    _choresSub?.cancel();
    _choresSub = FirebaseFirestore.instance.collection('chores')
        .where('familyId', isEqualTo: familyId)
        .snapshots().listen((snap) {
      _handleStreamSuccess();
      _chores = snap.docs;
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('chores', e, stack));

    // Återkommande händelser — expanderas i todayEvents-gettern.
    _recurringSub?.cancel();
    _recurringSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('isRecurring', isEqualTo: true)
        .snapshots().listen((snap) {
      _handleStreamSuccess();
      _recurringEvents = snap.docs;
      _rebuildEventCaches();
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('recurringEvents', e, stack));

    // Rutiner (morgon/kväll) för hela familjen.
    _routinesSub?.cancel();
    _routinesSub = FirebaseFirestore.instance
        .collection('routines')
        .where('familyId', isEqualTo: familyId)
        .snapshots()
        .listen((snap) {
      _handleStreamSuccess();
      _routines = snap.docs;
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('routines', e, stack));

    _subscribeDateBound(familyId);
    _scheduleMidnightResubscribe();
  }

  /// Dagens/morgondagens events, meals och notes — måste bytas vid midnatt.
  void _subscribeDateBound(String familyId) {
    final now = DateTime.now();
    _subscribedDateKey = dateKey(now);

    _eventsSub?.cancel();
    _eventsSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now))
        .snapshots().listen((snap) {
      _handleStreamSuccess();
      _todayDateEvents = snap.docs;
      _rebuildEventCaches();
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('todayDateEvents', e, stack));

    _tomorrowSub?.cancel();
    _tomorrowSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now.add(const Duration(days: 1))))
        .snapshots().listen((snap) {
      _handleStreamSuccess();
      _tomorrowDateEvents = snap.docs;
      _rebuildEventCaches();
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('tomorrowDateEvents', e, stack));

    _mealsSub?.cancel();
    _mealsSub = FirebaseFirestore.instance
        .collection('meals')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now))
        .snapshots()
        .listen((snap) {
      _handleStreamSuccess();
      _todayMeals = snap.docs;
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('todayMeals', e, stack));

    _notesSub?.cancel();
    _notesSub = FirebaseFirestore.instance
        .collection('family_notes')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: dateKey(now))
        .snapshots()
        .listen((snap) {
      _handleStreamSuccess();
      _todayNotes = snap.docs.map((d) => FamilyNote.fromDoc(d)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }, onError: (e, stack) => _handleStreamError('familyNotes', e, stack));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _userSub?.cancel();
    _familySub?.cancel();
    _choresSub?.cancel();
    _eventsSub?.cancel();
    _tomorrowSub?.cancel();
    _recurringSub?.cancel();
    _notesSub?.cancel();
    _routinesSub?.cancel();
    _mealsSub?.cancel();
    _familyDocSub?.cancel();
    _widgetDebounce?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}