import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/start_person.dart';
import 'load_error_view.dart';

/// Builds a tab's page for the start person (see startXrefProvider), with
/// a spinner while it loads and an error page if there is none.
class StartPersonBuilder extends ConsumerWidget {
  const StartPersonBuilder({super.key, required this.builder});

  final Widget Function(String xref) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ref
        .watch(startXrefProvider)
        .when(
          loading: () => const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          ),
          error: (error, _) => Scaffold(
            body: SafeArea(child: LoadErrorView(message: l10n.couldNotLoad('$error'))),
          ),
          data: (xref) => xref == null
              ? Scaffold(
                  body: SafeArea(child: LoadErrorView(message: l10n.noLinkedPersonError)),
                )
              : builder(xref),
        );
  }
}
