import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/photo_crop.dart';
import '../../widgets/cropped_photo.dart';

/// Frame a person on a photo (#37): a square frame to move by dragging and
/// resize by its corner handle. Pops with the [PhotoCrop] in pixels of the
/// original image, or null when cancelled.
class CropEditorScreen extends ConsumerStatefulWidget {
  const CropEditorScreen({super.key, required this.url, required this.headers, required this.title, this.initialCrop});

  final String url;
  final Map<String, String> headers;
  final String title;

  /// The crop to start with, as the API sends it - else a centred frame.
  final Object? initialCrop;

  @override
  ConsumerState<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends ConsumerState<CropEditorScreen> {
  static const _handleSize = 28.0;
  static const _minSideOnScreen = 40.0;

  late final Future<ui.Image> _image = ref.read(networkImageLoaderProvider)(widget.url, widget.headers);

  /// The frame, in image pixels.
  Rect? _frame;

  Rect _initialFrame(Size imageSize) {
    final crop = PhotoCrop.fromJson(widget.initialCrop, imageSize) ?? PhotoCrop.centered(imageSize);
    final side = math.min(crop.width, crop.height).toDouble();
    return _clamp(Rect.fromLTWH(crop.left.toDouble(), crop.top.toDouble(), side, side), imageSize);
  }

  Rect _clamp(Rect frame, Size imageSize) {
    final side = frame.width.clamp(1.0, imageSize.shortestSide);
    final left = frame.left.clamp(0.0, imageSize.width - side);
    final top = frame.top.clamp(0.0, imageSize.height - side);
    return Rect.fromLTWH(left, top, side, side);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            key: const Key('saveCropButton'),
            onPressed: _frame == null ? null : () => Navigator.of(context).pop(PhotoCrop.fromRect(_frame!)),
            child: Text(l10n.save, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<ui.Image>(
          future: _image,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48));
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
            final image = snapshot.data!;
            final imageSize = Size(image.width.toDouble(), image.height.toDouble());
            if (_frame == null) {
              // After this build: the Save button needs the frame too.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _frame == null) setState(() => _frame = _initialFrame(imageSize));
              });
              return const SizedBox.shrink();
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                // The image fitted into the space, like BoxFit.contain.
                final scale = math.min(
                  constraints.maxWidth / imageSize.width,
                  constraints.maxHeight / imageSize.height,
                );
                final shown = Size(imageSize.width * scale, imageSize.height * scale);
                final origin = Offset(
                  (constraints.maxWidth - shown.width) / 2,
                  (constraints.maxHeight - shown.height) / 2,
                );
                final frame = _frame!;
                final onScreen = Rect.fromLTWH(
                  origin.dx + frame.left * scale,
                  origin.dy + frame.top * scale,
                  frame.width * scale,
                  frame.height * scale,
                );
                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: origin & shown,
                      child: RawImage(image: image, fit: BoxFit.fill),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(child: CustomPaint(painter: _ShadePainter(onScreen))),
                    ),
                    Positioned.fromRect(
                      rect: onScreen,
                      child: GestureDetector(
                        key: const Key('cropFrame'),
                        onPanUpdate: (details) => setState(() {
                          _frame = _clamp(frame.shift(details.delta / scale), imageSize);
                        }),
                      ),
                    ),
                    Positioned(
                      left: onScreen.right - _handleSize / 2,
                      top: onScreen.bottom - _handleSize / 2,
                      child: GestureDetector(
                        key: const Key('cropHandle'),
                        onPanUpdate: (details) => setState(() {
                          final grow = (details.delta.dx + details.delta.dy) / 2 / scale;
                          final side = math.max(frame.width + grow, _minSideOnScreen / scale);
                          _frame = _clamp(Rect.fromLTWH(frame.left, frame.top, side, side), imageSize);
                        }),
                        child: Container(
                          width: _handleSize,
                          height: _handleSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black54),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Darkens everything outside the frame and outlines it.
class _ShadePainter extends CustomPainter {
  _ShadePainter(this.frame);

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(frame));
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawRect(
      frame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ShadePainter old) => old.frame != frame;
}
