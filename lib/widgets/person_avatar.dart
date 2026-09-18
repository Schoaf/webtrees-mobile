import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A circular avatar color-coded by sex, with a small tombstone badge for a
/// deceased person — matches the design mockup's person icons.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.sex, this.isDead = false, this.size = 42});

  /// webtrees sex code: "M", "F", "U" (unknown) or "X".
  final String sex;
  final bool isDead;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isFemale = sex == 'F';
    final background = isFemale ? AppColors.femaleAvatarBg : AppColors.maleAvatarBg;
    final foreground = isFemale ? AppColors.femaleAvatarFg : AppColors.maleAvatarFg;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(color: background, shape: BoxShape.circle),
            child: Icon(Icons.person, color: foreground, size: size * 0.55),
          ),
          if (isDead)
            Positioned(
              top: -size * 0.1,
              right: -size * 0.1,
              child: Container(
                width: size * 0.38,
                height: size * 0.38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.divider, width: 1.5),
                ),
                child: Icon(Icons.church, size: size * 0.22, color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}
