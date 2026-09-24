// Store-screenshot generator - NOT a CI test suite.
//
// This renders real app screens (with mocktail-mocked `WebtreesClient` data,
// following the same setUp/pumpWidget pattern as
// test/screens/home_screen_test.dart, search_screen_test.dart and
// person_detail_screen_test.dart) to raw PNGs at the exact pixel dimensions
// the App Store and Play Store expect, for App Store Connect / Play Console
// upload. It is NOT wired into any CI workflow and is not meant to run as
// part of the normal `flutter test` suite - see `_render` below, which skips
// every test here unless explicitly opted in, so this file existing doesn't
// slow down or clutter the real 182-test suite.
//
// Run it explicitly with:
//   flutter test test/screenshots/store_screenshots_test.dart --dart-define=RENDER_SCREENSHOTS=true
//
// Output lands in screenshots/raw/{ios,android}/*.png (gitignored). Feed
// that into `tool/compose_store_screenshots.py` (stage 2) to get final,
// phone-framed, store-ready images in screenshots/store/{ios,android}/.
//
// Gotcha (why this is written the way it is): `RepaintBoundary.toImage()`
// and `Image.toByteData()` do real, native async work and hang forever if
// awaited under the fake async zone `tester.pump()`/`pumpAndSettle()` use -
// they must run inside `tester.runAsync()`. Everything else (pumping the
// widget tree, letting FutureProviders resolve) uses ordinary fake-async
// pumping exactly like the rest of this test suite; only the final
// image-capture step is wrapped in `runAsync`.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/repositories/quick_note_store.dart';
import 'package:webtrees_mobile/screens/home/home_screen.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/screens/search/search_screen.dart';
import 'package:webtrees_mobile/screens/tree_view/tree_view_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/theme/app_theme.dart' show AppColors, buildAppTheme;

const bool _render = bool.fromEnvironment('RENDER_SCREENSHOTS');

class MockWebtreesClient extends Mock implements WebtreesClient {}

class MockQuickNoteStore extends Mock implements QuickNoteStore {}

/// One store target: the exact physical pixel size to render at, and the
/// devicePixelRatio used to get there (physicalSize == logicalSize *
/// devicePixelRatio, so the render is pixel-exact, not a resize).
class _Target {
  const _Target(this.platformDir, this.physicalSize, this.devicePixelRatio);

  final String platformDir;
  final Size physicalSize;
  final double devicePixelRatio;
}

// iOS: 6.9" iPhone display (iPhone 16/17/18 Pro Max class) - the single
// required iOS screenshot size as of the 2026 App Store Connect
// requirements (Apple dropped the older per-device-size requirements in
// 2024). Verified against
// developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
// on 2026-09-24: portrait 1320x2868, which is exactly 440x956 logical
// points at a 3.0 devicePixelRatio (matches the real device's ratio).
const _iosTarget = _Target('ios', Size(1320, 2868), 3.0);

// Android: Google Play phone screenshots accept a flexible aspect ratio,
// but 1080x2400 is a clean, common, safely-in-range resolution (24-bit,
// no alpha channel needed for the store upload - alpha is flattened away
// in stage 2). Rendered at a 2.0 devicePixelRatio (540x1200 logical
// points) rather than a narrower 360dp profile - the Home screen's
// section headers overflow at a genuine 360-logical-width, an existing
// layout tightness on narrow phones that's out of scope to fix here (this
// file only adds screenshot tooling, no widget changes).
const _androidTarget = _Target('android', Size(1080, 2400), 2.0);

const _targets = [_iosTarget, _androidTarget];

/// Blank top inset reserved on every render, as a fraction of the target's
/// physical width - matches (with headroom) the notch's own footprint in
/// `tool/compose_store_screenshots.py` (SAFE_AREA_FRAC there), so the
/// notch always lands on guaranteed-blank pixels instead of overlapping
/// whatever a given screen happens to draw at the very top. Every one of
/// the four screens here renders its body inside a `SafeArea` (checked:
/// HomeScreen, SearchScreen, PersonDetailScreen, TreeViewScreen all do),
/// so setting `tester.view.padding.top` reliably pushes their content down
/// by this amount, the same way a real notched phone would - this isn't
/// screen-specific, so it can't silently stop working for a screen whose
/// top content happens to sit lower (that's what broke the first version
/// of this: the notch overlapped TreeViewScreen's centered "Stammbaum"
/// title even though it happened to clear HomeScreen's left-aligned one).
const _kNotchSafeAreaFraction = 0.09;

Directory get _rawDir => Directory('screenshots/raw');

/// `flutter test`'s headless environment has no fonts registered at all,
/// so text renders as solid placeholder boxes ("tofu") unless real glyph
/// data is loaded first - not useful for store screenshots. Fetching a font
/// over the network isn't an option either (flutter_test blocks all real
/// HTTP requests, returning 400 for every one, which is also why
/// `google_fonts` logs a load error below - harmless here, see
/// `GoogleFonts.config.allowRuntimeFetching` in setUpAll).
///
/// Instead this loads the real Roboto .ttf files every Flutter SDK install
/// already ships at `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/` -
/// the same files a real app build embeds as its default Material font -
/// directly under the exact per-weight family names `google_fonts` uses
/// internally (e.g. `Roboto_regular`, `Roboto_500`; see
/// GoogleFontsFamilyWithVariant.toString() in the google_fonts package).
/// google_fonts' own `fontFamilyFallback` mechanism turned out not to
/// resolve in this headless test environment, so this registers the exact
/// primary family name directly rather than relying on that fallback.
/// Fully local and reproducible: no download, no asset added to the repo.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    // ignore: avoid_print
    print('FLUTTER_ROOT not set - screenshots will show placeholder glyph boxes instead of real text.');
    return;
  }
  final fontsDir = '$root/bin/cache/artifacts/material_fonts';
  const weightToFile = {
    'Roboto_100': 'Roboto-Thin.ttf',
    'Roboto_300': 'Roboto-Light.ttf',
    'Roboto_regular': 'Roboto-Regular.ttf',
    'Roboto_500': 'Roboto-Medium.ttf',
    'Roboto_700': 'Roboto-Bold.ttf',
    'Roboto_900': 'Roboto-Black.ttf',
    // Every Icon widget (search, mail, cake, chevron, ...) paints a glyph
    // from this font under this exact family name - same "SDK already has
    // it locally" trick as Roboto above, otherwise every icon in every
    // screenshot is a placeholder box too.
    'MaterialIcons': 'MaterialIcons-Regular.otf',
  };
  for (final entry in weightToFile.entries) {
    final file = File('$fontsDir/${entry.value}');
    if (!file.existsSync()) continue;
    final loader = FontLoader(entry.key);
    loader.addFont(file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// `flutter_tester`'s headless environment has no "platform default" font
/// at all (see dart:ui's own doc comment: "When no font family is provided
/// ... the platform default font will be used" - here that default is
/// empty). A `Text` widget still comes out fine because it merges with the
/// ambient `DefaultTextStyle`, which carries the app's theme font - but a
/// bare `RichText` (as `PersonCard` uses for the person name, so it can mix
/// styled spans) supplies its own `TextStyle` with no `fontFamily` at all,
/// bypassing that inheritance, and paints as a solid block instead of
/// glyphs. Not fixable from here without editing `lib/widgets/person_card
/// .dart`, which is out of scope for a screenshot-tooling-only change,
/// so instead this finds any such unstyled `RichText` after the first pump,
/// and overlays a second copy of the same spans with an explicit font
/// family (one of the ones `_loadRealFonts` registered) directly on top,
/// masking the solid block with the row's own background color first.
bool _hasUnresolvableFamily(InlineSpan span) {
  if (span is! TextSpan) return false;
  final style = span.style;
  final bare = style == null || (style.fontFamily == null && (style.fontFamilyFallback?.isEmpty ?? true));
  if (bare) return true;
  return span.children?.any(_hasUnresolvableFamily) ?? false;
}

InlineSpan _patchSpan(InlineSpan span) {
  if (span is! TextSpan) return span;
  final style = span.style;
  final bare = style == null || (style.fontFamily == null && (style.fontFamilyFallback?.isEmpty ?? true));
  final family = (style?.fontWeight?.value ?? 400) >= 500 ? 'Roboto_500' : 'Roboto_regular';
  return TextSpan(
    text: span.text,
    style: bare ? (style ?? const TextStyle()).copyWith(fontFamily: family) : style,
    children: span.children?.map(_patchSpan).toList(),
  );
}

/// Scans the currently-pumped tree for `RichText`s with no resolvable
/// font family and returns a `Positioned` patch for each, in the tree's
/// global coordinate space (valid as long as the widget is re-pumped with
/// the exact same layout, e.g. wrapped one level deeper in a `Stack`).
List<Widget> _collectBareRichTextPatches() {
  final patches = <Widget>[];
  for (final element in find.byType(RichText).evaluate()) {
    final richText = element.widget as RichText;
    if (!_hasUnresolvableFamily(richText.text)) continue;

    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) continue;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) continue;

    // A 1px pad on every side: the original (still-present, underneath)
    // unstyled RichText and this patch are laid out in two separate pump
    // passes, so their rasterized edges can round to different physical
    // pixels at high devicePixelRatio - padding the mask avoids a hairline
    // sliver of the original showing through at the boundary.
    patches.add(
      Positioned(
        left: topLeft.dx - 1,
        top: topLeft.dy - 1,
        width: size.width + 2,
        height: size.height + 2,
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(1),
          child: RichText(
            overflow: richText.overflow,
            maxLines: richText.maxLines,
            textAlign: richText.textAlign,
            text: _patchSpan(richText.text),
          ),
        ),
      ),
    );
  }
  return patches;
}

/// Pumps [screen] inside a keyed RepaintBoundary at [target]'s exact pixel
/// size, lets it settle (running [afterPump] too, e.g. to type a search
/// query), then captures and saves a PNG to
/// `screenshots/raw/{platform}/{name}.png`. If any bare `RichText` needs
/// patching (see above), re-pumps once more with the patches overlaid
/// before capturing.
Future<void> _renderAndSave(
  WidgetTester tester, {
  required ProviderContainer container,
  required Widget screen,
  required String name,
  required _Target target,
  Future<void> Function(WidgetTester tester)? afterPump,
}) async {
  tester.view.physicalSize = target.physicalSize;
  tester.view.devicePixelRatio = target.devicePixelRatio;
  // Reserve blank space at the very top for stage 2's notch - see
  // _kNotchSafeAreaFraction.
  tester.view.padding = FakeViewPadding(top: target.physicalSize.width * _kNotchSafeAreaFraction);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  Widget buildApp() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: screen,
    ),
  );

  var boundaryKey = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: buildApp()));
  await tester.pumpAndSettle();
  if (afterPump != null) await afterPump(tester);

  final patches = _collectBareRichTextPatches();
  if (patches.isNotEmpty) {
    boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: [Positioned.fill(child: buildApp()), ...patches]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (afterPump != null) await afterPump(tester);
  }

  // See the file-level comment: only the actual image capture needs
  // runAsync - the pump/pumpAndSettle above already ran under normal fake
  // async and must NOT be nested inside runAsync.
  await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: target.devicePixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final dir = Directory('${_rawDir.path}/${target.platformDir}')..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    file.writeAsBytesSync(byteData!.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
  });
}

void main() {
  setUpAll(() async {
    _rawDir.createSync(recursive: true);
    // Keep this self-contained/reproducible: don't let google_fonts try to
    // fetch Roboto from fonts.gstatic.com (flutter_test's HttpClient stub
    // blocks it anyway - every request comes back as a 400); load the SDK's
    // own bundled Roboto files instead (see _loadRealFonts).
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadRealFonts();
  });

  group('store screenshots', () {
    late MockWebtreesClient client;

    setUp(() {
      client = MockWebtreesClient();
      when(() => client.imageHeaders).thenReturn(<String, String>{});
    });

    testWidgets('HomeScreen', (tester) async {
      final noteStore = MockQuickNoteStore();
      when(() => noteStore.unsynced()).thenAnswer((_) async => <QuickNote>[]);

      when(() => client.info('Famtree')).thenAnswer(
        (_) async => {
          'user': {'realName': 'Elisabeth Bergmann'},
          'trees': [
            {
              'name': 'Famtree',
              'title': 'Familie Bergmann',
              'individuals': 187,
              'userXref': 'I1',
              'defaultXref': 'I1',
            },
          ],
        },
      );
      when(() => client.individual('Famtree', 'I1')).thenAnswer(
        (_) async => {
          'person': {
            'xref': 'I1',
            'name': 'Elisabeth Bergmann',
            'sex': 'F',
            'isDead': false,
            'lifespan': '1985-',
          },
        },
      );
      when(() => client.anniversaries('Famtree', days: 7)).thenAnswer(
        (_) async => {
          'data': [
            {
              'tag': 'BIRT',
              'inDays': 2,
              'years': 41,
              'person': {'xref': 'I7', 'name': 'Thomas Bergmann', 'isDead': false},
            },
            {
              'tag': 'BIRT',
              'inDays': 5,
              'years': 8,
              'person': {'xref': 'I8', 'name': 'Mia Bergmann', 'isDead': false},
            },
          ],
        },
      );
      when(() => client.shareRequestUnreadCount('Famtree')).thenAnswer((_) async => 2);

      final container = ProviderContainer(
        overrides: [
          webtreesClientProvider.overrideWithValue(client),
          quickNoteStoreProvider.overrideWithValue(noteStore),
        ],
      );
      addTearDown(container.dispose);

      for (final target in _targets) {
        await _renderAndSave(
          tester,
          container: container,
          screen: const HomeScreen(),
          name: 'home',
          target: target,
        );
      }
    }, skip: !_render);

    testWidgets('SearchScreen with results', (tester) async {
      when(() => client.individuals('Famtree', query: 'Bergmann')).thenAnswer(
        (_) async => {
          'data': [
            {'xref': 'I1', 'name': 'Elisabeth Bergmann', 'sex': 'F', 'isDead': false},
            {'xref': 'I2', 'name': 'Thomas Bergmann', 'sex': 'M', 'isDead': false},
            {'xref': 'I3', 'name': 'Heinrich Bergmann', 'sex': 'M', 'isDead': true},
            {'xref': 'I4', 'name': 'Mia Bergmann', 'sex': 'F', 'isDead': false},
            {'xref': 'I5', 'name': 'Karolina Bergmann-Weiss', 'sex': 'F', 'isDead': false},
            {'xref': 'I6', 'name': 'Friedrich Bergmann', 'sex': 'M', 'isDead': true},
          ],
        },
      );

      final container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
      addTearDown(container.dispose);

      // Type the query so the results (not the empty prompt) are on screen
      // for the screenshot.
      Future<void> typeQuery(WidgetTester tester) async {
        await tester.enterText(find.byType(TextField), 'Bergmann');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        await tester.pump();
      }

      for (final target in _targets) {
        await _renderAndSave(
          tester,
          container: container,
          screen: const SearchScreen(),
          name: 'search',
          target: target,
          afterPump: typeQuery,
        );
      }
    }, skip: !_render);

    testWidgets('PersonDetailScreen, filled out', (tester) async {
      final personJson = {
        'ok': true,
        'person': {
          'xref': 'I1',
          'name': 'Elisabeth Bergmann',
          'sex': 'F',
          'isDead': false,
          'lifespan': '* 1985',
        },
        'facts': [
          {
            'tag': 'BIRT',
            'label': 'Geburt',
            'value': '',
            'date': {'text': '14. März 1985', 'gedcom': '14 MAR 1985'},
            'place': {'short': 'Graz, Steiermark, Österreich'},
          },
          {'tag': 'SEX', 'label': 'Geschlecht', 'value': 'Weiblich'},
          {
            'tag': 'OCCU',
            'label': 'Beruf',
            'value': 'Kinderärztin',
            'date': null,
            'place': null,
          },
          {
            'tag': 'RESI',
            'label': 'Wohnort',
            'value': '',
            'date': {'text': 'seit 2012', 'gedcom': ''},
            'place': {'short': 'Klagenfurt, Kärnten, Österreich'},
          },
          {'tag': 'TITL', 'label': 'Titel', 'value': 'Dr.'},
          {'tag': 'REFN', 'label': 'Referenz', 'value': 'BER-1985-04'},
        ],
        'parentFamilies': [
          {
            'husband': {'xref': 'I2', 'name': 'Friedrich Bergmann', 'sex': 'M', 'isDead': true},
            'wife': {'xref': 'I3', 'name': 'Karolina Bergmann', 'sex': 'F', 'isDead': false},
          },
        ],
        'spouseFamilies': [
          {
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sex': 'M', 'isDead': false},
            'children': [
              {'xref': 'I5', 'name': 'Mia Wagner', 'sex': 'F', 'isDead': false},
              {'xref': 'I6', 'name': 'Paul Wagner', 'sex': 'M', 'isDead': false},
              {'xref': 'I7', 'name': 'Lena Wagner', 'sex': 'F', 'isDead': false},
            ],
          },
        ],
        'siblings': [
          {'xref': 'I8', 'name': 'Heinrich Bergmann', 'sex': 'M', 'isDead': false},
          {'xref': 'I9', 'name': 'Anna Bergmann', 'sex': 'F', 'isDead': false},
        ],
        'media': <dynamic>[],
        'canEdit': false,
      };
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson);

      final container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
      addTearDown(container.dispose);

      for (final target in _targets) {
        await _renderAndSave(
          tester,
          container: container,
          screen: const PersonDetailScreen(xref: 'I1'),
          name: 'person_detail',
          target: target,
        );
      }
    }, skip: !_render);

    testWidgets('TreeViewScreen, filled out', (tester) async {
      final individualJson = {
        'ok': true,
        'person': {'xref': 'I1', 'name': 'Elisabeth Bergmann', 'sortName': 'Bergmann,Elisabeth'},
        'facts': [
          {'tag': 'OCCU', 'value': 'Kinderärztin'},
        ],
        'birth': {
          'date': {'text': '14. März 1985', 'year': 1985},
          'place': {'short': 'Graz'},
        },
        'parentFamilies': [
          {
            'husband': {
              'xref': 'I2',
              'name': 'Friedrich Bergmann',
              'sortName': 'Bergmann,Friedrich',
              'sex': 'M',
              'isDead': true,
              'birth': {'date': {'year': 1952}},
            },
            'wife': {
              'xref': 'I3',
              'name': 'Karolina Bergmann',
              'sortName': 'Bergmann,Karolina',
              'sex': 'F',
              'isDead': false,
              'birth': {'date': {'year': 1955}},
            },
          },
        ],
        'spouseFamilies': [
          {
            'xref': 'F1',
            'maritalStatus': 'married',
            'marriage': {'date': {'year': 2011}},
            'spouse': {
              'xref': 'I4',
              'name': 'Thomas Wagner',
              'sortName': 'Wagner,Thomas',
              'sex': 'M',
              'isDead': false,
              'birth': {'date': {'year': 1983}},
            },
            'children': [
              {
                'xref': 'I5',
                'name': 'Mia Wagner',
                'sortName': 'Wagner,Mia',
                'sex': 'F',
                'isDead': false,
                'birth': {'date': {'year': 2013}},
              },
              {
                'xref': 'I6',
                'name': 'Paul Wagner',
                'sortName': 'Wagner,Paul',
                'sex': 'M',
                'isDead': false,
                'birth': {'date': {'year': 2015}},
              },
              {
                'xref': 'I7',
                'name': 'Lena Wagner',
                'sortName': 'Wagner,Lena',
                'sex': 'F',
                'isDead': false,
                'birth': {'date': {'year': 2018}},
              },
            ],
          },
        ],
        'siblings': [
          {
            'xref': 'I8',
            'name': 'Heinrich Bergmann',
            'sortName': 'Bergmann,Heinrich',
            'sex': 'M',
            'isDead': false,
            'birth': {'date': {'year': 1982}},
          },
          {
            'xref': 'I9',
            'name': 'Anna Bergmann',
            'sortName': 'Bergmann,Anna',
            'sex': 'F',
            'isDead': false,
            'birth': {'date': {'year': 1988}},
          },
        ],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
      };
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => individualJson);

      final container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
      addTearDown(container.dispose);

      for (final target in _targets) {
        await _renderAndSave(
          tester,
          container: container,
          screen: const TreeViewScreen(xref: 'I1'),
          name: 'tree_view',
          target: target,
        );
      }
    }, skip: !_render);
  });
}
