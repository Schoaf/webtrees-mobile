import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/server_url.dart';
import '../../widgets/tablet_bounded_body.dart';
import '../tree_picker/tree_picker_screen.dart';

/// Points the app at a different webtrees server, from the login screen -
/// the way in for someone who has no "Verbinden" link from that server's
/// "App" page. Checks the address with `Info` first (reachable, has
/// api4webtrees, offers at least one tree) and only then switches to it;
/// logging in or registering then happens on the login screen as usual.
class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  late final TextEditingController _urlController;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(serverUrlProvider);
    _urlController = TextEditingController(
      text: current.isEmpty ? '' : Uri.parse(current).host,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final serverUrl = normalizeServerUrl(_urlController.text);
    if (serverUrl == null) {
      setState(() => _error = l10n.serverErrorInvalidUrl);
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    final List<Map<String, dynamic>> trees;
    try {
      final info = await ref.read(serverProbeProvider)(serverUrl);
      if (info['api'] is! int) throw const FormatException('no api4webtrees');
      trees = (info['trees'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    } on DioException {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = l10n.authErrorServerUnreachable;
        });
      }
      return;
    } catch (_) {
      // Not JSON / not the shape Info returns: some other website, or
      // webtrees without the module.
      if (mounted) {
        setState(() {
          _checking = false;
          _error = l10n.serverErrorNoApi;
        });
      }
      return;
    }

    if (!mounted) return;
    if (trees.isEmpty) {
      setState(() {
        _checking = false;
        _error = l10n.serverErrorNoTrees;
      });
      return;
    }

    // Tree first, server last: on first start, setting the server swaps
    // this screen out for the login screen right away, so nothing after
    // that may depend on this widget still being mounted. The first tree
    // is set even when there are several, so the login screen is
    // consistent even if the picker is backed out of.
    final navigator = Navigator.of(context);
    await ref.read(treeNameProvider.notifier).set(trees.first['name'] as String);
    await ref.read(serverUrlProvider.notifier).set(serverUrl);

    // On first start this screen is the app's root, not pushed: setting the
    // server above already swapped it for the login screen.
    final route = MaterialPageRoute<void>(builder: (_) => TreePickerScreen(trees: trees));
    if (navigator.canPop()) {
      if (trees.length > 1) {
        await navigator.pushReplacement(route);
      } else {
        navigator.pop();
      }
    } else if (trees.length > 1) {
      await navigator.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final firstStart = !Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        title: Text(firstStart ? l10n.welcomeTitle : l10n.serverScreenTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
          child: TabletBoundedBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (firstStart)
                  ..._welcome(l10n)
                else
                  Text(
                    l10n.serverScreenIntro,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 24),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: l10n.serverUrlLabel,
                    hintText: l10n.serverUrlHint,
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _checking ? null : _submit(),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _checking ? null : _submit,
                  child: _checking
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.serverConnectButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _welcome(AppLocalizations l10n) {
    const body = TextStyle(color: AppColors.textSecondary, height: 1.4);
    return [
      Image.asset('assets/images/logo.png', height: 96),
      const SizedBox(height: 24),
      Text(l10n.welcomeWebtrees, style: body),
      const SizedBox(height: 12),
      Text(l10n.welcomeApp, style: body),
      const SizedBox(height: 24),
      Text(
        l10n.welcomeHowToTitle,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(l10n.welcomeHowToLink, style: body),
      const SizedBox(height: 12),
      Text(l10n.welcomeHowToAddress, style: body),
      const SizedBox(height: 12),
      Text(
        l10n.welcomeRequirement,
        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
    ];
  }
}
