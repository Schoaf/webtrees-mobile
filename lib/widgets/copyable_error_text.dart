import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/copy_to_clipboard.dart';

/// An inline (non-full-screen) error message that can be selected and
/// copied - for the raw exception text a failed save/action can surface
/// (e.g. a network error with the full request URL in it), which is too
/// long/technical to reliably long-press-select on a phone. See
/// [LoadErrorView] for the equivalent full-screen version used when an
/// initial data load fails rather than a save/action.
class CopyableErrorText extends StatelessWidget {
  const CopyableErrorText({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: l10n.copyErrorDetailsButton,
          onPressed: () => copyToClipboard(message),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}
