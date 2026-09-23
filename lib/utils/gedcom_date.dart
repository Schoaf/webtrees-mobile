/// Conversion between GEDCOM's plain "12 MAR 1930" date syntax and [DateTime],
/// for the date pickers in edit mode. Deliberately narrow, same as the
/// server-side counterpart (webtrees-contribution-request's GedcomSnapshot): GEDCOM date
/// qualifiers (ABT, ranges, ...) aren't picker-representable and are left as
/// free text rather than discarded.
library;

const Map<String, int> gedcomMonths = {
  'JAN': 1,
  'FEB': 2,
  'MAR': 3,
  'APR': 4,
  'MAY': 5,
  'JUN': 6,
  'JUL': 7,
  'AUG': 8,
  'SEP': 9,
  'OCT': 10,
  'NOV': 11,
  'DEC': 12,
};

const List<String> _germanMonthNames = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

DateTime? gedcomDateToDateTime(String gedcom) {
  final pattern = RegExp(
    r'^(\d{1,2}) (' '${gedcomMonths.keys.join('|')}' r') (\d{3,4})$',
  );
  final match = pattern.firstMatch(gedcom.trim());
  if (match == null) return null;

  final day = int.parse(match.group(1)!);
  final month = gedcomMonths[match.group(2)]!;
  final year = int.parse(match.group(3)!);

  try {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  } on ArgumentError {
    return null;
  }
}

String dateTimeToGedcom(DateTime date) {
  final month = gedcomMonths.entries
      .firstWhere((entry) => entry.value == date.month)
      .key;
  return '${date.day} $month ${date.year}';
}

/// German long-form display text for a parsed date, e.g. "25. Mai 1983".
String formatGermanDate(DateTime date) {
  return '${date.day}. ${_germanMonthNames[date.month - 1]} ${date.year}';
}

DateTime? germanDdMmYyyyToDateTime(String text) {
  final match = RegExp(
    r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$',
  ).firstMatch(text.trim());
  if (match == null) return null;

  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);

  try {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  } on ArgumentError {
    return null;
  }
}

String dateTimeToGermanDdMmYyyy(DateTime date) {
  final dd = date.day.toString().padLeft(2, '0');
  final mm = date.month.toString().padLeft(2, '0');
  return '$dd.$mm.${date.year}';
}
