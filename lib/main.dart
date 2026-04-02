import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';

// Import av dina sidor
import 'screens/dashboard_page.dart';
import 'screens/planner_page.dart';
import 'screens/chores_page.dart';
import 'screens/settings_page.dart';
import 'screens/login_page.dart';
import 'app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      // Kollar om användaren är inloggad
      home: const AuthWrapper(),
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
          return const MainPage();
        }
        return const LoginPage();
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

  // Controller för att hantera swipe-funktionen
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Listan över sidor
  final List<Widget> _pages = [
    const DashboardPage(), // Index 0: Hem
    const PlannerPage(), // Index 1: Planering
    const ChoresPage(), // Index 2: Sysslor
    const SettingsPage(), // Index 3: Inställningar
  ];

  // När man klickar i menyn
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Hoppa till sidan (utan animation för att det ska kännas snabbt vid klick)
    _pageController.jumpToPage(index);
  }

  // När man swipar (uppdaterar menyn)
  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Hämtar veckodag för att färga ikonen (NPF-logik)
    int weekday = DateTime.now().weekday;
    Color activeColor = AppTheme.getNpfDayColor(weekday);

    // Justering för Onsdag (Vit) och Fredag (Ljusgul) så de syns mot vit bakgrund
    if (weekday == 3) {
      activeColor = Colors.grey[700]!;
    } else if (weekday == 5) {
      activeColor = Colors.orange[800]!;
    }

    return Scaffold(
      extendBody: true, // Gör att menyn flyter snyggt
      // HÄR ÄR ÄNDRINGEN: PageView istället för att bara visa en sida
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics:
            const BouncingScrollPhysics(), // Snygg "studs" effekt vid kanterna
        children: _pages,
      ),

      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
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
            type: BottomNavigationBarType.fixed,
            showUnselectedLabels: true,
            onTap: _onItemTapped,
            elevation: 0,
          ),
        ),
      ),
    );
  }
}
