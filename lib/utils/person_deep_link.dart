/// Pulls a person's xref out of a shared webtrees link, if it is one.
///
/// Matches the plain (non-"pretty") webtrees URL this app itself shares —
/// `.../index.php?route=/tree/{tree}/individual/{xref}` — and, for
/// robustness, the pretty-URL form `/tree/{tree}/individual/{xref}` too, in
/// case a server is ever switched to rewritten URLs.
String? personXrefFromLink(Uri uri) {
  final route = uri.queryParameters['route'] ?? uri.path;
  final match = RegExp(r'/tree/[^/]+/individual/([^/]+)').firstMatch(route);
  return match?.group(1);
}
