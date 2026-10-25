import 'dart:ui';

/// The part of a photo that shows one person: GEDCOM 7 `2 CROP` at their
/// link to it, in pixels of the original image (api4webtrees level 38).
class PhotoCrop {
  const PhotoCrop({required this.left, required this.top, required this.width, required this.height});

  final int left;
  final int top;
  final int width;
  final int height;

  /// Null for no crop. Missing values as GEDCOM 7 has it: 0, or up to the
  /// image edge - which needs [imageSize].
  static PhotoCrop? fromJson(Object? json, Size imageSize) {
    if (json is! Map) return null;
    final left = json['left'] as int? ?? 0;
    final top = json['top'] as int? ?? 0;
    return PhotoCrop(
      left: left,
      top: top,
      width: json['width'] as int? ?? (imageSize.width.round() - left),
      height: json['height'] as int? ?? (imageSize.height.round() - top),
    );
  }

  /// A centred square over half the shorter side - a start for a new frame.
  factory PhotoCrop.centered(Size imageSize) {
    final side = (imageSize.shortestSide / 2).round();
    return PhotoCrop(
      left: ((imageSize.width - side) / 2).round(),
      top: ((imageSize.height - side) / 2).round(),
      width: side,
      height: side,
    );
  }

  factory PhotoCrop.fromRect(Rect rect) =>
      PhotoCrop(left: rect.left.round(), top: rect.top.round(), width: rect.width.round(), height: rect.height.round());

  /// This frame after turning the image (of [imageSize], as shown now) a
  /// quarter turn clockwise: the left edge becomes the top one, the height
  /// the width - as api4webtrees' MediaRotate turns a crop.
  PhotoCrop turnedClockwise(Size imageSize) =>
      PhotoCrop(left: imageSize.height.round() - top - height, top: left, width: height, height: width);

  Rect get rect => Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());

  Map<String, int> toJson() => {'top': top, 'left': left, 'height': height, 'width': width};
}
