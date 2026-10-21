import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/webtrees_url.dart';

void main() {
  test('index.php form keeps a subfolder', () {
    expect(
      webtreesUrl('https://example.com/webtrees', '/tree/T/individual/I1', usePrettyUrls: false).toString(),
      'https://example.com/webtrees/index.php?route=%2Ftree%2FT%2Findividual%2FI1',
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
