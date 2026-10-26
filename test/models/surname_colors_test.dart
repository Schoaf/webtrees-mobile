import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/surname_colors.dart';

void main() {
  test('the most frequent surnames get a colour, the others none', () {
    final colors = SurnameColors().assign([
      for (var i = 0; i < surnamePalette.length; i++) ...['Name$i', 'Name$i'],
      'Rare',
      '',
    ]);

    expect(colors.length, surnamePalette.length);
    expect(colors.containsKey('Rare'), isFalse);
    expect(colors.containsKey(''), isFalse);
    expect(colors.values.toSet().length, surnamePalette.length, reason: 'no colour twice');
  });

  test('a surname keeps its colour when the people in view change', () {
    final surnameColors = SurnameColors();
    final first = surnameColors.assign(['Muster', 'Muster', 'Huber']);
    final second = surnameColors.assign(['Huber', 'Huber', 'Wagner', 'Wagner', 'Wagner']);

    expect(second['Huber'], first['Huber']);
    expect(second['Wagner'], isNot(first['Huber']));
  });
}
