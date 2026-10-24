import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/media_viewer_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

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
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpViewer(WidgetTester tester, List<Map<String, dynamic>> photos, {bool canEdit = true}) async {
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
      () => client.postFact('Famtree', 'M1', tag: 'NOTE', value: any(named: 'value')),
    ).thenAnswer((_) async => {'ok': true});
    when(() => client.postUnlinkMedia('Famtree', 'I1', media: 'M1')).thenAnswer((_) async => {'ok': true});
    await pumpViewer(tester, [_photo('M1', isPrimary: true), _photo('M2')]);

    await tester.tap(find.byKey(const Key('removePhotoButton')));
    await tester.pumpAndSettle();
    expect(find.text('Foto von Anna Muster entfernen?'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('removePhotoComment')), 'Falsche Person');
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();

    verify(
      () => client.postFact('Famtree', 'M1', tag: 'NOTE', value: 'Von Anna Muster (I1) entfernt: Falsche Person'),
    ).called(1);
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

    verifyNever(() => client.postFact(any(), any(), tag: any(named: 'tag'), value: any(named: 'value')));
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
}
