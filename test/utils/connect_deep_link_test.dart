import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/connect_deep_link.dart';

void main() {
  group('connectParamsFromLink', () {
    test('parses url, code, tree and user from a well-formed connect link', () {
      final uri = Uri.parse(
        'webtreesmobile://connect?url=https%3A%2F%2Ftree.example.com%2F&code=abc123&tree=Famtree&user=alice',
      );
      final params = connectParamsFromLink(uri);

      expect(params, isNotNull);
      expect(params!.serverUrl, 'https://tree.example.com/');
      expect(params.code, 'abc123');
      expect(params.tree, 'Famtree');
      expect(params.userName, 'alice');
    });

    test('tree and user are optional - a link with just url and code still parses', () {
      final uri = Uri.parse('webtreesmobile://connect?url=https%3A%2F%2Ftree.example.com%2F&code=abc123');
      final params = connectParamsFromLink(uri);

      expect(params, isNotNull);
      expect(params!.serverUrl, 'https://tree.example.com/');
      expect(params.code, 'abc123');
      expect(params.tree, isNull);
      expect(params.userName, isNull);
    });

    test('a different scheme is not a connect link', () {
      final uri = Uri.parse('https://stammbaum.familiescharf.at/tree/Famtree/individual/I1');
      expect(connectParamsFromLink(uri), isNull);
    });

    test('the right scheme but a different host is not a connect link', () {
      final uri = Uri.parse('webtreesmobile://something-else?url=https%3A%2F%2Ftree.example.com%2F&code=abc123');
      expect(connectParamsFromLink(uri), isNull);
    });

    test('missing url returns null', () {
      final uri = Uri.parse('webtreesmobile://connect?code=abc123');
      expect(connectParamsFromLink(uri), isNull);
    });

    test('missing code returns null', () {
      final uri = Uri.parse('webtreesmobile://connect?url=https%3A%2F%2Ftree.example.com%2F');
      expect(connectParamsFromLink(uri), isNull);
    });

    test('an empty url or code is treated as missing', () {
      final uri = Uri.parse('webtreesmobile://connect?url=&code=');
      expect(connectParamsFromLink(uri), isNull);
    });
  });
}
