import 'package:flutter/painting.dart';

/// Colours for surnames in the tree (#43): one pastel card background per
/// surname, so a family line stands out. Few enough to tell apart - see [SurnameColors.assign].
// Nord's "Aurora" and "Frost" colours, lightened to a pastel - muted, so
// the avatars on the cards stay clear.
const surnamePalette = [
  Color(0xFFEACAC0), // terracotta
  Color(0xFFF6E7CB), // sand
  Color(0xFFD5E2CB), // sage
  Color(0xFFCCE0E0), // frost
  Color(0xFFCBD6E3), // slate
  Color(0xFFDDCCDA), // mauve
  Color(0xFFE4DBCF), // taupe
  Color(0xFFEBE6DA), // linen
];

/// Every surname without a colour of its own: the card's plain white.
const otherSurnameColor = Color(0xFFFFFFFF);

/// Hands out the palette: the most frequent surnames in view get a colour,
/// and a surname keeps the one it had as long as it can - moving to another
/// person doesn't repaint the families already seen.
class SurnameColors {
  final _assigned = <String, int>{};

  /// Colours for [surnames] (one entry per person in view) - only the most
  /// frequent ones; the others are [otherSurnameColor].
  Map<String, Color> assign(Iterable<String> surnames) {
    final counts = <String, int>{};
    for (final surname in surnames) {
      if (surname.isNotEmpty) counts[surname] = (counts[surname] ?? 0) + 1;
    }
    final top =
        (counts.keys.toList()..sort((a, b) {
              final byCount = counts[b]!.compareTo(counts[a]!);
              return byCount != 0 ? byCount : a.compareTo(b);
            }))
            .take(surnamePalette.length)
            .toList();

    final taken = <int>{};
    final result = <String, Color>{};
    // Keep earlier colours first, then fill in the new ones.
    for (final surname in top) {
      final index = _assigned[surname];
      if (index != null && taken.add(index)) result[surname] = surnamePalette[index];
    }
    for (final surname in top.where((s) => !result.containsKey(s))) {
      final index = List.generate(surnamePalette.length, (i) => i).firstWhere((i) => !taken.contains(i));
      taken.add(index);
      _assigned[surname] = index;
      result[surname] = surnamePalette[index];
    }
    return result;
  }
}

/// The colour of a line to a person with [cardColor]: the card's own
/// colour - wide enough to show on the grey canvas.
Color lineColorFor(Color cardColor) => cardColor;
