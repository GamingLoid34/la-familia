// Local-only browser test entry point. Never used by the production build.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:la_familia/main.dart' show MyApp;
import 'package:la_familia/providers/family_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Uri.base.host != 'localhost') throw StateError('Local preview only');
  await initializeDateFormatting('sv_SE');
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-hem-key',
      appId: '1:123:web:hem',
      messagingSenderId: '123',
      projectId: 'demo-vardag-hem',
      authDomain: 'demo-vardag-hem.firebaseapp.com',
    ),
  );
  await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9098);
  FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8198);
  FirebaseFunctions.instance.useFunctionsEmulator('127.0.0.1', 5008);
  runApp(
    ChangeNotifierProvider(
      create: (_) => FamilyProvider(),
      child: const MyApp(),
    ),
  );
}
