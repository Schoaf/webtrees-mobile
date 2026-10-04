/// Plain text from the little HTML webtrees puts in its texts (welcome
/// text, registration terms): line breaks for <br>/<p>, bullets for <li>,
/// all other tags dropped, common entities decoded.
String htmlToPlainText(String html) {
  final text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
        final code = int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16);
        return code == null ? m[0]! : String.fromCharCode(code);
      })
      .replaceAllMapped(
        RegExp(r'&([a-zA-Z]+);'),
        (m) => _entities[m[1]!] ?? m[0]!,
      );
  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

// The named entities webtrees texts realistically contain (German/French
// letters a custom welcome text might be written with).
const _entities = {
  'nbsp': ' ',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'amp': '&',
  'auml': 'ä',
  'ouml': 'ö',
  'uuml': 'ü',
  'Auml': 'Ä',
  'Ouml': 'Ö',
  'Uuml': 'Ü',
  'szlig': 'ß',
  'eacute': 'é',
  'egrave': 'è',
  'agrave': 'à',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
};
