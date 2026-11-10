import 'package:flutter/material.dart';

/// A subtle scale + fade transition that makes navigating between
/// tournament screens feel smooth and modern ("zoom in / zoom out").
class ZoomRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  ZoomRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}
