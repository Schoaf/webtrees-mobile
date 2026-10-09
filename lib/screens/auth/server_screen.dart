import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/server_url.dart';
import '../../widgets/linked_text.dart';
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
  _ServerError? _error;

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
    final serverUrl = normalizeServerUrl(_urlController.text);
    if (serverUrl == null) {
      setState(() => _error = _ServerError.invalidUrl);
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    List<Map<String, dynamic>>? trees;
    var reachable = true;
    try {
      final info = await ref.read(serverProbeProvider)(serverUrl);
      if (info['api'] is int) {
        if (isApiTooOld(info)) {
          setState(() {
            _checking = false;
            _error = _ServerError.moduleTooOld;
          });
          return;
        }
        trees = (info['trees'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      }
    } on DioException catch (e) {
      // A response (404 ...) means the site is there, just no Info route.
      reachable = e.response != null;
    } catch (_) {
      // Not JSON / not the shape Info returns.
    }

    _ServerError? error;
    if (trees == null) {
      // Info failed: tell "webtrees without api4webtrees" apart from
      // "not webtrees" / "not reachable" via webtrees' own /ping route.
      final isWebtrees = reachable && await ref.read(webtreesPingProvider)(serverUrl);
      error = isWebtrees
          ? _ServerError.moduleMissing
          : reachable
          ? _ServerError.notWebtrees
          : _ServerError.unreachable;
    } else if (trees.isEmpty) {
      error = _ServerError.noTrees;
    }

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _checking = false;
        _error = error;
      });
      return;
    }
    final foundTrees = trees!;

    // Tree first, server last: on first start, setting the server swaps
    // this screen out for the login screen right away, so nothing after
    // that may depend on this widget still being mounted. The first tree
    // is set even when there are several, so the login screen is
    // consistent even if the picker is backed out of.
    final navigator = Navigator.of(context);
    await ref.read(treeNameProvider.notifier).set(foundTrees.first['name'] as String);
    await ref.read(serverUrlProvider.notifier).set(serverUrl);

    // On first start this screen is the app's root, not pushed: setting the
    // server above already swapped it for the login screen.
    final route = MaterialPageRoute<void>(builder: (_) => TreePickerScreen(trees: foundTrees));
    if (navigator.canPop()) {
      if (foundTrees.length > 1) {
        await navigator.pushReplacement(route);
      } else {
        navigator.pop();
      }
    } else if (foundTrees.length > 1) {
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
                  _welcome(l10n)
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
                  SelectionArea(
                    child: LinkedText(
                      _errorMessage(_error!, l10n),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
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

  String _errorMessage(_ServerError error, AppLocalizations l10n) => switch (error) {
    _ServerError.invalidUrl => l10n.serverErrorInvalidUrl,
    _ServerError.unreachable => l10n.authErrorServerUnreachable,
    _ServerError.notWebtrees => l10n.serverErrorNoApi,
    _ServerError.moduleMissing => l10n.serverErrorModuleMissing,
    _ServerError.moduleTooOld => l10n.serverErrorModuleTooOld(minApiVersionName),
    _ServerError.noTrees => l10n.serverErrorNoTrees,
  };

  // Selectable (copy the module name, the instructions ...), and every
  // "webtrees"/"api4webtrees" links to where it's explained.
  Widget _welcome(AppLocalizations l10n) {
    const body = TextStyle(color: AppColors.textSecondary, height: 1.4);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.asset('assets/images/logo.png', height: 96),
          const SizedBox(height: 24),
          LinkedText(l10n.welcomeWebtrees, style: body),
          const SizedBox(height: 12),
          LinkedText(l10n.welcomeApp, style: body),
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
          LinkedText(
            l10n.welcomeRequirement,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

enum _ServerError { invalidUrl, unreachable, notWebtrees, moduleMissing, moduleTooOld, noTrees }
