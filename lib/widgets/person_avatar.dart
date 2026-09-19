import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A circular avatar — a stored photo when there is one, else a sex-coded
/// silhouette — with a tombstone badge for a deceased person.
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
              child: hasPhoto
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
            ),
            if (isDead)
              Positioned(
                top: -size * 0.08,
                right: -size * 0.1,
                child: SizedBox(
                  width: size * 0.48,
                  height: size * 0.48,
                  child: CustomPaint(
                    painter: _TombstonePainter(color: AppColors.textSecondary),
                  ),
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

/// A simple, unambiguous headstone silhouette — an arched top on a
/// rectangular base with a cross, so it reads clearly even at small sizes
/// (unlike a generic building/church icon).
class _TombstonePainter extends CustomPainter {
  const _TombstonePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Same shape/cross proportions as the very first hand-drawn tombstone
    // (edge-to-edge, cross reaching up into the arch) — later tweaks meant
    // to fit an outline stroke ended up shrinking and re-centering the
    // whole thing, which is what made the cross look wrong. The Stack this
    // sits in uses clipBehavior: Clip.none, so the stroke isn't clipped by
    // running the shape edge-to-edge.
    final baseTop = h * 0.3;
    final path = Path()
      ..moveTo(w * 0.02, h)
      ..lineTo(w * 0.02, baseTop)
      ..arcToPoint(
        Offset(w * 0.98, baseTop),
        radius: Radius.circular(w * 0.49),
        clockwise: true,
      )
      ..lineTo(w * 0.98, h)
      ..close();

    // A white outline so the badge reads clearly against a photo or a
    // similarly-colored silhouette, without embedding it in a circular
    // backdrop.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 0.1,
    );
    canvas.drawPath(path, paint);

    // A large, high-contrast cross so it reads clearly even at small
    // avatar sizes — the previous thin cross was easy to mistake for a
    // padlock shackle.
    final crossPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final crossW = w * 0.16;
    canvas.drawRect(
      Rect.fromLTWH(w / 2 - crossW / 2, h * 0.08, crossW, h * 0.5),
      crossPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.22, h * 0.2, w * 0.56, crossW),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TombstonePainter oldDelegate) =>
      oldDelegate.color != color;
}
