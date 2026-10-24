import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/photo_crop.dart';

/// Loads a network image as a decoded [ui.Image] - for its size, or to paint
/// a part of it.
Future<ui.Image> loadNetworkImage(String url, Map<String, String> headers) {
  final completer = Completer<ui.Image>();
  final stream = NetworkImage(url, headers: headers).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// [loadNetworkImage] - swapped in tests, which have no network.
final networkImageLoaderProvider = Provider<Future<ui.Image> Function(String url, Map<String, String> headers)>(
  (ref) => loadNetworkImage,
);

/// [crop] of the image at [url], filling a square of [size] - what the
/// person's photo will look like.
class CroppedPhoto extends ConsumerStatefulWidget {
  const CroppedPhoto({super.key, required this.url, required this.headers, required this.crop, this.size = 120});

  final String url;
  final Map<String, String> headers;
  final PhotoCrop crop;
  final double size;

  @override
  ConsumerState<CroppedPhoto> createState() => _CroppedPhotoState();
}

class _CroppedPhotoState extends ConsumerState<CroppedPhoto> {
  late final Future<ui.Image> _image = ref.read(networkImageLoaderProvider)(widget.url, widget.headers);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<ui.Image>(
        future: _image,
        builder: (context, snapshot) => snapshot.hasData
            ? CustomPaint(painter: _CropPainter(snapshot.data!, widget.crop.rect))
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.source);

  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) {
    // Like the server's thumbnail: the middle of the crop, covering the square.
    final side = source.shortestSide;
    final square = Rect.fromCenter(center: source.center, width: side, height: side);
    canvas.drawImageRect(image, square, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.image != image || old.source != source;
}
