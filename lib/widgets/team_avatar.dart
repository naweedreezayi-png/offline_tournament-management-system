import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'zoomable_image.dart';

class TeamAvatar extends StatelessWidget {
  final String? imagePath;
  final String name;
  final double radius;

  /// Optional override for what happens on tap (e.g. team_setup_screen
  /// uses this to open the image picker instead). When omitted, tapping
  /// a team with a photo opens it full-screen; teams without a photo do
  /// nothing on tap.
  final VoidCallback? onTap;

  const TeamAvatar({
    super.key,
    required this.name,
    this.imagePath,
    this.radius = 18,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if (imagePath != null && imagePath!.isNotEmpty && (kIsWeb || File(imagePath!).existsSync())) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundImage: kIsWeb ? NetworkImage(imagePath!) as ImageProvider : FileImage(File(imagePath!)),
      );
    } else {
      final initials = name.trim().isEmpty
          ? '?'
          : name.trim().substring(0, name.trim().length >= 2 ? 2 : 1).toUpperCase();
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        child: Text(
          initials,
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.7,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap ?? () => showZoomableImage(context, name: name, imagePath: imagePath),
      child: avatar,
    );
  }
}
