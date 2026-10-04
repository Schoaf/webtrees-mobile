import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/auth/register_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.info('Famtree')).thenAnswer((_) async => <String, dynamic>{});
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('de'),
          home: RegisterScreen(),
        ),
      ),
    );
  }

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'Anna Muster');
    await tester.enterText(find.byType(TextField).at(1), 'anna@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'anna');
    await tester.enterText(find.byType(TextField).at(3), 'hunter22');
    await tester.enterText(find.byType(TextField).at(4), 'Ich bin die Enkelin von Franz Muster.');
    await tester.pump();
  }

  testWidgets('the submit button stays disabled until every field is filled', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await fillForm(tester);

    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a password under 8 characters keeps the button disabled', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Anna Muster');
    await tester.enterText(find.byType(TextField).at(1), 'anna@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'anna');
    await tester.enterText(find.byType(TextField).at(3), 'short');
    await tester.enterText(find.byType(TextField).at(4), 'Ich bin die Enkelin.');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('a too short password shows the rule once the field is left', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(TextField).at(3));
    await tester.enterText(find.byType(TextField).at(3), 'short');
    await tester.pump();
    // The rule doubles as the placeholder, so check the field's error, not just any text.
    String? passwordError() => tester.widget<TextField>(find.byType(TextField).at(3)).decoration!.errorText;
    expect(passwordError(), isNull, reason: 'no error while still typing');

    await tester.tap(find.byType(TextField).at(4));
    await tester.pump();

    expect(passwordError(), 'Mind. 8 Zeichen');
  });

  testWidgets('an invalid email shows an error once the field is left', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(TextField).at(1));
    await tester.enterText(find.byType(TextField).at(1), 'anna@example');
    await tester.tap(find.byType(TextField).at(2));
    await tester.pump();

    expect(find.text('Bitte eine gültige E-Mail-Adresse eingeben.'), findsOneWidget);
  });

  testWidgets('a successful request shows the confirmation view with a way back to login', (tester) async {
    when(
      () => client.register(
        'Famtree',
        username: 'anna',
        email: 'anna@example.com',
        realName: 'Anna Muster',
        password: 'hunter22',
        comments: 'Ich bin die Enkelin von Franz Muster.',
      ),
    ).thenAnswer((_) async => {'ok': true});

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await fillForm(tester);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Anfrage gesendet'), findsOneWidget);
    expect(find.text('Zurück zur Anmeldung'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a taken username shows the matching server error and stays on the form', (tester) async {
    when(
      () => client.register(
        'Famtree',
        username: 'anna',
        email: 'anna@example.com',
        realName: 'Anna Muster',
        password: 'hunter22',
        comments: 'Ich bin die Enkelin von Franz Muster.',
      ),
    ).thenAnswer((_) async => {'ok': false, 'error': 'username-taken'});

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await fillForm(tester);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Dieser Benutzername ist bereits vergeben.'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('the password field starts obscured and the eye icon toggles visibility', (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    final passwordField = find.byType(TextField).at(3);
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
  });
}
