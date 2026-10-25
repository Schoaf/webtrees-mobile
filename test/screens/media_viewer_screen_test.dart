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

    expect(find.byKey(const Key('photoMenu')), findsNothing);
    expect(find.byKey(const Key('removePhotoButton')), findsNothing);
  });

  testWidgets('makes the photo in view the profile photo, from the menu only', (tester) async {
    when(() => client.postPrimaryMedia('Famtree', 'I1', media: 'M2')).thenAnswer((_) async => {'ok': true});
    await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2')]);
    expect(find.byKey(const Key('primaryPhotoButton')), findsNothing, reason: 'no symbol at the top');

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photoMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als Profilbild verwenden'));
    await tester.pumpAndSettle();
    verify(() => client.postPrimaryMedia('Famtree', 'I1', media: 'M2')).called(1);

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
    Map<String, dynamic> object(List<Map<String, dynamic>> people) => {'xref': 'M1', 'people': people};

    setUp(() {
      when(() => client.mediaObject('Famtree', 'M1')).thenAnswer((_) async => object([]));
    });

    testWidgets('an older server: no marking, no "Auf dem Foto"', (tester) async {
      await pumpViewer(tester, [_photo('M1', isPrimary: true)]);
      expect(find.byKey(const Key('markPeopleButton')), findsNothing);
      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Personen markieren'), findsNothing);
      expect(find.text('Auf dem Foto'), findsNothing);
      verifyNever(() => client.mediaObject(any(), any()));
    });

    testWidgets('the profile photo carries a label; the menu offers it for the others', (tester) async {
      when(() => client.postPrimaryMedia('Famtree', 'I1', media: 'M2')).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2')]);
      expect(find.text('Profilbild'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Profilbild'), findsNothing);
      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Als Profilbild verwenden'));
      await tester.pumpAndSettle();

      verify(() => client.postPrimaryMedia('Famtree', 'I1', media: 'M2')).called(1);
      expect(find.text('Profilbild'), findsOneWidget);
    });

    testWidgets('"Auf dem Foto" lists who is on it; a name shows the frame, the frame leads to them', (tester) async {
      when(() => client.mediaObject('Famtree', 'M1')).thenAnswer(
        (_) async => object([
          {'xref': 'I1', 'name': 'Anna Muster', 'crop': null},
          {
            'xref': 'I2',
            'name': 'Karl Muster',
            'crop': {'top': 10, 'left': 20, 'height': 100, 'width': 100},
          },
        ]),
      );
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], canEdit: false, apiLevel: 40);

      expect(find.text('Auf dem Foto'), findsOneWidget);
      expect(find.byKey(const Key('mark-I2')), findsNothing, reason: 'no frame until a name is tapped');

      // The name shows where the person is on the photo; their frame leads to them.
      await tester.tap(find.byKey(const Key('onPhoto-I2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mark-I2')), findsOneWidget);
      expect(container.read(personHistoryProvider).activeXref, isNot('I2'));
      await tester.tap(find.byKey(const Key('mark-I2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlinkPerson')), findsNothing, reason: 'no edit rights');
      await tester.tap(find.byKey(const Key('goToPerson')));
      await tester.pumpAndSettle();
      expect(container.read(personHistoryProvider).activeXref, 'I2');
    });

    testWidgets('nobody marked: no "Auf dem Foto"', (tester) async {
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], canEdit: false, apiLevel: 40);
      expect(find.text('Auf dem Foto'), findsNothing);
      expect(find.byKey(const Key('markPeopleButton')), findsNothing, reason: 'no edit rights');
    });

    testWidgets('marking: all frames show, a tapped frame is adjusted', (tester) async {
      when(() => client.mediaObject('Famtree', 'M1')).thenAnswer(
        (_) async => object([
          {'xref': 'I1', 'name': 'Anna Muster', 'crop': null},
          {
            'xref': 'I2',
            'name': 'Karl Muster',
            'crop': {'top': 10, 'left': 20, 'height': 100, 'width': 100},
          },
        ]),
      );
      when(
        () => client.postMediaCrop(
          'Famtree',
          'I2',
          media: 'M1',
          crop: any(named: 'crop'),
        ),
      ).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 40);

      await tester.tap(find.byKey(const Key('markPeopleButton')));
      await tester.pumpAndSettle();
      expect(find.text('Personen markieren'), findsOneWidget);
      expect(find.byKey(const Key('mark-I1')), findsNothing, reason: 'no crop, no frame');
      await tester.tap(find.byKey(const Key('mark-I2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rahmen anpassen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveCropButton')));
      await tester.pumpAndSettle();

      verify(
        () => client.postMediaCrop(
          'Famtree',
          'I2',
          media: 'M1',
          crop: {'top': 10, 'left': 20, 'height': 100, 'width': 100},
        ),
      ).called(1);
      expect(find.text('Rahmen gespeichert.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('endMarkingButton')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);
    });

    Future<void> markBerta(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personen markieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addMarkButton')));
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
    }

    testWidgets('+ Person: frame, who is it - their profile photo when they have none', (tester) async {
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

      await markBerta(tester);

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

      await markBerta(tester);

      expect(find.text('Als Profilbild von Berta Muster verwenden?'), findsOneWidget);
      expect(find.byType(CroppedPhoto), findsOneWidget);
      await tester.tap(find.text('Bisheriges behalten'));
      await tester.pumpAndSettle();
      verifyNever(() => client.postPrimaryMedia(any(), any(), media: any(named: 'media')));
    });

    testWidgets('who is it: the people linked to the photo come first, unmarked at the top', (tester) async {
      when(() => client.mediaObject('Famtree', 'M1')).thenAnswer(
        (_) async => object([
          {
            'xref': 'I2',
            'name': 'Karl Muster',
            'crop': {'top': 10, 'left': 20, 'height': 100, 'width': 100},
          },
          {'xref': 'I1', 'name': 'Anna Muster', 'crop': null},
        ]),
      );
      when(
        () => client.postMediaCrop(
          'Famtree',
          'I1',
          media: 'M1',
          crop: any(named: 'crop'),
        ),
      ).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 40);

      await tester.tap(find.byKey(const Key('markPeopleButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addMarkButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveCropButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('searchOtherPerson')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('pick-I1'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('pick-I2'))).dy),
      );
      await tester.tap(find.byKey(const Key('pick-I1')));
      await tester.pumpAndSettle();

      verify(
        () => client.postMediaCrop(
          'Famtree',
          'I1',
          media: 'M1',
          crop: any(named: 'crop'),
        ),
      ).called(1);
      verifyNever(() => client.postPrimaryMedia(any(), any(), media: any(named: 'media')));
      expect(find.text('Anna Muster markiert.'), findsOneWidget, reason: 'already her profile photo: no question');
    });

    testWidgets('turns the photo on the server, from the menu (#40)', (tester) async {
      when(() => client.postMediaRotate('Famtree', 'M1', quarterTurns: 1)).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 41);

      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drehen'));
      await tester.pumpAndSettle();

      verify(() => client.postMediaRotate('Famtree', 'M1', quarterTurns: 1)).called(1);
      expect(find.text('Foto gedreht.'), findsOneWidget);
    });

    testWidgets('no turning on a server without it', (tester) async {
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 40);
      await tester.tap(find.byKey(const Key('photoMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Drehen'), findsNothing);
    });

    testWidgets('Back while marking ends marking, not the media view', (tester) async {
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 40);
      await tester.tap(find.byKey(const Key('markPeopleButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('endMarkingButton')));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
    });

    testWidgets('a marked person can be unlinked from the photo; the view stays', (tester) async {
      when(() => client.mediaObject('Famtree', 'M1')).thenAnswer(
        (_) async => object([
          {
            'xref': 'I2',
            'name': 'Karl /Muster/',
            'crop': {'top': 10, 'left': 20, 'height': 100, 'width': 100},
          },
        ]),
      );
      when(() => client.postUnlinkMedia('Famtree', 'I2', media: 'M1')).thenAnswer((_) async => {'ok': true});
      await pumpViewer(tester, [_photo('M1', isPrimary: true)], apiLevel: 40);

      await tester.tap(find.byKey(const Key('markPeopleButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mark-I2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unlinkPerson')));
      await tester.pumpAndSettle();
      expect(find.text('Foto von Karl Muster entfernen?'), findsOneWidget);
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();

      verify(() => client.postUnlinkMedia('Famtree', 'I2', media: 'M1')).called(1);
      expect(find.byType(MediaViewerScreen), findsOneWidget);
    });
  });
}
