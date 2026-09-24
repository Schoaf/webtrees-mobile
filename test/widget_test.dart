import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webtrees_mobile/main.dart';
import 'package:webtrees_mobile/screens/auth/login_screen.dart';

void main() {
  testWidgets('shows the login screen when not authenticated', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StammbaumApp()));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
