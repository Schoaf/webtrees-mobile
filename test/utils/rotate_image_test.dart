import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:webtrees_mobile/utils/rotate_image.dart';

void main() {
  final wide = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 20)));

  test('turns a photo by 90° per quarter turn', () async {
    final once = img.decodeImage(await rotateImageBytes(wide, 1))!;
    expect((once.width, once.height), (20, 40));
    final twice = img.decodeImage(await rotateImageBytes(wide, 2))!;
    expect((twice.width, twice.height), (40, 20));
  });

  test('no turn leaves the bytes as they are', () async {
    expect(await rotateImageBytes(wide, 0), same(wide));
    expect(await rotateImageBytes(wide, 4), same(wide));
  });

  test('a turned photo is a JPEG', () {
    expect(jpegFilename('IMG_1234.HEIC'), 'IMG_1234.jpg');
    expect(jpegFilename('scan.png'), 'scan.jpg');
    expect(jpegFilename('photo'), 'photo.jpg');
  });
}
