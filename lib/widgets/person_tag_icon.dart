import 'package:flutter/material.dart';

/// "Personen markieren": a person with a tag - there is no such Material
/// icon, so it is two put together. [background] is what the icon sits on:
/// the tag's outline in that colour sets it off from the person.
class PersonTagIcon extends StatelessWidget {
  const PersonTagIcon({super.key, required this.background, this.size = 24, this.color});

  final Color background;
  final double size;

  /// Default: the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Icon(Icons.person_outline, size: size * 0.9, color: iconColor),
          Positioned(
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(color: background, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Icon(Icons.sell, size: size * 0.48, color: iconColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
