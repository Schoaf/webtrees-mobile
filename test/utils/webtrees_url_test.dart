import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/webtrees_url.dart';

void main() {
  test('index.php form keeps a subfolder, in the path and in the route', () {
    expect(
      webtreesUrl('https://example.com/webtrees', '/tree/T/individual/I1', usePrettyUrls: false).toString(),
      'https://example.com/webtrees/index.php?route=%2Fwebtrees%2Ftree%2FT%2Findividual%2FI1',
    );
  });

  test('index.php form in the web root has the plain route', () {
    expect(
      webtreesUrl('https://example.com', '/ping', usePrettyUrls: false).toString(),
      'https://example.com/index.php?route=%2Fping',
    );
  });

  test('pretty form appends the route to the base path', () {
    expect(
      webtreesUrl('https://example.com/webtrees/', '/module/_api4webtrees_/Info', usePrettyUrls: true, query: {'lang': 'en'})
          .toString(),
      'https://example.com/webtrees/module/_api4webtrees_/Info?lang=en',
    );
  });
}
