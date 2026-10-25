import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/widgets/photo_description_sheet.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  PhotoDescription? result;
  var isClosed = false;

  Future<void> openSheet(WidgetTester tester, {int count = 1}) async {
    result = null;
    isClosed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPhotoDescriptionSheet(context, [
                for (var i = 0; i < count; i++) Uint8List.fromList(_png),
              ]);
              isClosed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('uploading right away: nothing described, a photo (#38)', (tester) async {
    await openSheet(tester);
    expect(find.text('Foto beschreiben'), findsOneWidget);
    expect(find.textContaining('Gilt für alle'), findsNothing);

    await tester.tap(find.byKey(const Key('uploadPhotosButton')));
    await tester.pumpAndSettle();

    expect((result!.title, result!.note, result!.type), (null, null, 'photo'));
  });

  testWidgets('title, description and document are passed on', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byKey(const Key('photoTitleField')), ' Taufschein ');
    await tester.enterText(find.byKey(const Key('photoDescriptionField')), 'Pfarramt Graz, 1952');
    await tester.tap(find.text('Dokument'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('uploadPhotosButton')));
    await tester.pumpAndSettle();

    expect((result!.title, result!.note, result!.type), ('Taufschein', 'Pfarramt Graz, 1952', 'document'));
  });

  testWidgets('several photos: says it applies to all', (tester) async {
    await openSheet(tester, count: 3);
    expect(find.text('3 Fotos beschreiben'), findsOneWidget);
    expect(find.textContaining('Gilt für alle ausgewählten Fotos.'), findsOneWidget);
  });

  testWidgets('cancel uploads nothing', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect((isClosed, result), (true, null));
  });
}
