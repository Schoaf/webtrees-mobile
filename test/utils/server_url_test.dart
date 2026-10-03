import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/server_url.dart';

void main() {
  test('adds https when no scheme is typed', () {
    expect(normalizeServerUrl(' stammbaum.example.org '), 'https://stammbaum.example.org');
  });

  test('keeps an explicit http and port (e.g. a NAS on the local network)', () {
    expect(normalizeServerUrl('http://192.168.1.5:8095/'), 'http://192.168.1.5:8095');
  });

  test('keeps a sub-path, drops index.php, query and trailing slashes', () {
    expect(
      normalizeServerUrl('https://example.org/webtrees/index.php?route=/tree/x'),
      'https://example.org/webtrees',
    );
    expect(normalizeServerUrl('example.org/webtrees//'), 'https://example.org/webtrees');
  });

  test('rejects empty input and non-web schemes', () {
    expect(normalizeServerUrl('   '), isNull);
    expect(normalizeServerUrl('ftp://example.org'), isNull);
    expect(normalizeServerUrl('https://'), isNull);
  });
}
