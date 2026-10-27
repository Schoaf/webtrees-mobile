import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/family_lines.dart';
import 'package:webtrees_mobile/models/surname_grouping.dart';

void main() {
  FamilyLines build(Map<String, String> surnameOf, List<(String, String)> links, {SurnameGrouping? grouping}) =>
      FamilyLines.build(
        surnameOf: surnameOf,
        parentLinks: links,
        keyOf: (s) => surnameGroupKey(s, grouping ?? SurnameGrouping.exact),
      );

  test('the line goes up to the parent with the same surname', () {
    final lines = build(
      {'child': 'Muster', 'father': 'Muster', 'mother': 'Huber', 'grandfather': 'Muster', 'motherFather': 'Huber'},
      [('child', 'father'), ('child', 'mother'), ('father', 'grandfather'), ('mother', 'motherFather')],
    );
    expect(lines.lineOf['child'], lines.lineOf['grandfather']);
    expect(lines.lineOf['mother'], lines.lineOf['motherFather']);
    expect(lines.lineOf['child'], isNot(lines.lineOf['mother']));
  });

  test('the same name without a link is another family', () {
    final lines = build(
      {'child': 'Muster', 'father': 'Muster', 'partner': 'Muster'},
      [('child', 'father')],
    );
    expect(lines.lineOf['child'], 'Muster');
    expect(lines.lineOf['partner'], 'Muster#partner');
    expect(lines.labels['Muster#partner'], 'Muster');
  });

  test('a change of name breaks the line', () {
    final lines = build({'child': 'Neumann', 'father': 'Muster'}, [('child', 'father')]);
    expect(lines.lineOf['child'], isNot(lines.lineOf['father']));
  });

  test('similar spellings link up as set, the line showing the most frequent', () {
    final lines = build(
      {'child': 'Humer', 'father': 'Hummer', 'grandfather': 'Hummer'},
      [('child', 'father'), ('father', 'grandfather')],
      grouping: SurnameGrouping.spelling,
    );
    expect(lines.lineOf.values.toSet(), hasLength(1));
    expect(lines.labels.values, ['Hummer']);
  });

  test('no surname, no line', () {
    final lines = build({'child': '', 'father': ''}, [('child', 'father')]);
    expect(lines.lines, isEmpty);
  });
}
