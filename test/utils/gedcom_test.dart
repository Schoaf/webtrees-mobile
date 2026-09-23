import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/gedcom.dart';

void main() {
  group('stripNameSlashes', () {
    test('removes the surname slashes and trims', () {
      expect(stripNameSlashes('Hans /Müller/'), 'Hans Müller');
    });

    test('leaves a name with no slashes unchanged (besides trimming)', () {
      expect(stripNameSlashes('  Hans Müller  '), 'Hans Müller');
    });
  });

  group('buildGedcomName', () {
    test('wraps the surname in slashes', () {
      expect(buildGedcomName('Hans', 'Müller'), 'Hans /Müller/');
    });

    test('trims whitespace from both parts', () {
      expect(buildGedcomName(' Hans ', ' Müller '), 'Hans /Müller/');
    });

    test('an empty given name still produces a valid GEDCOM value', () {
      expect(buildGedcomName('', 'Müller'), '/Müller/');
    });
  });

  group('splitGedcomName', () {
    test('splits a well-formed GEDCOM name into given and surname', () {
      final (given, surname) = splitGedcomName('Hans /Müller/');
      expect(given, 'Hans');
      expect(surname, 'Müller');
    });

    test('falls back to putting everything in given when there is no slash-wrapped surname', () {
      final (given, surname) = splitGedcomName('Hans Müller');
      expect(given, 'Hans Müller');
      expect(surname, '');
    });

    test('handles a surname-only name (empty given)', () {
      final (given, surname) = splitGedcomName('/Müller/');
      expect(given, '');
      expect(surname, 'Müller');
    });
  });
}
