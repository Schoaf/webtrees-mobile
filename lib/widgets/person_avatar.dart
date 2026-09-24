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
    this.showBanderole = true,
  });

  /// webtrees sex code: "M", "F", "U" (unknown) or "X".
  final String sex;
  final bool isDead;
  final double size;

  /// Whether a deceased person gets the small diagonal ribbon drawn across
  /// this avatar's own circle. Set to false when the caller draws a bigger
  /// [DeathBanderole] of its own spanning a larger area (a whole list row,
  /// a whole screen's corner) instead - otherwise the two would double up.
  final bool showBanderole;

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
                  if (isDead && showBanderole) _Banderole(size: size),
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

/// A diagonal "deceased" ribbon sized to span whatever area it's placed
/// in - a full [PersonCard] row, or a screen's whole corner - rather than
/// [PersonAvatar]'s own small circular bounds (that's [_Banderole], kept
/// separate since it's clipped to the avatar's own `ClipOval` instead).
///
/// Place this as a child of a `Stack` sized to the area it should span
/// (e.g. `Positioned.fill` inside that `Stack`, or a fixed-size `SizedBox`
/// pinned to a screen corner) - it paints across exactly that area's
/// bounds via [CustomPaint], so it needs no explicit width/height of its
/// own and stays correct if that area's size changes (row width, screen
/// size on rotation, ...).
class DeathBanderole extends StatelessWidget {
  const DeathBanderole({
    super.key,
    this.thicknessFactor = 0.16,
    this.color = AppColors.textPrimary,
  });

  /// Ribbon thickness as a fraction of the shorter side of the area it
  /// spans - keeps the ribbon looking proportionate whether it's drawn
  /// across a compact list row or a whole tablet screen's corner.
  final double thicknessFactor;

  final Color color;

  @override
  Widget build(BuildContext context) {
    // The painter deliberately draws outside its own [0, size] box (the
    // rotated ribbon's corners fall outside it - see the painter below), so
    // this needs its own explicit clip: nothing upstream (a Stack's default
    // clipBehavior included) clips a CustomPaint's actual paint calls to its
    // layout size, only to a Stack's own bounds, and only when Stack's
    // overflow check - based on child *layout* geometry, which this widget's
    // small, fully-in-bounds SizedBox never trips - decides there's
    // something to clip. Without this, the ribbon silently bled into
    // whatever sat above/beside its box (e.g. PersonDetailScreen's header
    // bar, above the corner ribbon's own area).
    return ClipRect(
      child: CustomPaint(painter: _DeathBanderolePainter(color: color, thicknessFactor: thicknessFactor)),
    );
  }
}

class _DeathBanderolePainter extends CustomPainter {
  const _DeathBanderolePainter({required this.color, required this.thicknessFactor});

  final Color color;
  final double thicknessFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final thickness = size.shortestSide * thicknessFactor;

    canvas.save();
    // Pivot near the top-left corner, then rotate -45deg so the ribbon
    // crosses that corner diagonally, matching the original avatar
    // banderole's orientation.
    canvas.translate(0, size.height * 0.14);
    canvas.rotate(-math.pi / 4);
    // Wide enough that the rotated rectangle still fully covers the
    // corner after rotation, whatever the aspect ratio of `size` is.
    final span = size.width + size.height;
    canvas.drawRect(Rect.fromLTWH(-size.height * 0.3, 0, span, thickness), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DeathBanderolePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.thicknessFactor != thicknessFactor;
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

