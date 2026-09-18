import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stammbaum_app/main.dart';

void main() {
  testWidgets('shows the login screen when not authenticated', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StammbaumApp()));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
  });
}
