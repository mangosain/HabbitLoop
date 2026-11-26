import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/palette.dart';
import 'screens/auth.dart';
import 'services/daily_quote_rotation.dart';
import 'firebase_options.dart';
import 'widgets/brand.dart';
import 'widgets/firebase_connection_banner.dart';
import 'widgets/shared_element.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  runApp(const HabitLoopApp());
}

class HabitLoopApp extends StatefulWidget {
  const HabitLoopApp({super.key});

  @override
  State<HabitLoopApp> createState() => _HabitLoopAppState();
}

class _HabitLoopAppState extends State<HabitLoopApp>
    with WidgetsBindingObserver {
  bool _backgrounded = false;
  final _quotes = DailyQuoteRotation.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    firebaseAvailability.addListener(_retryQuotes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_backgrounded) unawaited(_quotes.open());
    });
  }

  void _retryQuotes() {
    if (!_backgrounded &&
        firebaseAvailability.value == FirebaseAvailability.connected) {
      unawaited(_quotes.retryWhenConnected());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgrounded = true;
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      unawaited(_quotes.open());
    }
  }

  @override
  void dispose() {
    firebaseAvailability.removeListener(_retryQuotes);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static final _lightTheme = appTheme();
  static final _darkTheme = appTheme(dark: true);
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: themeMode,
    builder: (context, mode, _) => MaterialApp(
      title: 'HabitLoop',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: mode,
      home: const LuminousSplash(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: appStatusBarStyle(Theme.of(context).brightness),
        child: FirebaseConnectionBanner(
          monitor: firebaseAvailability,
          child: child!,
        ),
      ),
    ),
  );
}

class LuminousSplash extends StatefulWidget {
  const LuminousSplash({super.key});
  @override
  State<LuminousSplash> createState() => _LuminousSplashState();
}

class _LuminousSplashState extends State<LuminousSplash> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    final minimumPresentation = Future<void>.delayed(
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 360),
    );
    try {
      final (_, prefs) = await (
        Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
        SharedPreferences.getInstance(),
      ).wait;
      if (!mounted) return;
      firebaseAvailability.reset();
      await minimumPresentation;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        sharedRoute<void>(
          context,
          prefs.getBool('onboarding_seen') == true
              ? const AuthGate()
              : const OnboardingScreen(),
        ),
      );
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'HabitLoop startup',
        ),
      );
      if (!mounted) return;
      if (error is FirebaseException) firebaseAvailability.reportUnavailable();
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.cream,
    body: Center(
      child: _failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('HabitLoop could not start.'),
                TextButton(
                  onPressed: () {
                    setState(() => _failed = false);
                    unawaited(_start());
                  },
                  child: const Text('Try again'),
                ),
              ],
            )
          : const BrandLoading(),
    ),
  );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int page = 0;
  static const content = [
    (
      Icons.fact_check_rounded,
      'Track Your Habits',
      'Build routines, stay consistent and make space for your daily wins.',
      AppPalette.mint,
    ),
    (
      Icons.notifications_active_rounded,
      'Stay Reminded',
      'Flexible device reminders keep your plans on your mind.',
      AppPalette.yellow,
    ),
    (
      Icons.insights_rounded,
      'See Your Progress',
      'Review your days and enjoy the feeling of moving forward.',
      AppPalette.lavender,
    ),
  ];
  Future<void> complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(sharedRoute<void>(context, const AuthGate()));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const BrandMark(size: 48),
                TextButton(onPressed: complete, child: const Text('Skip')),
              ],
            ),
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: content.length,
                onPageChanged: (i) => setState(() => page = i),
                itemBuilder: (context, i) {
                  final item = content[i];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 480),
                        curve: Curves.easeOutCubic,
                        width: 235,
                        height: 235,
                        decoration: BoxDecoration(
                          color: item.$4,
                          borderRadius: BorderRadius.circular(78),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(item.$1, color: AppPalette.green, size: 119),
                            const Positioned(
                              top: 21,
                              right: 27,
                              child: Icon(
                                Icons.auto_awesome,
                                color: AppPalette.amber,
                                size: 35,
                              ),
                            ),
                            const Positioned(
                              bottom: 28,
                              left: 18,
                              child: Icon(
                                Icons.spa,
                                color: AppPalette.deepGreen,
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 42),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text(
                        item.$3,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                content.length,
                (i) => AnimatedContainer(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  duration: const Duration(milliseconds: 220),
                  width: i == page ? 23 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == page ? AppPalette.green : AppPalette.border,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 29),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => page == content.length - 1
                    ? complete()
                    : controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOutCubic,
                      ),
                child: Text(
                  page == content.length - 1 ? 'Get started' : 'Continue',
                ),
              ),
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    ),
  );
}
