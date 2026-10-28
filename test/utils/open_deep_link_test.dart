import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/open_deep_link.dart';

void main() {
  Uri open(String page) => Uri.parse('webtreesmobile://open?url=${Uri.encodeComponent(page)}');

  test('a person page, without and with pretty URLs', () {
    final plain = openLinkFrom(open('https://example.org/index.php?route=%2Ftree%2FFamtree%2Findividual%2FI1%2FAnna-Muster'))!;
    expect((plain.tree, plain.xref, plain.isChart), ('Famtree', 'I1', false));

    final pretty = openLinkFrom(open('https://example.org/webtrees/tree/Famtree/individual/I42'))!;
    expect((pretty.tree, pretty.xref, pretty.isChart), ('Famtree', 'I42', false));
  });

  test('a chart of a person', () {
    final pedigree = openLinkFrom(open('https://example.org/index.php?route=%2Ftree%2FFamtree%2Fpedigree-right-4%2FI7'))!;
    expect((pedigree.tree, pedigree.xref, pedigree.isChart), ('Famtree', 'I7', true));
  });

  test('only links of the connected server, subfolder included', () {
    final link = openLinkFrom(open('https://example.org/webtrees/index.php?route=%2Fwebtrees%2Ftree%2FT%2Findividual%2FI1'))!;
    expect(link.isOnServer('https://example.org/webtrees'), isTrue);
    expect(link.isOnServer('https://example.org/webtrees/'), isTrue);
    expect(link.isOnServer('https://example.org/other'), isFalse);
    expect(link.isOnServer('https://other.org/webtrees'), isFalse);
  });

  test('other links are none', () {
    expect(openLinkFrom(Uri.parse('webtreesmobile://connect?url=x&code=y')), isNull);
    expect(openLinkFrom(Uri.parse('webtreesmobile://open-in?result=on')), isNull);
    expect(openLinkFrom(open('https://example.org/index.php?route=%2Fmy-account')), isNull);
  });
}
