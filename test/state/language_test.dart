import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/state/language.dart';

void main() {
  test('a German device gets German', () {
    expect(resolveAppLocale(const [Locale('de', 'AT')]), const Locale('de'));
  });

  test('every other device language falls back to English', () {
    expect(resolveAppLocale(const [Locale('nl', 'NL')]), const Locale('en'));
    expect(resolveAppLocale(const [Locale('en', 'US')]), const Locale('en'));
    expect(resolveAppLocale(null), const Locale('en'));
  });
}
