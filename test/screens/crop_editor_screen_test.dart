import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/models/photo_crop.dart';
import 'package:webtrees_mobile/screens/search/crop_editor_screen.dart';
import 'package:webtrees_mobile/widgets/cropped_photo.dart';

void main() {
  late ui.Image image;
  PhotoCrop? result;

  Future<void> pumpEditor(WidgetTester tester, {Object? initialCrop}) async {
    image = (await tester.runAsync(() => createTestImage(width: 400, height: 300)))!;
    result = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [networkImageLoaderProvider.overrideWithValue((_, _) async => image)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<PhotoCrop>(
                  MaterialPageRoute(
                    builder: (_) =>
                        CropEditorScreen(url: 'x', headers: const {}, title: 'Rahmen', initialCrop: initialCrop),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts with a centred square and saves it (#37)', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const Key('saveCropButton')));
    await tester.pumpAndSettle();
    expect(result!.toJson(), {'top': 75, 'left': 125, 'height': 150, 'width': 150});
  });

  testWidgets('dragging moves the frame, never past the edge', (tester) async {
    await pumpEditor(tester);
    await tester.drag(find.byKey(const Key('cropFrame')), const Offset(2000, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveCropButton')));
    await tester.pumpAndSettle();
    expect(result!.toJson(), {'top': 150, 'left': 250, 'height': 150, 'width': 150});
  });

  testWidgets('the corner handle resizes, at most to the shorter side', (tester) async {
    await pumpEditor(tester, initialCrop: {'top': 0, 'left': 0, 'height': 100, 'width': 100});
    await tester.drag(find.byKey(const Key('cropHandle')), const Offset(2000, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveCropButton')));
    await tester.pumpAndSettle();
    expect(result!.toJson(), {'top': 0, 'left': 0, 'height': 300, 'width': 300});
  });
}
