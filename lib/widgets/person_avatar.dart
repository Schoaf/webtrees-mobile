import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A circular avatar — a stored photo when there is one, else a sex-coded
/// silhouette — with a diagonal banderole across the top-left for a
/// deceased person (matches the family-tree view's card treatment).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.sex,
    this.isDead = false,
    this.size = 42,
    this.photoUrl,
    this.photoHeaders,
    this.onTap,
    this.editable = false,
  });

  /// webtrees sex code: "M", "F", "U" (unknown) or "X".
  final String sex;
  final bool isDead;
  final double size;

  /// The thumbnail to show instead of the silhouette, if any.
  final String? photoUrl;

  /// Headers (session cookie) needed to fetch [photoUrl] — webtrees serves
  /// media behind the same session as everything else.
  final Map<String, String>? photoHeaders;

  final VoidCallback? onTap;

  /// Shows a small camera badge over the photo and signals that [onTap]
  /// changes the photo (upload/camera) rather than opening it full-screen —
  /// used while the person's facts are in edit mode.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final isFemale = sex == 'F';
    final background = isFemale
        ? AppColors.femaleAvatarBg
        : AppColors.maleAvatarBg;
    final foreground = isFemale
        ? AppColors.femaleAvatarFg
        : AppColors.maleAvatarFg;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: Stack(
                children: [
                  hasPhoto
                      ? Image.network(
                          photoUrl!,
                          headers: photoHeaders,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _Silhouette(
                            background: background,
                            foreground: foreground,
                          ),
                        )
                      : _Silhouette(background: background, foreground: foreground),
                  if (isDead) _Banderole(size: size),
                ],
              ),
            ),
            if (editable)
              Positioned(
                bottom: -size * 0.06,
                right: -size * 0.06,
                child: Container(
                  width: size * 0.46,
                  height: size * 0.46,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: size * 0.24,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A diagonal banderole across the top-left of the (already-clipped)
/// circular avatar — deliberately wide/long and let the parent `ClipOval`
/// crop it, rather than computing the exact chord geometry.
class _Banderole extends StatelessWidget {
  const _Banderole({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: size * 0.08,
      left: -size * 0.3,
      child: Transform.rotate(
        angle: -math.pi / 4,
        child: Container(width: size * 1.3, height: size * 0.18, color: AppColors.textPrimary),
      ),
    );
  }
}

class _Silhouette extends StatelessWidget {
  const _Silhouette({required this.background, required this.foreground});

  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: background,
      child: CustomPaint(painter: _PersonSilhouettePainter(color: foreground)),
    );
  }
}

/// Head + shoulders silhouette that fills the circle edge-to-edge — unlike
/// Material's `Icons.person`, which has built-in padding baked into the
/// glyph and looks small inside a tightly-cropped circle.
class _PersonSilhouettePainter extends CustomPainter {
  const _PersonSilhouettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(w / 2, h * 0.35), w * 0.22, paint);

    final path = Path()
      ..moveTo(w * 0.08, h * 1.05)
      ..cubicTo(w * 0.08, h * 0.72, w * 0.32, h * 0.55, w / 2, h * 0.55)
      ..cubicTo(w * 0.68, h * 0.55, w * 0.92, h * 0.72, w * 0.92, h * 1.05)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PersonSilhouettePainter oldDelegate) =>
      oldDelegate.color != color;
}

