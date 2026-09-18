import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/person_card.dart';
import '../search/person_detail_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _future = _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: FutureBuilder<_AccountData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Konnte nicht laden: ${snapshot.error}'),
                    );
                  }

                  final data = snapshot.data!;
                  return ListView(
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
                            _InfoRow(label: 'Name', value: data.realName),
                            _InfoRow(
                              label: 'Rolle',
                              value: data.role,
                              last: true,
                            ),
                          ],
                        ),
                      ),
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
                      if (data.startPerson != null && data.startXref != null)
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
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

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
          const Text(
            'Mein Konto',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
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
    return Container(
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
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
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
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
