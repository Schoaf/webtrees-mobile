/// The family lines in view (#43): a child and a parent belong to the same
/// line when their surnames are the same (in the group set in the profile).
/// Going up from a person, the line goes on to the parent with the same
/// surname - broken only by a change of name. People of the same name
/// without such a link are different families, with colours of their own.
class FamilyLines {
  const FamilyLines({required this.lineOf, required this.labels});

  /// The line of each person in view, by xref - '' without a surname.
  final Map<String, String> lineOf;

  /// The name each line shows: its most frequent spelling.
  final Map<String, String> labels;

  /// One entry per person in view, for the counts and the colours.
  List<String> get lines => [
    for (final line in lineOf.values)
      if (line.isNotEmpty) line,
  ];

  /// [surnameOf] the people in view by xref, [parentLinks] each (child,
  /// parent) shown in the tree, [keyOf] the group of a surname.
  factory FamilyLines.build({
    required Map<String, String> surnameOf,
    required Iterable<(String child, String parent)> parentLinks,
    required String Function(String surname) keyOf,
  }) {
    final root = <String, String>{for (final xref in surnameOf.keys) xref: xref};
    String find(String xref) {
      while (root[xref] != xref) {
        xref = root[xref] = root[root[xref]!]!;
      }
      return xref;
    }

    for (final (child, parent) in parentLinks) {
      final childSurname = surnameOf[child] ?? '';
      final parentSurname = surnameOf[parent] ?? '';
      if (childSurname.isEmpty || parentSurname.isEmpty || keyOf(childSurname) != keyOf(parentSurname)) continue;
      final a = find(child);
      final b = find(parent);
      if (a != b) root[a] = b;
    }

    final members = <String, List<String>>{};
    for (final xref in surnameOf.keys) {
      if (surnameOf[xref]!.isNotEmpty) members.putIfAbsent(find(xref), () => []).add(xref);
    }

    // A line is called by its surname group - the largest of a group keeps
    // just that, so its colour stays while moving through the tree; others
    // of the same name get their first member's xref added.
    final byGroup = <String, List<List<String>>>{};
    for (final line in members.values) {
      byGroup.putIfAbsent(keyOf(surnameOf[line.first]!), () => []).add(line..sort());
    }
    final lineOf = <String, String>{for (final xref in surnameOf.keys) xref: ''};
    final labels = <String, String>{};
    for (final MapEntry(key: group, value: lines) in byGroup.entries) {
      lines.sort((a, b) {
        final bySize = b.length.compareTo(a.length);
        return bySize != 0 ? bySize : a.first.compareTo(b.first);
      });
      for (final (i, line) in lines.indexed) {
        final id = i == 0 ? group : '$group#${line.first}';
        for (final xref in line) {
          lineOf[xref] = id;
        }
        labels[id] = _mostFrequent(line.map((xref) => surnameOf[xref]!));
      }
    }
    return FamilyLines(lineOf: lineOf, labels: labels);
  }
}

/// The most frequent of [spellings], alphabetically first on a tie.
String _mostFrequent(Iterable<String> spellings) {
  final counts = <String, int>{};
  for (final spelling in spellings) {
    counts[spelling] = (counts[spelling] ?? 0) + 1;
  }
  return (counts.keys.toList()..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      }))
      .first;
}
