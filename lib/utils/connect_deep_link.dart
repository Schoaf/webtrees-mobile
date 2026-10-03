/// The parameters carried by a "Verbinden" (Connect) deep link — see
/// [connectParamsFromLink].
class ConnectParams {
  const ConnectParams({required this.serverUrl, required this.code, this.tree, this.userName});

  /// The webtrees server this device should now talk to - not necessarily
  /// the one already configured; any webtrees site running api4webtrees
  /// can hand out a link like this, pointing at itself.
  final String serverUrl;

  /// A 48-hex-character, single-use pairing code - see
  /// `WebtreesClient.pair`. Already spent the moment it's redeemed
  /// (successfully or not), and expires a few minutes after the server
  /// issued it.
  final String code;

  /// The tree the "App" page was opened from on the website - a sensible
  /// first pick if the account can see more than one, but never the only
  /// source of truth: `Info`'s own `trees[]` is.
  final String? tree;

  /// The webtrees username being paired - display-only (e.g. "connecting
  /// as alice…"), the server already knows who `code` belongs to.
  final String? userName;
}

/// Pulls the four params out of a "Verbinden" deep link
/// (`webtreesmobile://connect?url=…&code=…&tree=…&user=…`), if it is one -
/// see AppPages::deepLink() in the api4webtrees module. Always a plain
/// query-string URI by the time this app receives it (never the
/// URL-fragment form the intermediate HTTPS QR-landing page uses - that
/// page's own JavaScript already resolved the fragment into a real
/// `webtreesmobile://` link before handing off to the OS).
ConnectParams? connectParamsFromLink(Uri uri) {
  if (uri.scheme != 'webtreesmobile' || uri.host != 'connect') return null;

  final url = uri.queryParameters['url'];
  final code = uri.queryParameters['code'];
  if (url == null || url.isEmpty || code == null || code.isEmpty) return null;

  return ConnectParams(
    serverUrl: url,
    code: code,
    tree: uri.queryParameters['tree'],
    userName: uri.queryParameters['user'],
  );
}
