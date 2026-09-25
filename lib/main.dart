import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// Import av dina sidor & tjänster
import 'screens/dashboard_page.dart';
import 'screens/kalender_page.dart';
import 'screens/sysslor_page.dart';
import 'screens/settings_page.dart';
import 'screens/display/display_clock.dart';
import 'screens/display/display_shell.dart';
import 'screens/login_page.dart';
import 'screens/onboarding_page.dart';
import 'screens/splash_screen.dart';
import 'app_theme.dart';
import 'navigation/app_navigation.dart';
import 'utils/aktivitet_payload.dart';
import 'utils/pending_checklist_edits.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'theme/app_colors.dart';
import 'providers/family_provider.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'services/migration_service.dart';
import 'timer_service.dart';
import 'utils/minute_ticker.dart';
import 'utils/layout.dart';
import 'widgets/offline_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DisplayClock.init(uri: kIsWeb ? Uri.base : null);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  MinuteTicker.ensureRunning();
  
  // Initiera svenska datuminställningar
  await initializeDateFormatting('sv_SE', null);
  
  // Initiera Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Crashlytics stöds inte på web; undvik att krascha vid felrapportering.
    if (!kIsWeb) {
      FlutterError.onError = (errorDetails) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (e) {
    developer.log('Firebase init error: $e');
  }

  if (!kIsWeb) {
    await NotificationService.initialize();
  }

  // Lågstimuli-läge (NPF) — laddas före första frame så UI:t aldrig "blinkar".
  try {
    final prefs = await SharedPreferences.getInstance();
    AppTheme.lowStimuli = prefs.getBool('lowStimuli') ?? false;
    AppTheme.colorMode = ColorMode.fromStorage(prefs.getString('colorMode'));
  } catch (e) {
    developer.log('Kunde inte läsa lowStimuli: $e');
  }

  // Aktivera offline-cache för Firestore
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FamilyProvider()),
      ],
      child: const MyApp(),
    ),
  );
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
    
    // Aktivera 120Hz efter att första framen ritats
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enableHighRefreshRate();
      if (!kIsWeb) {
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFFF7F7F7),
          systemNavigationBarIconBrightness: Brightness.dark,
        ));
      }
    });
  }

  Future<void> _enableHighRefreshRate() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterDisplayMode.setHighRefreshRate();
      } catch (e) {
        developer.log('Kunde inte aktivera 120Hz: $e');
      }
    }
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
      title: 'Vardag',
      navigatorKey: AppNavigation.navigatorKey,
      debugShowCheckedModeBanner: false,

      // Språkstöd för svenska
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('sv', 'SE'),
      ],

      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.getNpfDayColor(_weekday),
          brightness: Brightness.light,
        ),
        textTheme: AppTheme.appTextTheme(ThemeData.light().textTheme),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
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

/// Sant när appen körs på web med ?display=1 i adressen (Storskärmsläge).
bool get isDisplayMode =>
    kIsWeb && Uri.base.queryParameters['display'] == '1';

/// Rotvyn efter lyckad inloggning + familjekoppling.
/// ENDA stället i appen som får avgöra MainPage vs DisplayShell.
Widget rootAfterAuth() =>
    isDisplayMode ? const DisplayShell() : const MainPage();

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
            return rootAfterAuth();
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
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    AppNavigation.tabsAvailable = true;
    AppNavigation.tab.value = _selectedIndex;
    AppNavigation.tab.addListener(_onNavigationTab);
    AktivitetSparning.instans.senaFel.addListener(_onLateSaveError);
    // Packlisteändringar som väntar på nätet: vid start, när appen kommer
    // tillbaka och när nätet återkommer.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_flushWhenReady()));
    _lifecycle = AppLifecycleListener(onResume: _flushPendingChecklists);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((c) => c != ConnectivityResult.none)) _flushPendingChecklists();
    });
    _pageController = PageController(initialPage: _selectedIndex);
    _pages = [
      const DashboardPage(),
      const KalenderPage(),
      const SysslorPage(),
      const SettingsPage(),
    ];
    // Engångsmigration: tilldela unik medlemsfärg om saknas/default-grön.
    // Fire-and-forget; den loggar internt och blockerar aldrig UI.
    MigrationService.backfillMemberColors();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      SharedPreferences.getInstance().then((prefs) {
        if (prefs.getBool('notifPermissionAsked') != true) {
          NotificationService.requestPermissions().then((_) {
            prefs.setBool('notifPermissionAsked', true);
          });
        }
      });
      // FCM: registrera enhetens token + visa förgrunds-pushar (Etapp 11).
      PushService.init();
    }

    if (kIsWeb) {
      // Webben: registrerar token om tillstånd redan beviljats + håller den färsk.
      // Själva tillståndsfrågan sker via knapp i Inställningar (iOS-krav).
      PushService.init();
    }

    // Fas 5: återschemalägg lokala notiser när providern har data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_rescheduleNotificationsWhenReady());
    });
  }

  Future<void> _rescheduleNotificationsWhenReady() async {
    if (kIsWeb || !mounted) return;
    final provider = context.read<FamilyProvider>();
    for (var i = 0; i < 60; i++) {
      if (!mounted) return;
      final fid = provider.currentUser?.familyId;
      if (!provider.isLoading && fid != null && fid.isNotEmpty) {
        unawaited(() async {
          await NotificationService.rescheduleAllForFamily(fid);
          // cancelAll() ovan tog även timerns slutnotis — lägg tillbaka den
          // om en fokustimer fortfarande räknar ner.
          final t = TimerService.instance;
          if (t.isRunning.value && t.remainingSeconds.value > 0) {
            await NotificationService.scheduleTimerDone(
              at: DateTime.now().add(Duration(seconds: t.remainingSeconds.value)),
            );
          }
        }());
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  void dispose() {
    AppNavigation.tab.removeListener(_onNavigationTab);
    AktivitetSparning.instans.senaFel.removeListener(_onLateSaveError);
    _lifecycle?.dispose();
    _connectivitySub?.cancel();
    AppNavigation.tabsAvailable = false;
    _pageController.dispose();
    super.dispose();
  }

  bool _showingLateError = false;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Bara den inloggades egna köposter i den aktiva familjen körs.
  void _flushPendingChecklists() {
    final me = context.read<FamilyProvider>().currentUser;
    final fid = me?.familyId ?? '';
    if (me == null || fid.isEmpty) return;
    final provider = context.read<FamilyProvider>();
    unawaited(PendingChecklistEdits.instance.flush(
        uid: me.uid,
        familyId: fid,
        // Byts kontot eller familjen mitt i uppspelningen avbryts den.
        stillActive: () =>
            FirebaseAuth.instance.currentUser?.uid == me.uid &&
            provider.currentUser?.uid == me.uid &&
            provider.currentUser?.familyId == fid,
        onFailed: AktivitetSparning.instans.rapporteraFel));
  }

  /// Vid start finns användaren inte direkt — vänta in providern.
  Future<void> _flushWhenReady() async {
    final provider = context.read<FamilyProvider>();
    for (var i = 0; i < 60 && mounted; i++) {
      if (!provider.isLoading &&
          (provider.currentUser?.familyId ?? '').isNotEmpty) {
        _flushPendingChecklists();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Ett nekande som kom efter att formuläret slutat vänta — sägs alltid.
  Future<void> _onLateSaveError() async {
    if (_showingLateError) return;
    final errors = AktivitetSparning.instans.senaFel.value;
    final ctx = AppNavigation.navigatorKey.currentContext;
    if (errors.isEmpty || ctx == null) return;
    _showingLateError = true;
    await showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Aktiviteten sparades inte'),
        content: Text(errors.first),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
    AktivitetSparning.instans.kvitteraFel();
    _showingLateError = false;
    if (AktivitetSparning.instans.senaFel.value.isNotEmpty) {
      unawaited(_onLateSaveError());
    }
  }

  /// En genväg någon annanstans i appen har bytt flik.
  void _onNavigationTab() {
    final index = AppNavigation.tab.value;
    if (index != _selectedIndex && mounted) _onItemTapped(index);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    AppNavigation.tab.value = index;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FamilyProvider>(); // lågstimuli/färgläge ritar om flikfältet
    final colors = AppTheme.colors();

    final size = WindowSize.of(context);
    final contentWidth = size.isExpanded
        ? WindowSize.contentMaxWidth
        : double.infinity;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      extendBody: false,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: OfflineBanner(
            child: ClipRect(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                  AppNavigation.tab.value = index;
                },
                children: _pages,
              ),
            ),
          ),
        ),
      ),
      // heightFactor: 1 — annars expanderar Align/Center till full höjd och
      // nav-pillen centreras vertikalt mitt på Fold (extendBody).
      bottomNavigationBar: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.isExpanded
                ? WindowSize.navMaxWidth
                : double.infinity,
          ),
          child: SafeArea(
            top: false,
            child: _buildBottomNav(colors),
          ),
        ),
      ),
    );
  }

  /// Flikfältet som i Android-appen Vardag: kortytan som bakgrund, vald flik
  /// i accentfärgen mörkad 25 %, ingen skugga i lågstimuli.
  Widget _buildBottomNav(AppColors colors) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.cardBorder),
        boxShadow: AppTheme.lowStimuli
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Hem',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded),
              label: 'Kalender',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.checklist_rounded),
              label: 'Sysslor',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_rounded),
              label: 'Mer',
            ),
          ],
          currentIndex: _selectedIndex,
          backgroundColor: colors.cardSurface,
          selectedItemColor: colors.navSelected,
          unselectedItemColor: colors.onCardSecondary,
          selectedIconTheme: const IconThemeData(size: 28),
          unselectedIconTheme: const IconThemeData(size: 24),
          selectedLabelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          unselectedLabelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          onTap: _onItemTapped,
          elevation: 0,
        ),
      ),
    );
  }
}