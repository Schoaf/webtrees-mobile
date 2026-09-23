import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/share_review_deep_link.dart';

void main() {
  group('shareReviewIdFromLink', () {
    test('extracts the request id from a RequestReview notification link', () {
      final uri = Uri.parse(
        'https://tree.example.com/index.php?route=/module/_webtrees-contribution-request_/RequestReview/Famtree&id=42',
      );
      expect(shareReviewIdFromLink(uri), 42);
    });

    test('returns null when the route does not match RequestReview', () {
      final uri = Uri.parse('https://tree.example.com/index.php?route=/tree/Famtree/individual/I1');
      expect(shareReviewIdFromLink(uri), isNull);
    });

    test('returns null when id is missing', () {
      final uri = Uri.parse(
        'https://tree.example.com/index.php?route=/module/_webtrees-contribution-request_/RequestReview/Famtree',
      );
      expect(shareReviewIdFromLink(uri), isNull);
    });

    test('returns null when id is not a valid integer', () {
      final uri = Uri.parse(
        'https://tree.example.com/index.php?route=/module/_webtrees-contribution-request_/RequestReview/Famtree&id=abc',
      );
      expect(shareReviewIdFromLink(uri), isNull);
    });
  });
}
