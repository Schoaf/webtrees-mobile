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
  const RegisterScreen({super.key, this.registrationTerms});

  /// webtrees' terms for "Request a new user account", as plain text - only
  /// when the site shows them (Info `loginForm.registrationTerms`).
  final String? registrationTerms;

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

  // A field shows its error only once left (focus lost) - not while the
  // person is still typing in it for the first time.
  late final _focus = {
    for (final field in _Field.values) field: FocusNode()..addListener(() => _onFocusChange(field)),
  };
  final _touched = <_Field>{};

  void _onFocusChange(_Field field) {
    if (!_focus[field]!.hasFocus && !_touched.contains(field)) {
      setState(() => _touched.add(field));
    }
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validate(_Field field, AppLocalizations l10n) {
    switch (field) {
      case _Field.realName:
        return _realNameController.text.trim().isEmpty ? l10n.fieldRequired : null;
      case _Field.email:
        final email = _emailController.text.trim();
        if (email.isEmpty) return l10n.fieldRequired;
        return _emailPattern.hasMatch(email) ? null : l10n.invalidEmail;
      case _Field.username:
        return _usernameController.text.trim().isEmpty ? l10n.fieldRequired : null;
      case _Field.password:
        final password = _passwordController.text;
        return password.length >= 8 ? null : l10n.passwordRules;
      case _Field.comments:
        return _commentsController.text.trim().isEmpty ? l10n.fieldRequired : null;
    }
  }

  String? _errorFor(_Field field, AppLocalizations l10n) =>
      _touched.contains(field) ? _validate(field, l10n) : null;

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    _realNameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  bool _canSubmit(AppLocalizations l10n) => _Field.values.every((field) => _validate(field, l10n) == null);

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
        if (widget.registrationTerms != null) ...[
          Text(
            widget.registrationTerms!,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
        ],
        TextField(
          controller: _realNameController,
          focusNode: _focus[_Field.realName],
          decoration: InputDecoration(
            labelText: l10n.fullNameLabel,
            hintText: l10n.fullNameHint,
            errorText: _errorFor(_Field.realName, l10n),
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _emailController,
          focusNode: _focus[_Field.email],
          decoration: InputDecoration(
            labelText: l10n.emailAddressLabel,
            errorText: _errorFor(_Field.email, l10n),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _usernameController,
          focusNode: _focus[_Field.username],
          decoration: InputDecoration(
            labelText: l10n.username,
            errorText: _errorFor(_Field.username, l10n),
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _passwordController,
          focusNode: _focus[_Field.password],
          decoration: InputDecoration(
            labelText: l10n.passwordLabel,
            hintText: l10n.passwordRules,
            errorText: _errorFor(_Field.password, l10n),
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
          focusNode: _focus[_Field.comments],
          decoration: InputDecoration(
            labelText: l10n.registerCommentsLabel,
            hintText: l10n.registerCommentsHint,
            errorText: _errorFor(_Field.comments, l10n),
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
          onPressed: _loading || !_canSubmit(l10n) ? null : _submit,
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
        const SizedBox(height: 12),
        Text(
          l10n.registerApprovalNote,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

enum _Field { realName, email, username, password, comments }
