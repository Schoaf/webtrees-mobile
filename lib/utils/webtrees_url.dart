/// A webtrees route (e.g. `/tree/Famtree/individual/I1`) as a URL on the site
/// at [baseUrl] (no trailing slash needed). Two forms, as webtrees itself:
/// - default: `{base}/index.php?route={path}{route}`, `{path}` being the
///   base URL's own path (`/webtrees` for `https://example.org/webtrees`)
/// - "pretty URLs" switched on (Info `rewriteUrls`): `{base}{route}` - such
///   servers redirect the index.php form, and some redirect it wrongly
///   (dropping a subfolder), so the app must use this form there.
Uri webtreesUrl(
  String baseUrl,
  String route, {
  required bool usePrettyUrls,
  Map<String, String> query = const {},
}) {
  final base = Uri.parse(baseUrl);
  final basePath = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
  if (usePrettyUrls) {
    return base.replace(path: '$basePath$route', queryParameters: query.isEmpty ? null : query);
  }
  // webtrees' router matches the whole path, subfolder included:
  // `/webtrees/index.php?route=/webtrees/ping` - `route=/ping` is a 404 there.
  return base.replace(path: '$basePath/index.php', queryParameters: {'route': '$basePath$route', ...query});
}
