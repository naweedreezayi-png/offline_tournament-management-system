import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Logo of the offline edition: a champion's medal (ring + star) hanging from two
/// ribbons, on a round green badge. Drawn purely in code, so it scales crisply
/// at any size without an image asset.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.45),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.2),
      child: const CustomPaint(painter: _MedalPainter()),
    );
  }
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final white = Paint()..color = Colors.white;
    final amber = Paint()..color = AppColors.cyan; // amber accent

    // Two ribbon tails behind the medal.
    final left = Path()
      ..moveTo(w * 0.22, 0)
      ..lineTo(w * 0.46, 0)
      ..lineTo(w * 0.54, h * 0.5)
      ..lineTo(w * 0.34, h * 0.5)
      ..close();
    final right = Path()
      ..moveTo(w * 0.54, 0)
      ..lineTo(w * 0.78, 0)
      ..lineTo(w * 0.66, h * 0.5)
      ..lineTo(w * 0.46, h * 0.5)
      ..close();
    canvas.drawPath(left, white..color = Colors.white.withValues(alpha: 0.85));
    canvas.drawPath(right, white..color = Colors.white);

    // Medal ring.
    final c = Offset(w * 0.5, h * 0.64);
    final r = w * 0.34;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(c, r * 0.78, Paint()..color = AppColors.primaryDark);

    // Five-point star in the middle.
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r * 0.62 : r * 0.26;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(c.dx + radius * math.cos(a), c.dy + radius * math.sin(a));
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, amber);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
