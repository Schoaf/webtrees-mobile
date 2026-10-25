import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The store workflow sends the App Store release notes to Google Play too
/// (tool/prepare_store_uploads.py) - Google refuses more than 500 characters.
void main() {
  for (final file in Directory('fastlane/metadata/ios').listSync().whereType<Directory>()) {
    final notes = File('${file.path}/release_notes.txt');
    if (!notes.existsSync()) continue;
    test('${notes.path} fits Google Play (at most 500 characters)', () {
      expect(notes.readAsStringSync().trimRight().runes.length, lessThanOrEqualTo(500));
    });
  }
}
