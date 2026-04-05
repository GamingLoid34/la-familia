import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class FamilyProvider extends ChangeNotifier {
  UserModel? _currentUser;
  List<UserModel> _familyMembers = [];
  List<QueryDocumentSnapshot> _chores = [];
  List<QueryDocumentSnapshot> _todayEvents = [];
  
  bool _isLoading = true;

  StreamSubscription? _userSub;
  StreamSubscription? _familySub;
  StreamSubscription? _choresSub;
  StreamSubscription? _eventsSub;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get familyMembers => _familyMembers;
  List<QueryDocumentSnapshot> get chores => _chores;
  List<QueryDocumentSnapshot> get todayEvents => _todayEvents;
  bool get isLoading => _isLoading;

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
    _todayEvents = [];
    _isLoading = false;
    
    _userSub?.cancel();
    _familySub?.cancel();
    _choresSub?.cancel();
    _eventsSub?.cancel();
    
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
      _familyMembers = [];
      _chores = [];
      _todayEvents = [];
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

    // Lyssna på dagens händelser
    _eventsSub?.cancel();
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    _eventsSub = FirebaseFirestore.instance.collection('planner_events')
        .where('familyId', isEqualTo: familyId)
        .where('date', isEqualTo: todayStr)
        .snapshots().listen((snap) {
      _todayEvents = snap.docs;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _familySub?.cancel();
    _choresSub?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}