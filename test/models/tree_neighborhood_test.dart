import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/tree_neighborhood.dart';

Map<String, dynamic> _loadFixture(String name) {
  return jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('TreeNeighborhood.fromJson (real dev-server fixture)', () {
    late TreeNeighborhood neighborhood;

    setUp(() {
      neighborhood = TreeNeighborhood.fromJson(_loadFixture('individual_i3.json'));
    });

    test('parses the current person, deriving first name from sortName', () {
      expect(neighborhood.person.xref, 'I3');
      expect(neighborhood.person.firstName, 'Josef');
      expect(neighborhood.person.birthYear, 1955);
      expect(neighborhood.person.hasParents, isTrue);
      expect(neighborhood.person.childrenCount, 2);
      expect(neighborhood.person.partnersCount, 1);
    });

    test('parses father and mother from the primary parent family', () {
      expect(neighborhood.father?.xref, 'I1');
      expect(neighborhood.father?.firstName, 'Anton');
      expect(neighborhood.mother?.xref, 'I2');
    });

    test('has no siblings (only child of I1/I2 in the fixture)', () {
      expect(neighborhood.siblings, isEmpty);
    });

    test('parses the one partner family with its marital status and children', () {
      expect(neighborhood.partners, hasLength(1));
      final family = neighborhood.partners.single;
      expect(family.partner?.xref, 'I4');
      expect(family.maritalStatus, MaritalStatus.married);
      expect(family.isOngoing, isTrue);
      expect(family.children.map((c) => c.xref), ['I5', 'I6']);
    });

    test('defaultPartner is the only (ongoing) partner', () {
      expect(neighborhood.defaultPartner?.partner?.xref, 'I4');
    });

    test('extraChildrenByParent is zero (no other partners for either parent)', () {
      expect(neighborhood.extraChildrenFather, 0);
      expect(neighborhood.extraChildrenMother, 0);
    });
  });

  group('TreeNeighborhood.fromJson (synthetic edge cases)', () {
    test('an unknown partner (spouse: null) parses as a null TreeNode.partner', () {
      final json = {
        'person': {'xref': 'I1', 'name': 'Maria Muster', 'sortName': 'Muster,Maria'},
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'siblings': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
        'spouseFamilies': [
          {
            'xref': 'F1',
            'spouse': null,
            'maritalStatus': 'unknown',
            'marriage': null,
            'children': [
              {'xref': 'I2', 'name': 'Lea Muster', 'sortName': 'Muster,Lea'},
            ],
          },
        ],
      };

      final neighborhood = TreeNeighborhood.fromJson(json);
      final family = neighborhood.partners.single;

      expect(family.partner, isNull);
      expect(family.maritalStatus, MaritalStatus.unknown);
      expect(family.isOngoing, isFalse);
      expect(family.children.single.firstName, 'Lea');
    });

    test('siblings are sorted by birth year then first name', () {
      final json = {
        'person': {'xref': 'I1', 'name': 'Root', 'sortName': 'Root,Root'},
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
        'siblings': [
          {
            'xref': 'I2',
            'name': 'Bernd Muster',
            'sortName': 'Muster,Bernd',
            'birth': {
              'date': {'year': 1980},
            },
          },
          {
            'xref': 'I3',
            'name': 'Anna Muster',
            'sortName': 'Muster,Anna',
            'birth': {
              'date': {'year': 1978},
            },
          },
          {
            'xref': 'I4',
            'name': 'Anna Zweit',
            'sortName': 'Zweit,Anna',
            'birth': {
              'date': {'year': 1978},
            },
          },
        ],
      };

      final neighborhood = TreeNeighborhood.fromJson(json);

      expect(neighborhood.siblings.map((s) => s.xref), ['I3', 'I4', 'I2']);
    });

    test('picks the ongoing partner as default over an ended earlier one', () {
      final json = {
        'person': {'xref': 'I1', 'name': 'Root', 'sortName': 'Root,Root'},
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'siblings': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
        'spouseFamilies': [
          {
            'xref': 'F1',
            'spouse': {'xref': 'I2', 'name': 'Ex Partner', 'sortName': 'Partner,Ex'},
            'maritalStatus': 'divorced',
            'marriage': {
              'date': {'year': 2000},
            },
            'children': <dynamic>[],
          },
          {
            'xref': 'F2',
            'spouse': {'xref': 'I3', 'name': 'Current Partner', 'sortName': 'Partner,Current'},
            'maritalStatus': 'married',
            'marriage': {
              'date': {'year': 2015},
            },
            'children': <dynamic>[],
          },
        ],
      };

      final neighborhood = TreeNeighborhood.fromJson(json);

      expect(neighborhood.defaultPartner?.partner?.xref, 'I3');
    });
  });
}
