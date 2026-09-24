import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../repositories/quick_note_store.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/gedcom.dart';
import '../../widgets/person_card.dart';
import '../../widgets/tablet_bounded_body.dart';
import '../account/account_screen.dart';
import '../responses/responses_list_screen.dart';
import '../search/person_detail_screen.dart';
import '../search/search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final info = await client.info(tree);
    final treeInfo = (info['trees'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((t) => t['name'] == tree, orElse: () => const {});

    Map<String, dynamic>? startPerson;
    final defaultXref = treeInfo['defaultXref'] as String? ?? '';
    final userXref = treeInfo['userXref'] as String? ?? '';
    final xref = defaultXref.isNotEmpty ? defaultXref : userXref;
    if (xref.isNotEmpty) {
      final individual = await client.individual(tree, xref);
      startPerson = individual['person'] as Map<String, dynamic>?;
    }

    // "Mein Konto" — the person record linked to this webtrees account,
    // distinct from the tree's Startperson (defaultXref): shown as the
    // header avatar and opened by tapping it.
    Map<String, dynamic>? linkedPerson;
    if (userXref.isNotEmpty) {
      linkedPerson = userXref == xref
          ? startPerson
          : (await client.individual(tree, userXref))['person']
                as Map<String, dynamic>?;
    }

    final anniversaries = await client.anniversaries(tree, days: 7);
    final birthdaysThisWeek = (anniversaries['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((event) {
          final person = event['person'] as Map<String, dynamic>?;
          return event['tag'] == 'BIRT' &&
              person != null &&
              person['isDead'] != true;
        })
        .toList();

    int unreadResponses;
    try {
      unreadResponses = await client.shareRequestUnreadCount(tree);
    } catch (_) {
      // webtrees-contribution-request may not be installed/enabled - don't let that break
      // the rest of the home screen.
      unreadResponses = 0;
    }

    return _HomeData(
      treeTitle: treeInfo['title'] as String? ?? 'Stammbaum',
      individualCount: treeInfo['individuals'] as int? ?? 0,
      startPerson: startPerson,
      realName:
          (info['user'] as Map<String, dynamic>)['realName'] as String? ?? '',
      birthdaysThisWeek: birthdaysThisWeek,
      linkedXref: userXref.isNotEmpty ? userXref : null,
      linkedPhotoUrl: linkedPerson?['thumb'] as String?,
      unreadResponses: unreadResponses,
    );
  }

  String _birthdaySubtitle(AppLocalizations l10n, Map<String, dynamic> event) {
    final years = event['years'] as int?;
    final inDays = event['inDays'] as int? ?? 0;
    final weekdays = [
      l10n.weekdayMonday,
      l10n.weekdayTuesday,
      l10n.weekdayWednesday,
      l10n.weekdayThursday,
      l10n.weekdayFriday,
      l10n.weekdaySaturday,
      l10n.weekdaySunday,
    ];
    final when = switch (inDays) {
      0 => l10n.today,
      1 => l10n.tomorrow,
      _ => l10n.onWeekdayName(
        weekdays[DateTime.now().add(Duration(days: inDays)).weekday - 1],
      ),
    };
    return years == null ? when : l10n.turningYears(years, when);
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(l10n.couldNotLoad('${snapshot.error}')),
              );
            }

            final data = snapshot.data!;
            return TabletBoundedBody(
              child: Column(
                children: [
                  _Header(
                    title: data.treeTitle,
                    initials: _initials(data.realName),
                    photoUrl: data.linkedPhotoUrl,
                    photoHeaders: ref.read(webtreesClientProvider).imageHeaders,
                    onTap: () async {
                      // Mein Konto can change the linked photo/name or the
                      // Startperson shown below — without this, Home kept
                      // showing whatever it loaded at app start until a
                      // restart, since it's kept alive in the tab IndexedStack
                      // and never reloads on its own.
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountScreen(),
                        ),
                      );
                      if (mounted) setState(() => _future = _load());
                    },
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      children: [
                        _SearchEntryButton(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SearchScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (data.startPerson != null) ...[
                          Text(
                            l10n.startPerson,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          PersonCard(
                            person: data.startPerson!,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PersonDetailScreen(
                                  xref: data.startPerson!['xref'] as String,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (data.unreadResponses > 0) ...[
                          const SizedBox(height: 26),
                          Row(
                            children: [
                              const Icon(
                                Icons.mark_email_unread_outlined,
                                size: 17,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.responsesTitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _ResponsesCard(count: data.unreadResponses),
                        ],
                        if (data.birthdaysThisWeek.isNotEmpty) ...[
                          const SizedBox(height: 26),
                          Row(
                            children: [
                              const Icon(
                                Icons.cake_outlined,
                                size: 17,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.birthdaysThisWeek,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _BirthdayList(
                            events: data.birthdaysThisWeek,
                            subtitle: (event) =>
                                _birthdaySubtitle(l10n, event),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const _UnsyncedNotes(),
                        const SizedBox(height: 18),
                        Column(
                          children: [
                            Text(
                              l10n.individualsInTree(data.individualCount),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(ref.read(serverUrlProvider)),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: Text(l10n.openFullWebsite),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.initials,
    this.photoUrl,
    this.photoHeaders,
    this.onTap,
  });

  final String title;
  final String initials;
  final String? photoUrl;
  final Map<String, String>? photoHeaders;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: ClipOval(
              child: Container(
                width: 40,
                height: 40,
                color: AppColors.primary.withValues(alpha: 0.14),
                alignment: Alignment.center,
                child: hasPhoto
                    ? Image.network(
                        photoUrl!,
                        headers: photoHeaders,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEntryButton extends StatelessWidget {
  const _SearchEntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)!.searchPersonHint,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Birthdays shown as a plain list embedded in one bordered block — not as
/// individual button/card rows like search results — so it reads as one
/// grouped piece of information rather than a stack of tappable buttons.
/// Rows are still tappable through to the person's detail page.
class _BirthdayList extends StatelessWidget {
  const _BirthdayList({required this.events, required this.subtitle});

  final List<Map<String, dynamic>> events;
  final String Function(Map<String, dynamic>) subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        // Without this, each row (an InkWell/Container shrink-wrapped to its
        // own text) gets centered in the card by Column's default alignment
        // instead of stretching so the text can sit at the left edge.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < events.length; i++)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PersonDetailScreen(
                      xref:
                          (events[i]['person'] as Map<String, dynamic>)['xref']
                              as String,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: i < events.length - 1
                        ? const Border(
                            bottom: BorderSide(color: AppColors.divider),
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stripNameSlashes(
                          (events[i]['person'] as Map<String, dynamic>)['name']
                                  as String? ??
                              '',
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle(events[i]),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Summary card for unreviewed "ask a relative" answers (see webtrees-contribution-request)
/// — same card styling as [_BirthdayList], sized like a single person row,
/// per Andreas's request to make it as prominent as the birthdays card.
/// There's no native in-app review screen yet, so tapping it opens the
/// review list on the website instead, same pattern as "Zur Website".
class _ResponsesCard extends ConsumerWidget {
  const _ResponsesCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ResponsesListScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.responsesReceivedTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.requestsPendingReview(count),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.treeTitle,
    required this.individualCount,
    required this.startPerson,
    required this.realName,
    required this.birthdaysThisWeek,
    required this.linkedXref,
    required this.linkedPhotoUrl,
    required this.unreadResponses,
  });

  final String treeTitle;
  final int individualCount;
  final Map<String, dynamic>? startPerson;
  final String realName;

  /// Living individuals with a birthday in the next 7 days, soonest first
  /// (each entry is one Anniversaries event: {person, years, inDays, ...}).
  final List<Map<String, dynamic>> birthdaysThisWeek;

  /// The account's own linked person ("Mein Konto"), if any — distinct from
  /// [startPerson] (the tree's Startperson).
  final String? linkedXref;
  final String? linkedPhotoUrl;

  /// How many "ask a relative" requests (see webtrees-contribution-request) have an answer
  /// this account hasn't reviewed yet.
  final int unreadResponses;
}

class _UnsyncedNotes extends ConsumerWidget {
  const _UnsyncedNotes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(quickNoteStoreProvider);
    return FutureBuilder<List<QuickNote>>(
      future: store.unsynced(),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const [];
        if (notes.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.notSynced(notes.length),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final note in notes) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: note.xref == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PersonDetailScreen(xref: note.xref!),
                          ),
                        ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.personGuess,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          note.text,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
