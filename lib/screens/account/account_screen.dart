import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/copy_to_clipboard.dart';
import '../../widgets/person_card.dart';
import '../search/person_detail_screen.dart';
import '../search/search_screen.dart';

/// The server's raw role string (stable, not display text); see
/// [_roleLabel] for the localized text shown for each. Kept off the
/// data-loading path (`_AccountScreenState._load`, which runs before the
/// first build and has no reliable [AppLocalizations] yet) and resolved at
/// display time in `build()` instead, which always has one.
String _roleLabel(AppLocalizations l10n, String? role) => switch (role) {
  'manager' => l10n.roleManager,
  'moderator' => l10n.roleModerator,
  'editor' => l10n.roleEditor,
  'member' => l10n.roleMember,
  'visitor' => l10n.roleVisitor,
  _ => '—',
};

/// "Mein Konto" — the webtrees account itself: username/name/role, which
/// person record it's linked to, and which person is the tree's
/// Startperson. Distinct from any one person's own detail page.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late Future<_AccountData> _future;
  bool _editing = false;
  bool _saving = false;
  String? _saveError;
  String? _appVersion;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;

  final _realNameController = TextEditingController();
  Map<String, dynamic>? _pendingStartPerson;
  String? _pendingStartXref;

  @override
  void initState() {
    super.initState();
    _future = _load();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final biometrics = ref.read(biometricAuthProvider);
    final supported = await biometrics.isDeviceSupported();
    final enabled = supported && await biometrics.isEnabled();
    if (mounted) {
      setState(() {
        _biometricSupported = supported;
        _biometricEnabled = enabled;
      });
    }
  }

  @override
  void dispose() {
    _realNameController.dispose();
    super.dispose();
  }

  Future<_AccountData> _load() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final info = await client.info(tree);
    final user = info['user'] as Map<String, dynamic>;
    final treeInfo = (info['trees'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((t) => t['name'] == tree, orElse: () => const {});

    final userXref = treeInfo['userXref'] as String? ?? '';
    final defaultXref = treeInfo['defaultXref'] as String? ?? '';

    Map<String, dynamic>? linkedPerson;
    if (userXref.isNotEmpty) {
      linkedPerson =
          (await client.individual(tree, userXref))['person']
              as Map<String, dynamic>?;
    }

    Map<String, dynamic>? startPerson;
    if (defaultXref.isNotEmpty) {
      startPerson = defaultXref == userXref
          ? linkedPerson
          : (await client.individual(tree, defaultXref))['person']
                as Map<String, dynamic>?;
    }

    return _AccountData(
      userName: user['userName'] as String? ?? '',
      realName: user['realName'] as String? ?? '',
      roleKey: treeInfo['role'] as String?,
      linkedPerson: linkedPerson,
      linkedXref: userXref.isNotEmpty ? userXref : null,
      startPerson: startPerson,
      startXref: defaultXref.isNotEmpty ? defaultXref : null,
    );
  }

  void _startEditing(_AccountData data) {
    setState(() {
      _editing = true;
      _saveError = null;
      _realNameController.text = data.realName;
      _pendingStartPerson = data.startPerson;
      _pendingStartXref = data.startXref;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _saveError = null;
    });
  }

  Future<void> _pickStartPerson() async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          pickerTitle: AppLocalizations.of(context)!.chooseStartPersonTitle,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pendingStartPerson = picked;
      _pendingStartXref = picked['xref'] as String?;
    });
  }

  Future<void> _save(_AccountData original) async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final l10n = AppLocalizations.of(context)!;

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final realName = _realNameController.text.trim();
    try {
      final result = await client.updateAccount(
        tree,
        realName: realName != original.realName ? realName : null,
        defaultXref: _pendingStartXref != original.startXref
            ? (_pendingStartXref ?? '')
            : null,
      );
      if (result['ok'] != true) {
        throw Exception(result['error'] ?? l10n.unknownError);
      }
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
        _future = _load();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.changesSaved)));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = l10n.saveFailedError('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AccountData>(
      future: _future,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context)!;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Text(l10n.couldNotLoad('${snapshot.error}')),
              ),
            ),
          );
        }

        final data = snapshot.data!;
        return Scaffold(
          bottomNavigationBar: _editing
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(data),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.save),
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(
                  editing: _editing,
                  onBack: () => Navigator.of(context).maybePop(),
                  onEditToggle: _editing
                      ? _cancelEditing
                      : () => _startEditing(data),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          children: [
                            _InfoRow(label: l10n.username, value: data.userName),
                            if (_editing)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.divider,
                                    ),
                                  ),
                                ),
                                child: TextField(
                                  controller: _realNameController,
                                  decoration: InputDecoration(
                                    labelText: l10n.nameLabel,
                                    isDense: true,
                                    border: InputBorder.none,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              )
                            else
                              _InfoRow(label: l10n.nameLabel, value: data.realName),
                            _InfoRow(
                              label: l10n.role,
                              value: _roleLabel(l10n, data.roleKey),
                              last: true,
                            ),
                          ],
                        ),
                      ),
                      if (_saveError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _saveError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        l10n.linkedPersonSectionTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (data.linkedPerson != null && data.linkedXref != null)
                        PersonCard(
                          person: data.linkedPerson!,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PersonDetailScreen(xref: data.linkedXref!),
                            ),
                          ),
                        )
                      else
                        _EmptyNote(text: l10n.noLinkedPersonMessage),
                      const SizedBox(height: 24),
                      Text(
                        l10n.startPerson,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_editing)
                        _pendingStartPerson != null
                            ? PersonCard(
                                person: _pendingStartPerson!,
                                onTap: _pickStartPerson,
                              )
                            : _EmptyNote(
                                text: l10n.noStartPersonMessage,
                                onTap: _pickStartPerson,
                              )
                      else if (data.startPerson != null &&
                          data.startXref != null)
                        PersonCard(
                          person: data.startPerson!,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PersonDetailScreen(xref: data.startXref!),
                            ),
                          ),
                        )
                      else
                        _EmptyNote(text: l10n.noStartPersonMessage),
                      if (_editing) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _pickStartPerson,
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: Text(l10n.changeStartPersonButton),
                        ),
                      ],
                      if (!_editing) ...[
                        const SizedBox(height: 32),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ref
                                .read(authControllerProvider.notifier)
                                .logout();
                            // Logging out swaps what the root of the app
                            // shows (Home -> Login), but that root sits
                            // *below* this pushed screen in the Navigator
                            // stack — without popping back to it, this
                            // screen just keeps showing until the next
                            // navigation happens to reveal the swap.
                            if (context.mounted) {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            }
                          },
                          icon: const Icon(Icons.logout, size: 18),
                          label: Text(l10n.logoutButton),
                        ),
                        if (_biometricSupported) ...[
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              l10n.lockWithBiometricsTitle,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              l10n.biometricsSubtitle,
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: _biometricEnabled,
                            onChanged: (value) async {
                              await ref
                                  .read(biometricAuthProvider)
                                  .setEnabled(value);
                              if (mounted) {
                                setState(() => _biometricEnabled = value);
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(ref.read(serverUrlProvider)),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(l10n.openFullWebsite),
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(privacyPolicyUrl(ref)),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                          label: Text(l10n.privacyPolicy),
                        ),
                        if (_appVersion != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.appVersion(_appVersion!),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.editing,
    required this.onEditToggle,
  });

  final VoidCallback onBack;
  final bool editing;
  final VoidCallback onEditToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.myAccountTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onEditToggle,
            icon: Icon(
              editing ? Icons.close : Icons.edit_outlined,
              color: AppColors.textPrimary,
            ),
            tooltip: editing
                ? AppLocalizations.of(context)!.cancelEditing
                : AppLocalizations.of(context)!.edit,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => copyToClipboard(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
            ),
            Flexible(
              child: Text(
                value.isEmpty ? '—' : value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountData {
  const _AccountData({
    required this.userName,
    required this.realName,
    required this.roleKey,
    required this.linkedPerson,
    required this.linkedXref,
    required this.startPerson,
    required this.startXref,
  });

  final String userName;
  final String realName;

  /// The server's raw role string ('manager', 'editor', ...); see
  /// [_roleLabel] for the localized display text.
  final String? roleKey;
  final Map<String, dynamic>? linkedPerson;
  final String? linkedXref;
  final Map<String, dynamic>? startPerson;
  final String? startXref;
}
