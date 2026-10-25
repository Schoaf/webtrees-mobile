import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/my_person_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/state/person_history.dart';
import 'package:webtrees_mobile/state/start_person.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  testWidgets('a person opened elsewhere shows even without a start person', (tester) async {
    final client = MockWebtreesClient();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    when(() => client.usePrettyUrls).thenReturn(false);
    when(() => client.individual('Famtree', 'I2')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I2', 'name': 'Berta Muster', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );
    final container = ProviderContainer(
      overrides: [
        webtreesClientProvider.overrideWithValue(client),
        startXrefProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('de'),
          home: MyPersonScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Für dieses Konto ist keine Person verknüpft.'), findsOneWidget);

    container.read(personHistoryProvider.notifier).show('I2');
    await tester.pumpAndSettle();
    expect(find.text('Berta Muster'), findsWidgets);
  });
}
