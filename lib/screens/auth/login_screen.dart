import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/html_text.dart';
import '../../widgets/tablet_bounded_body.dart';
import 'register_screen.dart';
import 'server_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  AuthError? _error;
  String? _treeTitle;
  // From Info `login` - webtrees' own login-page settings. Until known (or
  // if Info fails), registration stays offered; the server still refuses
  // it if disabled.
  String? _welcome;
  bool _registrationAllowed = true;
  String? _registerTerms;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    // After the first frame: needs the context's locale for the texts' language.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTreeTitle());
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  // Best-effort only: just for the "welcome to <tree>" subtitle under the
  // logo, so any failure (offline, unreachable server) is silently ignored
  // rather than blocking the login form itself.
  Future<void> _loadTreeTitle() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final lang = Localizations.localeOf(context).languageCode;

    try {
      final info = await client.info(tree, lang: lang);
      final login = info['login'] as Map<String, dynamic>?;
      if (mounted && login != null) {
        final welcome = htmlToPlainText(login['welcome'] as String? ?? '');
        final terms = login['terms'] as String?;
        setState(() {
          _welcome = welcome.isEmpty ? null : welcome;
          _registrationAllowed = login['registration'] as bool? ?? true;
          _registerTerms = terms == null ? null : htmlToPlainText(terms);
        });
      }
      final trees = (info['trees'] as List<dynamic>?) ?? const [];
      Map<String, dynamic>? match;
      for (final t in trees.cast<Map<String, dynamic>>()) {
        if (t['name'] == tree) {
          match = t;
          break;
        }
      }
      final title = match?['title'] as String?;
      if (mounted && title != null && title.isNotEmpty) {
        setState(() => _treeTitle = title);
      }
    } catch (_) {
      // Ignored - see comment above.
    }
  }

  Future<void> _changeServer() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ServerScreen()),
    );
    if (!mounted) return;
    setState(() {
      _treeTitle = null;
      _error = null;
    });
    _loadTreeTitle();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await ref
        .read(authControllerProvider.notifier)
        .login(_usernameController.text.trim(), _passwordController.text);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 56, 32, 24),
              child: TabletBoundedBody(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 80,
                  ),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        width: 220,
                        fit: BoxFit.contain,
                      ),
                      if (_treeTitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _treeTitle!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                      if (_welcome != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _welcome!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              l10n.serverLabel(
                                Uri.parse(ref.watch(serverUrlProvider)).host,
                              ),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _changeServer,
                            child: Text(l10n.changeServerButton),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(labelText: l10n.username),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: l10n.passwordLabel,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                          ),
                        ),
                        obscureText: !_passwordVisible,
                        onSubmitted: (_) => _submit(),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => launchUrl(
                            siteUrl(passwordRequestUrl(ref), mobile: true),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Text(l10n.forgotPasswordLink),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_error != null) ...[
                        Text(
                          _error!.message(l10n),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(l10n.loginButton),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_registrationAllowed)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  RegisterScreen(terms: _registerTerms),
                            ),
                          ),
                          child: Text(
                            l10n.registerLink,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      const SizedBox(height: 48),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              siteUrl(ref.read(serverUrlProvider), mobile: false),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(l10n.openFullWebsite),
                          ),
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              siteUrl(privacyPolicyUrl(ref), mobile: true),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(
                              Icons.privacy_tip_outlined,
                              size: 16,
                            ),
                            label: Text(l10n.privacyPolicy),
                          ),
                        ],
                      ),
                      if (_appVersion != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.appVersion(_appVersion!),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
