import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Where captures are written and how they reach the phone's gallery.
class MediaStore {
  static const album = 'Creative Camera';

  /// A fresh file path in the app's temp folder.
  static Future<String> newPath(String prefix, String ext) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/captures');
    await folder.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${folder.path}/${prefix}_$stamp.$ext';
  }

  /// Copies a picture into the Photos / Gallery app.
  static Future<bool> saveImage(String path) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putImage(path, album: album);
      return true;
    } on GalException {
      return false;
    }
  }

  /// Copies a video into the Photos / Gallery app.
  static Future<bool> saveVideo(String path) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putVideo(path, album: album);
      return true;
    } on GalException {
      return false;
    }
  }
}
