import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/server_error.dart';

void main() {
  group('describeServerError', () {
    test('extracts the message from a webtrees alert-danger HTML page', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          data: '<html><body><div class="alert-danger p-3">'
              '<button type="button">x</button>Something went wrong on the server.'
              '</div></body></html>',
        ),
      );

      expect(describeServerError(error), 'Something went wrong on the server.');
    });

    test('strips nested HTML tags and collapses blank lines from the extracted message', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          data: '<div class="alert-danger">'
              '<p>Line one</p>\n\n\n<p>Line two</p>'
              '</div>',
        ),
      );

      expect(describeServerError(error), 'Line one\nLine two');
    });

    test('falls back to the exception string when there is no alert-danger div', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(requestOptions: RequestOptions(path: '/'), data: '<html>not an error page</html>'),
      );

      expect(describeServerError(error), error.toString());
    });

    test('falls back to the exception string when the response data is not a String', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(requestOptions: RequestOptions(path: '/'), data: {'error': 'boom'}),
      );

      expect(describeServerError(error), error.toString());
    });

    test('falls back to the exception string for a non-DioException error', () {
      final error = Exception('plain failure');
      expect(describeServerError(error), error.toString());
    });
  });
}
