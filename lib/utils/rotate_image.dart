import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// [bytes] turned clockwise by [quarterTurns] × 90°, as JPEG - in the
/// background, a large photo takes a moment. The orientation the camera
/// stored (EXIF) is applied first, so the turn starts from what was shown.
Future<Uint8List> rotateImageBytes(Uint8List bytes, int quarterTurns) =>
    quarterTurns % 4 == 0 ? Future.value(bytes) : compute(_rotate, (bytes, quarterTurns % 4));

Uint8List _rotate((Uint8List, int) args) {
  final (bytes, quarterTurns) = args;
  final image = img.decodeImage(bytes);
  if (image == null) return bytes;
  return img.encodeJpg(img.copyRotate(img.bakeOrientation(image), angle: 90 * quarterTurns), quality: 90);
}

/// [filename] with a `.jpg` ending - [rotateImageBytes] makes a JPEG.
String jpegFilename(String filename) {
  final dot = filename.lastIndexOf('.');
  return '${dot < 0 ? filename : filename.substring(0, dot)}.jpg';
}
