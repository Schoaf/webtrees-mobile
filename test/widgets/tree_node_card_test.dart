import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/tree_neighborhood.dart';
import 'package:webtrees_mobile/widgets/person_avatar.dart';
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

  testWidgets('corner badges sit a true, consistent distance from the card\'s real edges', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TreeNodeCard(
          firstName: 'Anna',
          sex: 'F',
          isDead: false,
          birthYear: 1958,
          showAncestorsIcon: true,
          showPartnerIcon: true,
          showChildrenIcon: true,
          childrenCount: 2,
        ),
      ),
    );

    // Regression test: a corner badge's Positioned offset must be relative
    // to the card's true outer edge, not the (deliberately asymmetric,
    // fromLTRB(6, 10, 6, 16)) padding around the content Column - the
    // Stack the badges (and the death banderole) live in wraps the whole
    // card, with only the Column separately padded, precisely so this
    // holds directly with no padding math needed at the call site. The
    // ancestors/descendants badges sit 1px inside the true edge, the
    // partner badge stays flush (0) - see _CornerBadge.edgeGap's call
    // sites.
    final positioneds = tester
        .widgetList<Positioned>(find.descendant(of: find.byType(TreeNodeCard), matching: find.byType(Positioned)))
        .toList();

    final topLeft = positioneds.firstWhere((p) => p.top != null && p.left != null && p.right == null && p.bottom == null);
    final topRight = positioneds.firstWhere((p) => p.top != null && p.right != null && p.left == null && p.bottom == null);
    final bottomLeft = positioneds.firstWhere((p) => p.bottom != null && p.left != null && p.right == null && p.top == null);

    // Ancestors (top-left).
    expect(topLeft.top!, closeTo(1, 0.01));
    expect(topLeft.left!, closeTo(1, 0.01));
    // Partner (top-right).
    expect(topRight.top!, closeTo(1, 0.01));
    expect(topRight.right!, closeTo(1, 0.01));
    // Descendants (bottom-left).
    expect(bottomLeft.bottom!, closeTo(1, 0.01));
    expect(bottomLeft.left!, closeTo(1, 0.01));
  });

  testWidgets('a deceased person\'s banderole spans the whole card and sits under the corner icons', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TreeNodeCard(
          firstName: 'Anna',
          sex: 'F',
          isDead: true,
          birthYear: 1958,
          showInfoButton: true,
        ),
      ),
    );

    // Spans the whole card, not just the avatar (Positioned.fill - all
    // four offsets zero), so it's unmistakable regardless of card content.
    final banderolePositioned = tester.widget<Positioned>(
      find.ancestor(of: find.byType(DeathBanderole), matching: find.byType(Positioned)).first,
    );
    expect(banderolePositioned.left, 0);
    expect(banderolePositioned.top, 0);
    expect(banderolePositioned.right, 0);
    expect(banderolePositioned.bottom, 0);

    // Painted below the info-button icon: earlier in the enclosing Stack's
    // children list paints first, i.e. further back. The info button is
    // wrapped in the (private) _CornerBadge, not a bare Positioned - Stack
    // .children holds what was literally passed in, before _CornerBadge
    // builds its own Positioned further down the tree - so this matches
    // by runtime type name instead of importing a private class.
    final stack = tester.widget<Stack>(
      find.ancestor(of: find.byType(DeathBanderole), matching: find.byType(Stack)).first,
    );
    final banderoleIndex = stack.children.indexOf(banderolePositioned);
    final infoButtonIndex = stack.children.indexWhere(
      (w) => w.runtimeType.toString() == '_CornerBadge',
    );
    expect(banderoleIndex, greaterThanOrEqualTo(0));
    expect(infoButtonIndex, greaterThan(banderoleIndex));
  });

  testWidgets(
    'a narrower card gets a proportionally thicker banderole, so its absolute reach into the '
    'card stays the same as a wider one\'s',
    (tester) async {
      // Regression test: DeathBanderole's thicknessFactor is a fraction of
      // the card's own shortest side, so at one fixed factor the ribbon
      // read visibly thinner/shallower on a plain 90px-wide sibling/child/
      // parent card than on the wider (~110px), zoomed active/partner
      // card. TreeNodeCard derives thicknessFactor from its own width
      // instead, targeting the same absolute thickness regardless of
      // which role's card it's drawn on.
      Future<double> thicknessFactorFor(double width) async {
        await tester.pumpWidget(
          _wrap(TreeNodeCard(firstName: 'Anna', sex: 'F', isDead: true, birthYear: 1958, width: width)),
        );
        return tester.widget<DeathBanderole>(find.byType(DeathBanderole)).thicknessFactor;
      }

      final narrow = await thicknessFactorFor(90);
      final wide = await thicknessFactorFor(110);

      expect(narrow, greaterThan(wide), reason: 'the narrower card needs a bigger fraction for the same absolute reach');
      expect(narrow * 90, closeTo(wide * 110, 0.01), reason: 'both must resolve to the same absolute thickness');
    },
  );

  testWidgets('UnknownPersonCard shows the placeholder text and has no tap handler', (tester) async {
    await tester.pumpWidget(_wrap(const UnknownPersonCard()));

    expect(find.text('Unbekannt'), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
  });
}
