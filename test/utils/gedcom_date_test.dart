import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/gedcom_date.dart';

void main() {
  group('gedcomDateToDateTime', () {
    test('parses a well-formed GEDCOM date', () {
      final date = gedcomDateToDateTime('3 MAY 1980');
      expect(date, DateTime(1980, 5, 3));
    });

    test('is whitespace-tolerant', () {
      final date = gedcomDateToDateTime('  25 DEC 1999  ');
      expect(date, DateTime(1999, 12, 25));
    });

    test('returns null for a qualifier it cannot represent (e.g. ABT)', () {
      expect(gedcomDateToDateTime('ABT 1980'), isNull);
    });

    test('returns null for an out-of-range day (e.g. 31 FEB)', () {
      expect(gedcomDateToDateTime('31 FEB 1980'), isNull);
    });

    test('returns null for garbage input', () {
      expect(gedcomDateToDateTime('not a date'), isNull);
    });
  });

  group('dateTimeToGedcom', () {
    test('formats a DateTime back into GEDCOM syntax', () {
      expect(dateTimeToGedcom(DateTime(1980, 5, 3)), '3 MAY 1980');
    });
  });

  group('gedcomDateToDateTime / dateTimeToGedcom round-trip', () {
    test('round-trips for every month', () {
      for (final entry in gedcomMonths.entries) {
        final gedcom = '15 ${entry.key} 2000';
        final date = gedcomDateToDateTime(gedcom);
        expect(date, isNotNull, reason: gedcom);
        expect(dateTimeToGedcom(date!), gedcom);
      }
    });
  });

  group('formatGermanDate', () {
    test('formats a date as German long-form text', () {
      expect(formatGermanDate(DateTime(1983, 5, 25)), '25. Mai 1983');
    });

    test('uses the correct German month name for December', () {
      expect(formatGermanDate(DateTime(2000, 12, 1)), '1. Dezember 2000');
    });
  });

  group('germanDdMmYyyyToDateTime', () {
    test('parses a dd.mm.yyyy string', () {
      expect(germanDdMmYyyyToDateTime('25.05.1983'), DateTime(1983, 5, 25));
    });

    test('accepts single-digit day/month', () {
      expect(germanDdMmYyyyToDateTime('3.5.1980'), DateTime(1980, 5, 3));
    });

    test('returns null for an invalid calendar date', () {
      expect(germanDdMmYyyyToDateTime('31.02.1980'), isNull);
    });

    test('returns null for malformed text', () {
      expect(germanDdMmYyyyToDateTime('not a date'), isNull);
    });
  });

  group('dateTimeToGermanDdMmYyyy', () {
    test('formats and zero-pads day/month', () {
      expect(dateTimeToGermanDdMmYyyy(DateTime(1980, 5, 3)), '03.05.1980');
    });

    test('round-trips with germanDdMmYyyyToDateTime', () {
      final date = DateTime(1999, 12, 25);
      expect(germanDdMmYyyyToDateTime(dateTimeToGermanDdMmYyyy(date)), date);
    });
  });
}
