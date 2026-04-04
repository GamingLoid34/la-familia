import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Import av dina sidor
import 'screens/dashboard_page.dart';
import 'screens/planner_page.dart';
import 'screens/chores_page.dart';
import 'screens/settings_page.dart';
import 'screens/login_page.dart';
import 'screens/onboarding_page.dart';
import 'screens/splash_screen.dart';
import 'app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('sv');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _weekday = DateTime.now().weekday;
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    _scheduleMidnightRebuild();
  }

  void _scheduleMidnightRebuild() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(tomorrow.difference(now), () {
      if (mounted) {
        setState(() => _weekday = DateTime.now().weekday);
        _scheduleMidnightRebuild();
      }
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La Familia',
      debugShowCheckedModeBanner: false,
      // --- Språkinställningar för svenska datum mm ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('sv', 'SE')],

      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F0ED),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.getNpfDayColor(_weekday),
          brightness: Brightness.light,
        ),
      ),
      // Show splash screen first, it navigates to AuthWrapper when done
      home: const SplashScreen(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const FamilyCheckWrapper();
        }
        return const LoginPage();
      },
    );
  }
}

class FamilyCheckWrapper extends StatelessWidget {
  const FamilyCheckWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          if (data['familyId'] != null &&
              data['familyId'].toString().isNotEmpty) {
            return const MainPage();
          }
        }

        return const OnboardingPage();
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  late PageController _pageController;

  // Listan över sidor
  final List<Widget> _pages = [
    const DashboardPage(), // Index 0: Hem
    const PlannerPage(), // Index 1: Planering
    const ChoresPage(), // Index 2: Sysslor
    const SettingsPage(), // Index 3: Inställningar
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // När man klickar i menyn
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    int weekday = DateTime.now().weekday;
    Color activeColor = AppTheme.getDayAccentColor(weekday);

    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    Widget bodyContent = PageView(
      controller: _pageController,
      onPageChanged: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      children: _pages,
    );

    Widget bottomNav = Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Hem',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded),
              label: 'Planering',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.cleaning_services_rounded),
              label: 'Sysslor',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: 'Inställningar',
            ),
          ],
          currentIndex: _selectedIndex,
          backgroundColor: Colors.white,
          selectedItemColor: activeColor,
          unselectedItemColor: Colors.grey.shade400,
          selectedIconTheme: const IconThemeData(
            size: 28,
          ), // Slight scale up (approx 1.1x from 24)
          unselectedIconTheme: const IconThemeData(size: 24),
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          onTap: _onItemTapped,
          elevation: 0,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      extendBody: true,
      body: Center(
        child: Container(
          width: isWide ? 430 : double.infinity,
          decoration: isWide
              ? const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                )
              : null,
          child: ClipRect(child: bodyContent),
        ),
      ),
      bottomNavigationBar: isWide
          ? SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [SizedBox(width: 430, child: bottomNav)],
              ),
            )
          : bottomNav,
    );
  }
}