import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tablet_bounded_body.dart';

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
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _loadTreeTitle();
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

    try {
      final info = await client.info(tree);
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
                      const SizedBox(height: 40),
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
                      const SizedBox(height: 24),
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
                      const SizedBox(height: 56),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () => launchUrl(
                              siteUrl(ref.read(serverUrlProvider), mobile: false),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(l10n.viewFamilyTreeButton),
                          ),
                          TextButton(
                            onPressed: () => launchUrl(
                              siteUrl(privacyPolicyUrl(ref), mobile: true),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(l10n.privacyPolicy),
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
