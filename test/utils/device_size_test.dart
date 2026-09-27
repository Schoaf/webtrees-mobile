import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/device_size.dart';

Widget _wrapAt(Size size, WidgetBuilder builder) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Builder(builder: builder),
  );
}

void main() {
  testWidgets('tabletBoundedMaxWidth matches isWideLandscapeTablet exactly - 1100 wide, 480 otherwise', (
    tester,
  ) async {
    double? wideResult;
    double? narrowResult;

    await tester.pumpWidget(
      _wrapAt(const Size(1100, 800), (context) {
        wideResult = tabletBoundedMaxWidth(context);
        expect(isWideLandscapeTablet(context), isTrue);
        return const SizedBox();
      }),
    );

    await tester.pumpWidget(
      _wrapAt(const Size(400, 800), (context) {
        narrowResult = tabletBoundedMaxWidth(context);
        expect(isWideLandscapeTablet(context), isFalse);
        return const SizedBox();
      }),
    );

    expect(wideResult, 1100);
    expect(narrowResult, 480);
  });
}
