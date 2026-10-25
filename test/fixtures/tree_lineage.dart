/// A family over five generations for the tree's generation tests (#42):
/// Elisabeth (I1) with her parents, grandparents and great-grandparents
/// above, and her children and grandchildren with Thomas below.
library;

Map<String, dynamic> personJson(String xref, String name, String sex, {int? year}) => {
  'xref': xref,
  'name': '$name Muster',
  'sortName': 'Muster,$name',
  'sex': sex,
  'isDead': false,
  if (year != null)
    'birth': {
      'date': {'year': year},
    },
};

Map<String, dynamic> individualJson() => {
  'person': {...personJson('I1', 'Elisabeth', 'F', year: 1985), 'hasParents': true, 'childrenCount': 2},
  'canEdit': false,
  'facts': <dynamic>[],
  'parentFamilies': [
    {
      'xref': 'F10',
      'facts': [
        {'tag': 'MARR'},
      ],
      'husband': {...personJson('I2', 'Anton', 'M', year: 1955), 'hasParents': true},
      'wife': {...personJson('I3', 'Maria', 'F', year: 1958), 'hasParents': true},
      'children': [personJson('I1', 'Elisabeth', 'F', year: 1985)],
    },
  ],
  'spouseFamilies': [
    {
      'xref': 'F1',
      'facts': [
        {'tag': 'MARR'},
      ],
      'husband': {'xref': 'I20', 'isDead': false},
      'wife': {'xref': 'I1', 'isDead': false},
      'spouse': personJson('I20', 'Thomas', 'M', year: 1983),
      'children': [
        {...personJson('I30', 'Mia', 'F', year: 2010), 'childrenCount': 1},
        {...personJson('I31', 'Paul', 'M', year: 2012), 'childrenCount': 0},
      ],
    },
  ],
  'stepFamilies': <dynamic>[],
  'media': <dynamic>[],
};

/// The Pedigree answer for [generations] (counting Elisabeth).
Map<String, dynamic> pedigreeJson(int generations) {
  final all = {
    1: ('I1', 'Elisabeth', 'F'),
    2: ('I2', 'Anton', 'M'),
    3: ('I3', 'Maria', 'F'),
    4: ('I4', 'Josef', 'M'),
    5: ('I5', 'Anna', 'F'),
    6: ('I6', 'Karl', 'M'),
    7: ('I7', 'Rosa', 'F'),
    8: ('I8', 'Johann', 'M'),
    9: ('I9', 'Theresia', 'F'),
  };
  return {
    'root': 'I1',
    'generations': generations,
    'ancestors': [
      for (final entry in all.entries)
        if (entry.key < 1 << generations)
          {
            'n': entry.key,
            'person': personJson(entry.value.$1, entry.value.$2, entry.value.$3),
            // Josef's parents (8, 9) are the last known ones.
            'hasParents': entry.key < 4 || entry.key == 4,
          },
    ],
  };
}

/// The Descendants answer for [generations] (counting Elisabeth).
Map<String, dynamic> descendantsJson(int generations) {
  Map<String, dynamic> node(Map<String, dynamic> person, List<Map<String, dynamic>> children, int level) => {
    'person': person,
    'families': level >= generations - 1 || children.isEmpty
        ? <dynamic>[]
        : [
            {'xref': 'F${person['xref']}', 'spouse': null, 'children': children},
          ],
  };

  final lena = node(personJson('I40', 'Lena', 'F', year: 2035), [], 2);
  final mia = node(personJson('I30', 'Mia', 'F', year: 2010), [lena], 1);
  final paul = node(personJson('I31', 'Paul', 'M', year: 2012), [], 1);
  return {
    'root': 'I1',
    'generations': generations,
    'tree': {
      'person': personJson('I1', 'Elisabeth', 'F'),
      'families': generations < 2
          ? <dynamic>[]
          : [
              {'xref': 'F1', 'spouse': personJson('I20', 'Thomas', 'M'), 'children': [mia, paul]},
            ],
    },
  };
}
