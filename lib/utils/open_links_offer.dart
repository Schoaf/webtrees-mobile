import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../state/app_providers.dart';

const _kOfferedPrefKey = 'open_links_offered';

/// Opens the server's "App" page in the browser, where the user agrees to
/// open this tree's links in the app - the choice is a cookie of that
/// browser, so the app can't set it itself. The page then leads back here.
Future<void> setUpOpenLinks(WidgetRef ref) async {
  final uri = ref.read(webtreesClientProvider).openLinksSetupUri(ref.read(treeNameProvider));
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Whether the connected server's module can open links in the app - false
/// when it can't be asked.
Future<bool> canOpenLinksInApp(WidgetRef ref) async {
  try {
    return await ref.read(webtreesClientProvider).canOpenLinksInApp(ref.read(treeNameProvider));
  } catch (_) {
    return false;
  }
}

/// After setting up a server: asks once whether its links should open in
/// the app - only if its module offers it. Later it's in "Mein Konto".
Future<void> offerOpenLinksOnce(BuildContext context, WidgetRef ref) async {
  final key = '$_kOfferedPrefKey:${ref.read(serverUrlProvider)}';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(key) ?? false) return;
  if (!await canOpenLinksInApp(ref)) return;
  await prefs.setBool(key, true);
  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  final isSettingUp = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.openLinksPromptTitle),
      content: Text(l10n.openLinksPromptBody),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.openLinksPromptLater)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.openLinksPromptSetUp)),
      ],
    ),
  );
  if (isSettingUp ?? false) await setUpOpenLinks(ref);
}
