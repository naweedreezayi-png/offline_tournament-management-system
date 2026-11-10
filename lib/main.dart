import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' show databaseFactoryFfiWeb;
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/tournament_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_background.dart';

/// Lets any screen show a SnackBar (e.g. an "Undo delete" action) that
/// survives navigating to a different screen right afterwards.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Hides the Android navigation bar (Back / Home / Recents) like modern
/// apps do: it stays hidden while using the app, and appears only when the
/// user swipes up from the bottom edge; it hides itself again afterwards.
/// The status bar (clock, battery) stays visible.
Future<void> applySystemUiMode() async {
  try {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Browser build: SQLite runs in WebAssembly and is stored in IndexedDB.
  if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
  await applySystemUiMode();
  SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
    // The bar was revealed by a swipe (or a dialog/keyboard): hide it again
    // after a short moment so it only shows when needed.
    await Future.delayed(const Duration(seconds: 3));
    await applySystemUiMode();
  });
  runApp(const TournamentMasterApp());
}

class TournamentMasterApp extends StatefulWidget {
  const TournamentMasterApp({super.key});

  @override
  State<TournamentMasterApp> createState() => _TournamentMasterAppState();
}

class _TournamentMasterAppState extends State<TournamentMasterApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-hide the system navigation bar whenever the app returns.
    if (state == AppLifecycleState.resumed) {
      applySystemUiMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => TournamentProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Tournament Master Offline',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: rootMessengerKey,
            themeMode: settings.themeMode,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            builder: (context, child) {
              // Colours of the Android navigation bar (Back/Home/Recents)
              // follow the app theme, like other apps: light bar with dark
              // icons in light mode, dark bar with light icons in dark mode.
              final dark = Theme.of(context).brightness == Brightness.dark;
              final style = SystemUiOverlayStyle(
                systemNavigationBarColor:
                    dark ? const Color(0xFF08201A) : const Color(0xFFDDF3EA),
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: style,
                child: Directionality(
                  textDirection: settings.isRtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(child: AppBackground(dark: dark)),
                      child!,
                    ],
                  ),
                ),
              );
            },
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
