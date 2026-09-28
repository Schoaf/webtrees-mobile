import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tablet_bounded_body.dart';

/// Requests a new account without leaving the app (webtrees' own web
/// registration form still governs what happens next: an email
/// confirmation, then an administrator's approval — this screen only
/// replaces the browser hand-off, not that review step).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _realNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _commentsController = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  bool _done = false;
  RegisterError? _error;

  @override
  void dispose() {
    _realNameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _realNameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _usernameController.text.trim().isNotEmpty &&
      _passwordController.text.length >= 8 &&
      _commentsController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await ref
        .read(authControllerProvider.notifier)
        .register(
          realName: _realNameController.text.trim(),
          email: _emailController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          comments: _commentsController.text.trim(),
        );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
      _done = error == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.registerTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
          child: TabletBoundedBody(
            child: _done ? _buildSuccess(l10n) : _buildForm(l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.mark_email_read_outlined,
          size: 56,
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.registerSuccessTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.registerSuccessMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.backToLoginButton),
        ),
      ],
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _realNameController,
          decoration: InputDecoration(labelText: l10n.nameLabel),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(labelText: l10n.emailAddressLabel),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(labelText: l10n.username),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
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
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
          ),
          obscureText: !_passwordVisible,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _commentsController,
          decoration: InputDecoration(
            labelText: l10n.registerCommentsLabel,
            hintText: l10n.registerCommentsHint,
          ),
          maxLines: 4,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (_error != null) ...[
          Text(
            _error!.message(l10n),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: _loading || !_canSubmit ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(l10n.registerSubmitButton),
        ),
      ],
    );
  }
}
