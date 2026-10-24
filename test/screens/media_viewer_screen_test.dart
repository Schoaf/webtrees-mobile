import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/media_viewer_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/state/person_history.dart';
import 'package:webtrees_mobile/widgets/cropped_photo.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

Map<String, dynamic> _photo(String xref, {bool isPrimary = false}) => {
  'xref': xref,
  'isImage': true,
  'thumb': 'https://example.org/$xref-thumb.jpg',
  'file': 'https://example.org/$xref.jpg',
  'primary': isPrimary,
};

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;
  bool? popResult;

  setUp(() {
    popResult = null;
    client = MockWebtreesClient();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    when(() => client.usePrettyUrls).thenReturn(false);
  });

  Future<void> pumpViewer(
    WidgetTester tester,
    List<Map<String, dynamic>> photos, {
    bool canEdit = true,
    int? apiLevel,
  }) async {
    final image = (await tester.runAsync(() => createTestImage(width: 400, height: 300)))!;
    container = ProviderContainer(
      overrides: [
        webtreesClientProvider.overrideWithValue(client),
        apiLevelProvider.overrideWith((ref) async => apiLevel),
        networkImageLoaderProvider.overrideWithValue((_, _) async => image),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popResult = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => MediaViewerScreen(
                      personXref: 'I1',
                      personName: 'Anna Muster',
                      photos: photos,
                      canEdit: canEdit,
                    ),
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

  testWidgets('swipes through the photos, with a thumbnail strip', (tester) async {
    await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2'), _photo('M3')]);

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byKey(const Key('photoThumbnails')), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('no edit buttons without edit rights', (tester) async {
    await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2')], canEdit: false);

    expect(find.byKey(const Key('primaryPhotoButton')), findsNothing);
    expect(find.byKey(const Key('removePhotoButton')), findsNothing);
  });

  testWidgets('makes the photo in view the main photo', (tester) async {
    when(() => client.postPrimaryMedia('Famtree', 'I1', media: 'M2')).thenAnswer((_) async => {'ok': true});
    await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2')]);

    final button = find.byKey(const Key('primaryPhotoButton'));
    expect(tester.widget<IconButton>(button).onPressed, isNull, reason: 'already the main photo');

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    verify(() => client.postPrimaryMedia('Famtree', 'I1', media: 'M2')).called(1);
    expect(tester.widget<IconButton>(button).onPressed, isNull, reason: 'now the main photo');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(popResult, isTrue, reason: 'the person page reloads');
  });

  testWidgets('removes the photo from the person, with the comment as a note at the photo', (tester) async {
    when(
      () => client.postFact(
        'Famtree',
        'M1',
        tag: 'NOTE',
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async => {'ok': true});
    when(() => client.postUnlinkMedia('Famtree', 'I1', media: 'M1')).thenAnswer((_) async => {'ok': true});
    await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2')]);

    await tester.tap(find.byKey(const Key('removePhotoButton')));
    await tester.pumpAndSettle();
    expect(find.text('Foto von Anna Muster entfernen?'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('removePhotoComment')), 'Falsche Person');
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();

    verify(() => client.postFact('Famtree', 'M1', tag: 'NOTE', value: 'Von Anna Muster (I1) entfernt: Falsche Person'))
        .called(1);
    verify(() => client.postUnlinkMedia('Famtree', 'I1', media: 'M1')).called(1);
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('removing without a comment writes no note; the last photo closes the view', (tester) async {
    when(() => client.postUnlinkMedia('Famtree', 'I1', media: 'M1')).thenAnswer((_) async => {'ok': true});
    await pumpViewer(tester, [_photo('M1', isPrimary: true)]);

    await tester.tap(find.byKey(const Key('removePhotoButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();

    verifyNever(
      () => client.postFact(
        any(),
        any(),
        tag: any(named: 'tag'),
        value: any(named: 'value'),
      ),
    );
    expect(find.byType(MediaViewerScreen), findsNothing);
    expect(popResult, isTrue);
  });

  testWidgets('cancelling the question removes nothing', (tester) async {
    await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2')]);

    await tester.tap(find.byKey(const Key('removePhotoButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    verifyNever(() => client.postUnlinkMedia(any(), any(), media: any(named: 'media')));
    expect(find.text('1 / 2'), findsOneWidget);
  });

  group('marking people (#37)', () {
    testWidgets('an older server: no marks, no marking', (tester) async {
      await pumpViewer(tester, [_photo('M1', isPrimary: true)]);
      expect(find.byKey(const Key('marksButton')), findsNothing);
      expect(find.byKey(const Key('photoMenu')), findsNothing);
    });

    testWidgets('shows who is marked where; tapping one opens them', (tester) async {
      when(() => client.mediaObject('Famtree', 'M1')).thenAnswer(
        (_) async => {
          'xref': 'M1',
          'people': [
            {'xref': 'I1', 'name': 'Anna Muster', 'crop': null},
            {
              'xref': 'I2',
              'name': 'Karl Muster',
              'crop': {'top': 10, 'left': 20, 'height': 100, 'width': 100},
            },
          ],
        },
      );
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], canEdit: false, apiLevel: 40);

      await tester.tap(find.byKey(const Key('marksButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mark-I1')), findsNothing, reason: 'no crop, no frame');
      expect(find.text('Karl Muster'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mark-I2')));
      await tester.pumpAndSettle();
      expect(container.read(personHistoryProvider).activeXref, 'I2');
    });

    testWidgets('adjusts the crop of this person', (tester) async {
      when(
        () => client.postMediaCrop(
          'Famtree',
          'I1',
          media: 'M1',
          crop: any(named: 'crop'),
        ),
      ).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [
        _photo('M1', isPrimary: true)..['crop'] = {'top': 10, 'left': 20, 'height': 100, 'width': 100},
      ], apiLevel: 40);

      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ausschnitt anpassen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveCropButton')));
      await tester.pumpAndSettle();

      verify(
        () => client.postMediaCrop(
          'Famtree',
          'I1',
          media: 'M1',
          crop: {'top': 10, 'left': 20, 'height': 100, 'width': 100},
        ),
      ).called(1);
      expect(find.text('Ausschnitt gespeichert.'), findsOneWidget);
    });

    testWidgets('marks another person: frame, who is it - their main photo when they have none', (tester) async {
      when(() => client.individuals('Famtree', query: any(named: 'query'))).thenAnswer(
        (_) async => {
          'data': [
            {'xref': 'I9', 'name': 'Berta Muster', 'sex': 'F', 'isDead': false},
          ],
        },
      );
      when(
        () => client.postMediaCrop(
          'Famtree',
          'I9',
          media: 'M1',
          crop: any(named: 'crop'),
        ),
      ).thenAnswer((_) async => {'ok': true});
      when(() => client.postPrimaryMedia('Famtree', 'I9', media: 'M1')).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 40);

      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Person markieren'));
      await tester.pumpAndSettle();
      expect(find.text('Rahmen um die Person'), findsOneWidget);
      await tester.tap(find.byKey(const Key('saveCropButton')));
      await tester.pumpAndSettle();

      expect(find.text('Wer ist das?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Berta');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Berta Muster', findRichText: true));
      await tester.pumpAndSettle();

      verify(
        () => client.postMediaCrop(
          'Famtree',
          'I9',
          media: 'M1',
          crop: {'top': 75, 'left': 125, 'height': 150, 'width': 150},
        ),
      ).called(1);
      verify(() => client.postPrimaryMedia('Famtree', 'I9', media: 'M1')).called(1);
      expect(find.text('Berta Muster markiert.'), findsOneWidget);
    });

    testWidgets('someone with a photo is asked, old and new side by side', (tester) async {
      when(() => client.individuals('Famtree', query: any(named: 'query'))).thenAnswer(
        (_) async => {
          'data': [
            {'xref': 'I9', 'name': 'Berta Muster', 'sex': 'F', 'isDead': false, 'thumb': 'https://example.org/old.jpg'},
          ],
        },
      );
      when(
        () => client.postMediaCrop(
          'Famtree',
          'I9',
          media: 'M1',
          crop: any(named: 'crop'),
        ),
      ).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 40);

      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Person markieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveCropButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Berta');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Berta Muster', findRichText: true));
      await tester.pumpAndSettle();

      expect(find.text('Als Hauptfoto von Berta Muster verwenden?'), findsOneWidget);
      expect(find.byType(CroppedPhoto), findsOneWidget);
      await tester.tap(find.text('Bisheriges behalten'));
      await tester.pumpAndSettle();
      verifyNever(() => client.postPrimaryMedia(any(), any(), media: any(named: 'media')));
    });
  });
}
