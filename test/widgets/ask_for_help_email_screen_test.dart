import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/theme/app_theme.dart';
import 'package:webtrees_mobile/widgets/ask_for_help_email_screen.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester, {required Size viewSize}) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const AskForHelpEmailScreen(
            tree: 'Famtree',
            token: 'tok',
            subject: 'Bitte um Mithilfe',
            bodyTemplate: 'Hallo,\n\n{{PERSONAL_MESSAGE}}\n\nGrüße',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on a tablet-wide viewport, content is capped well under a 13" iPad\'s portrait width', (
    tester,
  ) async {
    // 13" iPad portrait is 1024 logical px wide.
    await pumpScreen(tester, viewSize: const Size(1366, 1024));

    final listViewWidth = tester.getSize(find.byType(ListView)).width;
    expect(listViewWidth, lessThan(1024));
  });

  testWidgets('the top bar matches the content width, not the full screen', (tester) async {
    await pumpScreen(tester, viewSize: const Size(1366, 1024));

    final topBarWidth = tester.getSize(find.widgetWithText(Container, 'Per E-Mail senden')).width;
    final contentWidth = tester.getSize(find.byType(ListView)).width;
    expect(topBarWidth, contentWidth);
    expect(topBarWidth, lessThan(1024));
  });

  testWidgets('email and name fields are capped at ~310px even on a wide viewport', (tester) async {
    await pumpScreen(tester, viewSize: const Size(1366, 1024));

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    // Email and Name are the first two TextFields (Persönliche Nachricht,
    // the third, is deliberately not width-capped).
    final emailFieldWidth = tester.getSize(find.byWidget(fields[0])).width;
    final nameFieldWidth = tester.getSize(find.byWidget(fields[1])).width;

    expect(emailFieldWidth, lessThanOrEqualTo(310));
    expect(nameFieldWidth, lessThanOrEqualTo(310));
  });

  testWidgets('the Senden button is a normal width, not stretched full-width on a tablet', (tester) async {
    await pumpScreen(tester, viewSize: const Size(1366, 1024));

    final buttonWidth = tester.getSize(find.widgetWithText(FilledButton, 'Senden')).width;
    expect(buttonWidth, lessThan(300), reason: 'a content-hugging button, not one stretched to fill the screen');
  });
}
