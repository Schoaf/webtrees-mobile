import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/person_deep_link.dart';

void main() {
  group('personXrefFromLink', () {
    test('extracts the xref from the plain (non-pretty) route query parameter', () {
      final uri = Uri.parse('https://tree.example.com/index.php?route=/tree/Famtree/individual/I5');
      expect(personXrefFromLink(uri), 'I5');
    });

    test('extracts the xref from a pretty-URL path form', () {
      final uri = Uri.parse('https://tree.example.com/tree/Famtree/individual/I5');
      expect(personXrefFromLink(uri), 'I5');
    });

    test('returns null for a link that is not a person link', () {
      final uri = Uri.parse('https://tree.example.com/index.php?route=/tree/Famtree/individuals');
      expect(personXrefFromLink(uri), isNull);
    });

    test('returns null for an unrelated URL', () {
      final uri = Uri.parse('https://example.com/');
      expect(personXrefFromLink(uri), isNull);
    });
  });
}
