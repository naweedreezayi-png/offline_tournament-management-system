import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// image_picker returns a path into a temporary/cache directory on most
/// platforms. That's fine for immediate display, but the OS is free to
/// clear it at any time — which is why team photos could vanish after
/// the app restarted even though everything else was still saved. This
/// copies the picked file into the app's permanent documents directory
/// so it stays valid until the user explicitly deletes the tournament.
class TeamImageStorage {
  static const _uuid = Uuid();

  static Future<String> persist(String pickedFilePath) async {
    if (kIsWeb) return pickedFilePath; // browser blob URL, kept by the browser
    final docsDir = await getApplicationDocumentsDirectory();
    final teamImagesDir = Directory(p.join(docsDir.path, 'team_images'));
    if (!await teamImagesDir.exists()) {
      await teamImagesDir.create(recursive: true);
    }
    final ext = p.extension(pickedFilePath);
    final newPath = p.join(teamImagesDir.path, '${_uuid.v4()}$ext');
    await File(pickedFilePath).copy(newPath);
    return newPath;
  }

  static Future<void> deleteAll(List<String> paths) async {
    if (kIsWeb) return;
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // best-effort cleanup; ignore failures
      }
    }
  }
}
