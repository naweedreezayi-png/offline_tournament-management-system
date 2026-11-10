import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// One combined splash: logo, app name and developer credit appear together
/// (the former brand screen and credit screen merged), then fade into home.
class _SplashScreenState extends State<SplashScreen> {
  bool _show = false; // fade/scale the content in
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _show = true);

    await Future.delayed(const Duration(milliseconds: 3200));
    if (!mounted) return;
    setState(() => _fadingOut = true);

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, anim, __) => const AuthGate(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: AnimatedOpacity(
        opacity: _fadingOut ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: AppBackground(dark: true)),
            SafeArea(
              child: AnimatedOpacity(
                opacity: _show ? 1 : 0,
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: _show ? 1 : 0.92,
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  child: const _SplashContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 3),
        const AppLogo(size: 140),
        const SizedBox(height: 28),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFA7F3D0)],
          ).createShader(bounds),
          child: const Text(
            'Intelligent Multi-Sport\nTournament Management\nSystem',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Offline edition · works without internet or server',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFFA9CFC0), letterSpacing: 0.4),
        ),
        const Spacer(flex: 3),
        const Text(
          'Developed by',
          style: TextStyle(fontSize: 13, color: Color(0xFFA9CFC0), letterSpacing: 1.2),
        ),
        const SizedBox(height: 6),
        const Text(
          'Naweed Rezayi',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 56,
          height: 3,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.cyan]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }
}
