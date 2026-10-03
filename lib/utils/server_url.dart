/// Turns whatever someone types as a webtrees address into the base URL
/// the client expects (scheme + host + optional sub-path, no trailing
/// slash, no `index.php`) - or null if it can't be one.
///
/// "stammbaum.example.org" -> "https://stammbaum.example.org"
/// "https://example.org/webtrees/index.php?route=..." -> "https://example.org/webtrees"
///
/// https is assumed when no scheme is given; http only when typed
/// explicitly (e.g. a NAS on the local network).
String? normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }

  var path = uri.path;
  if (path.endsWith('index.php')) path = path.substring(0, path.length - 'index.php'.length);
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$path';
}
