import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/surname_grouping.dart';

void main() {
  String key(String surname, SurnameGrouping grouping) => surnameGroupKey(surname, grouping);

  test('exact keeps every spelling apart', () {
    expect(key('Hummer', SurnameGrouping.exact), isNot(key('Humer', SurnameGrouping.exact)));
  });

  test('similar spelling joins slight differences, not other names', () {
    const spelling = SurnameGrouping.spelling;
    expect(key('Hummer', spelling), key('Humer', spelling));
    expect({key('Schmidt', spelling), key('Schmitt', spelling), key('Schmid', spelling)}, hasLength(1));
    expect({key('Mayer', spelling), key('Meier', spelling), key('Maier', spelling), key('Meyer', spelling)}, hasLength(1));
    expect(key('Müller', spelling), key('Mueller', spelling));
    expect(key('Hummer', spelling), isNot(key('Mohr', spelling)));
    expect(key('Müller', spelling), isNot(key('Miller', spelling)));
  });

  test('same sound is the Kölner Phonetik', () {
    const sound = SurnameGrouping.sound;
    expect(key('Müller-Lüdenscheidt', sound), '65752682');
    expect(key('Wikipedia', sound), '3412');
    expect(key('Breschnew', sound), '17863');
    expect(key('Hummer', sound), key('Humer', sound));
    expect(key('Meier', sound), key('Mohr', sound));
  });

  test('a group shows its most frequent spelling', () {
    final labels = surnameGroupLabels(
      ['Humer', 'Hummer', 'Hummer', 'Mohr'],
      (s) => surnameGroupKey(s, SurnameGrouping.spelling),
    );
    expect(labels.values, unorderedEquals(['Hummer', 'Mohr']));
  });
}
