/// Pulls a webtrees-share request id out of a shared "you got a response"
/// notification-email link, if it is one.
///
/// Matches the plain (non-"pretty") webtrees URL that email link uses —
/// `.../index.php?route=/module/_webtrees-share_/RequestReview/{tree}&id={id}`
/// — same convention as [personXrefFromLink] in person_deep_link.dart.
int? shareReviewIdFromLink(Uri uri) {
  final route = uri.queryParameters['route'] ?? uri.path;

  if (!RegExp(
    r'/module/_webtrees-share_/RequestReview/[^/]+$',
  ).hasMatch(route)) {
    return null;
  }

  final id = uri.queryParameters['id'];
  return id == null ? null : int.tryParse(id);
}
