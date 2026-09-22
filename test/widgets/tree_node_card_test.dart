import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/tree_neighborhood.dart';
import 'package:webtrees_mobile/widgets/tree_node_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows the first name and birth year', (tester) async {
    await tester.pumpWidget(_wrap(const TreeNodeCard(firstName: 'Anna', sex: 'F', isDead: false, birthYear: 1958)));

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('1958'), findsOneWidget);
  });

  testWidgets('shows the detail block only when detail is given', (tester) async {
    await tester.pumpWidget(_wrap(const TreeNodeCard(firstName: 'Anna', sex: 'F', isDead: false, birthYear: 1958)));
    expect(find.text('Graz'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        const TreeNodeCard(
          firstName: 'Maria',
          sex: 'F',
          isDead: false,
          birthYear: 1985,
          detail: TreePersonDetail(birthDateText: '14. März 1985', birthPlace: 'Graz', occupation: 'Lehrerin'),
        ),
      ),
    );

    expect(find.text('14. März 1985'), findsOneWidget);
    expect(find.text('Graz'), findsOneWidget);
    expect(find.text('Lehrerin'), findsOneWidget);
  });

  testWidgets('shows the sibling partner-name row only when set', (tester) async {
    await tester.pumpWidget(
      _wrap(const TreeNodeCard(firstName: 'Thomas', sex: 'M', isDead: false, birthYear: 1982, partnerNameRow: 'Julia')),
    );

    expect(find.text('Julia'), findsOneWidget);
  });

  testWidgets('shows the children-count badge with the right number', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TreeNodeCard(
          firstName: 'Lukas',
          sex: 'M',
          isDead: false,
          birthYear: 2012,
          showChildrenIcon: true,
          childrenCount: 3,
        ),
      ),
    );

    expect(find.text('+3'), findsOneWidget);
  });

  testWidgets('calls onTap when the card is tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        TreeNodeCard(firstName: 'Anna', sex: 'F', isDead: false, birthYear: 1958, onTap: () => tapped = true),
      ),
    );

    await tester.tap(find.text('Anna'));
    expect(tapped, isTrue);
  });

  testWidgets('calls onInfoTap, not onTap, when the info button is tapped', (tester) async {
    var cardTapped = false;
    var infoTapped = false;
    await tester.pumpWidget(
      _wrap(
        TreeNodeCard(
          firstName: 'Maria',
          sex: 'F',
          isDead: false,
          birthYear: 1985,
          showInfoButton: true,
          onTap: () => cardTapped = true,
          onInfoTap: () => infoTapped = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.info_outline));
    expect(infoTapped, isTrue);
    expect(cardTapped, isFalse);
  });

  testWidgets('UnknownPersonCard shows the placeholder text and has no tap handler', (tester) async {
    await tester.pumpWidget(_wrap(const UnknownPersonCard()));

    expect(find.text('Unbekannt'), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
  });
}
