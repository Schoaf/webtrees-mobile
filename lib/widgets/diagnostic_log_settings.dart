import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/diagnostic_log.dart';

/// The switch for the [DiagnosticLog] and, while it is on, the button that
/// sends it - in "Mein Konto" and on the login screen, since a login that
/// fails is exactly when it's needed.
class DiagnosticLogSettings extends StatefulWidget {
  const DiagnosticLogSettings({super.key, required this.serverUrl});

  /// Named in the log's first line.
  final String serverUrl;

  @override
  State<DiagnosticLogSettings> createState() => _DiagnosticLogSettingsState();
}

class _DiagnosticLogSettingsState extends State<DiagnosticLogSettings> {
  bool _isEnabled = DiagnosticLog.instance.isEnabled;

  Future<void> _setEnabled(bool isEnabled) async {
    await DiagnosticLog.instance.setEnabled(isEnabled);
    if (mounted) setState(() => _isEnabled = isEnabled);
  }

  Future<void> _send(BuildContext buttonContext) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final box = buttonContext.findRenderObject() as RenderBox?;
    final package = await PackageInfo.fromPlatform();
    final header = [
      'webtrees-mobile ${package.version} (${package.buildNumber})',
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Locale ${Platform.localeName}',
      'Server ${widget.serverUrl}',
      'Sent ${DateTime.now().toIso8601String()}',
    ].join('\n');
    final file = await DiagnosticLog.instance.fileToSend(header: header);
    if (file == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.diagnosticLogEmpty)));
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'webtrees-mobile diagnostics',
        // iPad: the share sheet needs a place to point at.
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const Key('diagnosticLogSwitch'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.diagnosticLogTitle, style: const TextStyle(fontSize: 14)),
          subtitle: Text(l10n.diagnosticLogSubtitle, style: const TextStyle(fontSize: 12)),
          value: _isEnabled,
          onChanged: _setEnabled,
        ),
        if (_isEnabled)
          Builder(
            builder: (buttonContext) => TextButton.icon(
              key: const Key('diagnosticLogSend'),
              onPressed: () => _send(buttonContext),
              icon: const Icon(Icons.bug_report_outlined, size: 16),
              label: Text(l10n.diagnosticLogSendButton),
            ),
          ),
      ],
    );
  }
}
