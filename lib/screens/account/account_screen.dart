import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/copy_to_clipboard.dart';
import '../../widgets/person_card.dart';
import '../search/person_detail_screen.dart';
import '../search/search_screen.dart';

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

  final _realNameController = TextEditingController();
  Map<String, dynamic>? _pendingStartPerson;
  String? _pendingStartXref;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
      role: _roleLabel(treeInfo['role'] as String?),
      linkedPerson: linkedPerson,
      linkedXref: userXref.isNotEmpty ? userXref : null,
      startPerson: startPerson,
      startXref: defaultXref.isNotEmpty ? defaultXref : null,
    );
  }

  String _roleLabel(String? role) => switch (role) {
    'manager' => 'Verwalter',
    'moderator' => 'Moderator',
    'editor' => 'Bearbeiter',
    'member' => 'Mitglied',
    'visitor' => 'Besucher',
    _ => '—',
  };

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
        builder: (_) => const SearchScreen(pickerTitle: 'Startperson wählen'),
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
        throw Exception(result['error'] ?? 'unbekannter Fehler');
      }
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
        _future = _load();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Änderungen gespeichert.')));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Speichern fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AccountData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Text('Konnte nicht laden: ${snapshot.error}'),
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
                          : const Text('Speichern'),
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
                            _InfoRow(
                              label: 'Benutzername',
                              value: data.userName,
                            ),
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
                                  decoration: const InputDecoration(
                                    labelText: 'Name',
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
                              _InfoRow(label: 'Name', value: data.realName),
                            _InfoRow(
                              label: 'Rolle',
                              value: data.role,
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
                      const Text(
                        'Verknüpfte Person',
                        style: TextStyle(
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
                        const _EmptyNote(
                          text: 'Keine Person mit diesem Konto verknüpft.',
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        'Startperson',
                        style: TextStyle(
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
                                text: 'Keine Startperson festgelegt.',
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
                        const _EmptyNote(text: 'Keine Startperson festgelegt.'),
                      if (_editing) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _pickStartPerson,
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('Startperson ändern'),
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
                          label: const Text('Abmelden'),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(ref.read(serverUrlProvider)),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Zur Website (Vollversion)'),
                        ),
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
          const Expanded(
            child: Text(
              'Mein Konto',
              style: TextStyle(
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
            tooltip: editing ? 'Bearbeiten abbrechen' : 'Bearbeiten',
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
    required this.role,
    required this.linkedPerson,
    required this.linkedXref,
    required this.startPerson,
    required this.startXref,
  });

  final String userName;
  final String realName;
  final String role;
  final Map<String, dynamic>? linkedPerson;
  final String? linkedXref;
  final Map<String, dynamic>? startPerson;
  final String? startXref;
}
