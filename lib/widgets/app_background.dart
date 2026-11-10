import 'package:flutter/material.dart';

/// Plain gradient page behind every screen, in two matching variants: deep navy
/// (dark mode) and a clearly blue-tinted sky (light mode). No picture, so text
/// and cards always sit on a calm, even colour. Drawn in code (no image asset).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.dark = true});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackgroundPainter(dark),
        size: Size.infinite,
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter(this.dark);

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width, h = size.height;

    // base: vertical blue gradient (dark: navy, light: tinted sky blue, same hue family)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0B3B2E), Color(0xFF07261E), Color(0xFF04130F)]
              : const [Color(0xFFD6F2E4), Color(0xFFC4E9D6), Color(0xFFB0DFC6)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // two very soft glows for depth (no shapes, nothing competes with the content)
    void glow(Offset c, double r, Color col) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [col, col.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(w * 0.85, h * 0.08), w * 0.9,
        (dark ? const Color(0xFF10B981) : const Color(0xFF6EE7B7)).withValues(alpha: dark ? 0.28 : 0.45));
    glow(Offset(w * 0.1, h * 0.95), w * 0.9,
        (dark ? const Color(0xFFF59E0B) : const Color(0xFFFCD34D)).withValues(alpha: dark ? 0.16 : 0.30));
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) => oldDelegate.dark != dark;
}
