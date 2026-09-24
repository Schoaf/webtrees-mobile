import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/gedcom.dart';
import 'person_avatar.dart';

/// A tappable person row — avatar, name (+ maiden name if given), lifespan,
/// chevron — as used on Start (startperson), Suche (results) and Person
/// (parents/spouse/children). Takes the API's `personSummary` JSON shape.
class PersonCard extends ConsumerWidget {
  const PersonCard({
    super.key,
    required this.person,
    this.maidenName,
    this.onTap,
    this.compact = false,
    this.subtitle,
  });

  final Map<String, dynamic> person;
  final String? maidenName;
  final VoidCallback? onTap;
  final bool compact;

  /// Replaces the lifespan line when set, e.g. a birthday countdown.
  final String? subtitle;

  /// Living people: the full birth date, not just the year, and no
  /// trailing dash — that dash means "born, still open-ended" for a
  /// year-only display, but reads oddly after a full date. Deceased
  /// people: webtrees' own "birth year–death year" lifespan string.
  String _defaultSubtitle() {
    final isDead = person['isDead'] as bool? ?? false;
    final lifespan = person['lifespan'] as String? ?? '';
    if (isDead) return lifespan;

    final birth = person['birth'] as Map<String, dynamic>?;
    final birthDate = birth?['date'] as Map<String, dynamic>?;
    final text = birthDate?['text'] as String?;
    return (text != null && text.isNotEmpty) ? text : lifespan;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sex = person['sex'] as String? ?? 'U';
    final isDead = person['isDead'] as bool? ?? false;
    final name = stripNameSlashes(person['name'] as String? ?? '(kein Name)');
    final lifespan = subtitle ?? _defaultSubtitle();
    final avatarSize = compact ? 40.0 : 42.0;
    final photoHeaders = ref.read(webtreesClientProvider).imageHeaders;

    final sexColor = sex == 'F'
        ? AppColors.femaleAvatarFg
        : AppColors.maleAvatarFg;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            // IntrinsicHeight gives the Row a bounded height to stretch
            // against — inside a ListView an item's height is otherwise
            // unbounded, and crossAxisAlignment.stretch needs a real number
            // to stretch to.
            child: Stack(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sex is also readable at a glance here — not just on
                      // the avatar icon, which can be hard to make out once
                      // a photo is set.
                      Container(width: 4, color: sexColor),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 11, 12, 11),
                          child: Row(
                            children: [
                              PersonAvatar(
                                sex: sex,
                                isDead: isDead,
                                size: avatarSize,
                                photoUrl: person['thumb'] as String?,
                                photoHeaders: photoHeaders,
                                // The whole row carries its own banderole
                                // below, spanning the full card rather than
                                // just this small avatar circle.
                                showBanderole: false,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RichText(
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                        children: [
                                          TextSpan(text: name),
                                          if (maidenName != null &&
                                              maidenName!.isNotEmpty)
                                            TextSpan(
                                              text: ' geb. $maidenName',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w400,
                                                color: AppColors.textTertiary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (lifespan.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          lifespan,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: AppColors.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Spans the entire row (not just the avatar) so a deceased
                // person is unmistakable even when the avatar is small or
                // covered by a photo.
                if (isDead) const Positioned.fill(child: DeathBanderole()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
