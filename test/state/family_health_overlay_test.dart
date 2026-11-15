import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/state/family_health_overlay.dart';

void main() {
  final overlay = FamilyHealthOverlay.fromJson(
    {
      'illnesses': [
        {'xref': 'I2', 'category': 'cancer'},
        {'xref': 'I2', 'category': 'cardiovascular'},
        {'xref': 'I9', 'category': 'cancer'},
        {'xref': 'I5'},
      ],
    },
    {
      'categories': [
        {'id': 'cardiovascular', 'name': 'Herz und Kreislauf'},
        {'id': 'cancer', 'name': 'Krebs'},
        {'id': 'lung', 'name': 'Lunge'},
        {'id': 'other', 'name': 'Sonstiges'},
      ],
    },
  );

  test('the categories of each individual, labelled in the module\'s order', () {
    expect(overlay.labelOf('I2'), 'Herz und Kreislauf · Krebs');
    // Without a category: "other", like the module.
    expect(overlay.labelOf('I5'), 'Sonstiges');
    expect(overlay.usedCategories, ['cardiovascular', 'cancer', 'other']);
  });

  test('without an illness: faded, no label', () {
    expect(overlay.isFaded('I1'), isTrue);
    expect(overlay.labelOf('I1'), isNull);
  });

  test('a picked category fades everyone without it and shows only it', () {
    final cancer = overlay.withCategory('cancer');
    expect(cancer.isFaded('I5'), isTrue);
    expect(cancer.labelOf('I2'), 'Krebs');
    expect(cancer.labelOf('I9'), 'Krebs');
  });
}
