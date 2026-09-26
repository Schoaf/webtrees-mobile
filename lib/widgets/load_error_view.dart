import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/copy_to_clipboard.dart';

/// The content shown when a screen's initial data load fails - a
/// [SelectableText] (so the raw error can be manually selected, unlike a
/// plain [Text]) plus an explicit copy button, since some exceptions (Dio
/// connection errors in particular) carry the full request URL and are too
/// long to reliably long-press-select on a phone. Content-only, not a
/// [Scaffold] itself: a screen that already renders its own back button
/// (e.g. TreeViewScreen's top bar) can drop this straight into its body,
/// while one that doesn't should wrap it in a Scaffold with an AppBar - see
/// PersonDetailScreen's error branches for that case.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: Colors.grey),
            const SizedBox(height: 12),
            SelectableText(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => copyToClipboard(message),
              icon: const Icon(Icons.copy, size: 16),
              label: Text(l10n.copyErrorDetailsButton),
            ),
          ],
        ),
      ),
    );
  }
}
