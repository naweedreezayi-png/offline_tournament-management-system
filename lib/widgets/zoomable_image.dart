import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Opens a full-screen viewer for a team's photo. If the team has no
/// photo, does nothing (there's nothing to zoom into).
void showZoomableImage(BuildContext context, {required String name, String? imagePath}) {
  if (imagePath == null || imagePath.isEmpty || (!kIsWeb && !File(imagePath).existsSync())) return;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _ZoomableImageScreen(name: name, imagePath: imagePath),
      ),
    ),
  );
}

class _ZoomableImageScreen extends StatelessWidget {
  final String name;
  final String imagePath;
  const _ZoomableImageScreen({required this.name, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(name),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: kIsWeb
                ? Image.network(imagePath, fit: BoxFit.contain)
                : Image.file(File(imagePath), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
