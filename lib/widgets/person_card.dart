import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'person_avatar.dart';

/// A tappable person row — avatar, name (+ maiden name if given), lifespan,
/// chevron — as used on Start (startperson), Suche (results) and Person
/// (parents/spouse/children). Takes the API's `personSummary` JSON shape.
class PersonCard extends StatelessWidget {
  const PersonCard({
    super.key,
    required this.person,
    this.maidenName,
    this.onTap,
    this.compact = false,
  });

  final Map<String, dynamic> person;
  final String? maidenName;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sex = person['sex'] as String? ?? 'U';
    final isDead = person['isDead'] as bool? ?? false;
    final name = person['name'] as String? ?? '(kein Name)';
    final lifespan = person['lifespan'] as String? ?? '';
    final avatarSize = compact ? 40.0 : 42.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              PersonAvatar(sex: sex, isDead: isDead, size: avatarSize),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                        children: [
                          TextSpan(text: name),
                          if (maidenName != null && maidenName!.isNotEmpty)
                            TextSpan(
                              text: ' geb. $maidenName',
                              style: const TextStyle(fontWeight: FontWeight.w400, color: AppColors.textTertiary),
                            ),
                        ],
                      ),
                    ),
                    if (lifespan.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(lifespan, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
