import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/photo_crop.dart';

void main() {
  const imageSize = Size(400, 300);

  test('reads the crop of the API, missing values like GEDCOM 7 (#37)', () {
    expect(PhotoCrop.fromJson(null, imageSize), isNull);
    final full = PhotoCrop.fromJson({'top': 10, 'left': 20, 'height': 30, 'width': 40}, imageSize)!;
    expect(full.toJson(), {'top': 10, 'left': 20, 'height': 30, 'width': 40});
    final partial = PhotoCrop.fromJson({'top': null, 'left': 100, 'height': null, 'width': null}, imageSize)!;
    expect(partial.toJson(), {'top': 0, 'left': 100, 'height': 300, 'width': 300});
  });

  test('a new frame is a centred square over half the shorter side', () {
    expect(PhotoCrop.centered(imageSize).toJson(), {'top': 75, 'left': 125, 'height': 150, 'width': 150});
  });
}
