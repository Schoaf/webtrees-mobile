import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/state/language.dart';

void main() {
  test('a German device gets German', () {
    expect(resolveAppLocale(const [Locale('de', 'AT')]), const Locale('de', 'AT'));
  });

  test('a Dutch device gets Dutch', () {
    expect(resolveAppLocale(const [Locale('nl', 'BE')]), const Locale('nl', 'BE'));
  });

  test('every other device language falls back to English', () {
    expect(resolveAppLocale(const [Locale('fr', 'FR')]), const Locale('en'));
    expect(resolveAppLocale(const [Locale('en', 'US')]), const Locale('en', 'US'));
    expect(resolveAppLocale(null), const Locale('en'));
  });

  test('a British device keeps GB, so dates are day/month/year', () {
    expect(resolveAppLocale(const [Locale('en', 'GB')]), const Locale('en', 'GB'));
  });

  test('a picked language keeps the device country only if it matches', () {
    expect(resolveAppLocale(const [Locale('en', 'GB')], picked: 'en'), const Locale('en', 'GB'));
    expect(resolveAppLocale(const [Locale('de', 'AT')], picked: 'en'), const Locale('en'));
  });
}
