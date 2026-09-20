import 'package:dio/dio.dart';

/// webtrees renders a fatal PHP error as a full HTML page (an
/// `alert-danger` div with the message + stack trace), not JSON — so a 500
/// from it normally only surfaces as Dio's generic "bad response" wrapper,
/// hiding the one thing that actually explains what broke. Pulls the real
/// message out when there is one.
String describeServerError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is String) {
      final match = RegExp(
        r'alert-danger[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(data);
      if (match != null) {
        final text = match
            .group(1)!
            .replaceAll(RegExp(r'<button[^>]*>.*?</button>', dotAll: true), '')
            .replaceAll(RegExp(r'<[^>]+>'), '\n')
            .replaceAll(RegExp(r'\n{2,}'), '\n')
            .trim();
        if (text.isNotEmpty) return text;
      }
    }
  }
  return error.toString();
}
