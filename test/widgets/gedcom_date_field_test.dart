import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/widgets/gedcom_date_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: GedcomDateField(controller: TextEditingController(text: text))),
      ),
    );
  }

  testWidgets('speaks the app language, not German (#45)', (tester) async {
    await pump(tester, '');
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Choose date'), findsOneWidget);

    await pump(tester, 'ABT 1930');
    expect(find.textContaining('ABT 1930'), findsWidgets);
    expect(find.textContaining('Bisheriger'), findsNothing);
  });
}
