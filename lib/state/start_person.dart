import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';

/// The person the Person and Stammbaum tabs start with: the one webtrees
/// itself would start with for this user (own Startperson, "this is me",
/// tree default, first individual) - only if they may see it, else null.
/// api4webtrees 1.13.0+.
final startXrefProvider = FutureProvider<String?>((ref) async {
  final client = ref.watch(webtreesClientProvider);
  final tree = ref.watch(treeNameProvider);
  // Depends on who is signed in - asked again after every sign-in, never
  // kept from a moment without a session.
  ref.watch(authControllerProvider.select((auth) => (auth.loggedIn, auth.userName)));
  final info = await client.info(tree);
  final treeInfo = (info['trees'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere(
    (t) => t['name'] == tree,
    orElse: () => const {},
  );
  final startXref = treeInfo['startXref'] as String? ?? '';
  return startXref.isNotEmpty ? startXref : null;
});
