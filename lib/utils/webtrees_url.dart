/// A webtrees route (e.g. `/tree/Famtree/individual/I1`) as a URL on the site
/// at [baseUrl] (no trailing slash needed). Two forms, as webtrees itself:
/// - default: `{base}/index.php?route={route}`
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
  return base.replace(path: '$basePath/index.php', queryParameters: {'route': route, ...query});
}
