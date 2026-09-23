import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_providers.dart';
import '../theme/app_theme.dart';

/// Lets the user personalize and send the webtrees-contribution-request "please help" email
/// — subject/body are server-rendered (see [WebtreesClient.sendShareRequestEmail]),
/// only the recipient and the free-text personal message come from here.
class AskForHelpEmailScreen extends ConsumerStatefulWidget {
  const AskForHelpEmailScreen({
    super.key,
    required this.tree,
    required this.token,
    required this.subject,
    required this.bodyTemplate,
  });

  final String tree;
  final String token;
  final String subject;

  /// Contains the literal marker `{{PERSONAL_MESSAGE}}` where the personal
  /// message goes — only for the live preview here; the server re-renders
  /// the real email itself from [personalMessage] on send.
  final String bodyTemplate;

  @override
  ConsumerState<AskForHelpEmailScreen> createState() =>
      _AskForHelpEmailScreenState();
}

class _AskForHelpEmailScreenState extends ConsumerState<AskForHelpEmailScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String get _previewBody => widget.bodyTemplate.replaceAll(
    '{{PERSONAL_MESSAGE}}',
    _messageController.text.trim().isEmpty
        ? '(keine persönliche Nachricht)'
        : _messageController.text.trim(),
  );

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Bitte eine gültige E-Mail-Adresse angeben.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final client = ref.read(webtreesClientProvider);
    try {
      final result = await client.sendShareRequestEmail(
        widget.tree,
        token: widget.token,
        recipientEmail: email,
        recipientName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        personalMessage: _messageController.text.trim(),
      );
      if (result['ok'] != true) {
        throw Exception(result['error'] ?? 'unbekannter Fehler');
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Senden fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Per E-Mail senden',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-Mail-Adresse',
                hintText: 'oma@beispiel.at',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Persönliche Nachricht (optional)',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Vorschau',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.subject,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(_previewBody),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Senden'),
            ),
          ],
        ),
      ),
    );
  }
}
