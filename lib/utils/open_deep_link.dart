/// This app's id in api4webtrees' list of apps (`src/Apps.php`) - the
/// "App" page asks to open links in it with `?open-in=` this.
const openLinksAppId = 'webtrees-mobile';

/// A webtrees page to show in the app instead of the browser - from
/// `webtreesmobile://open?url=<page URL>`, which the api4webtrees module
/// offers when a page is opened from outside ("Open links in the app").
class OpenLink {
  const OpenLink({required this.pageUrl, required this.tree, required this.xref, required this.isChart});

  /// The full webtrees address of the page.
  final Uri pageUrl;
  final String tree;
  final String xref;

  /// A chart (pedigree, descendants ...): shown as the app's tree, else the
  /// person's page.
  final bool isChart;

  /// Whether the page is on the server at [serverUrl] (subfolder included).
  bool isOnServer(String serverUrl) {
    final server = Uri.parse(serverUrl);
    String path(String p) => p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    return pageUrl.scheme == server.scheme &&
        pageUrl.host.toLowerCase() == server.host.toLowerCase() &&
        pageUrl.port == server.port &&
        '${path(pageUrl.path)}/'.startsWith('${path(server.path)}/');
  }
}

/// Reads an "open" link, if it is one: a person page
/// (`/tree/{tree}/individual/{xref}`) or a chart of a person
/// (`/tree/{tree}/<chart>/{xref}`, or the xref as `?xref=`) - with or
/// without pretty URLs (`index.php?route=...`).
OpenLink? openLinkFrom(Uri uri) {
  if (uri.scheme != 'webtreesmobile' || uri.host != 'open') return null;
  final page = Uri.tryParse(uri.queryParameters['url'] ?? '');
  if (page == null || !page.hasScheme) return null;

  final route = page.queryParameters['route'] ?? page.path;
  final person = RegExp(r'/tree/([^/]+)/individual/([^/]+)').firstMatch(route);
  if (person != null) {
    return OpenLink(
      pageUrl: page,
      tree: Uri.decodeComponent(person.group(1)!),
      xref: person.group(2)!,
      isChart: false,
    );
  }

  final chart = RegExp(r'/tree/([^/]+)/[^/]+(?:/([^/]+))?$').firstMatch(route);
  final xref = page.queryParameters['xref'] ?? chart?.group(2);
  if (chart == null || xref == null || xref.isEmpty) return null;
  return OpenLink(pageUrl: page, tree: Uri.decodeComponent(chart.group(1)!), xref: xref, isChart: true);
}
