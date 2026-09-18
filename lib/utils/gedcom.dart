/// GEDCOM wraps a name's surname in slashes, e.g. `"Hans /Müller/"` — that's
/// the on-disk format, not something to show someone reading the app.
String stripNameSlashes(String name) => name.replaceAll('/', '').trim();

/// Rebuilds the GEDCOM `NAME` value webtrees expects from separate given/
/// surname fields, e.g. `("Hans", "Müller")` -> `"Hans /Müller/"`.
String buildGedcomName(String given, String surname) {
  final g = given.trim();
  final s = surname.trim();
  return '$g /$s/'.trim();
}

/// Splits a raw GEDCOM `NAME` value like `"Hans /Müller/"` into given and
/// surname parts. Falls back to putting everything in [given] if there's no
/// slash-wrapped surname (e.g. a name still missing one).
(String given, String surname) splitGedcomName(String rawName) {
  final match = RegExp(r'^([^/]*)/([^/]*)/?').firstMatch(rawName);
  if (match == null) return (rawName.trim(), '');
  return (match.group(1)!.trim(), match.group(2)!.trim());
}
