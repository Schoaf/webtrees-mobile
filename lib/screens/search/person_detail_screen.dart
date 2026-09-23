import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/copy_to_clipboard.dart';
import '../../utils/gedcom.dart';
import '../../utils/server_error.dart';
import '../../widgets/add_fact_sheet.dart';
import '../../widgets/ask_for_help_email_screen.dart';
import '../../widgets/gedcom_date_field.dart';
import '../../widgets/person_avatar.dart';
import '../../widgets/person_card.dart';
import '../../widgets/place_autocomplete_field.dart';
import '../tree_view/tree_view_screen.dart';

/// Facts always shown; everything else is collapsed under "Mehr anzeigen"
/// so the record-metadata clutter (reference numbers, last-changed, ...)
/// doesn't crowd out the facts someone actually came here to read. NAME
/// isn't listed here at all — it's never shown in the read-only card (it's
/// already up top next to the photo), only as editable fields in edit mode.
const _primaryFactTags = {'SEX', 'BIRT', 'DEAT'};

/// Desired display/edit order for a person's facts, top to bottom.
///
/// This is the single place to change field order — edit the list below and
/// both the read-only facts card and the edit form pick it up automatically.
/// Any tag not listed here keeps its server-given order, appended after the
/// ones listed.
///
/// NOTE: "Aktualisiert am" (the GEDCOM CHAN / last-changed tag) isn't in
/// this list because the webtreesand-api module strips it out server-side
/// (its SKIP_FACTS list) — it currently can't be fetched via this API at
/// all, so there's nothing to display yet even though it's on the wishlist.
const kFactDisplayOrder = ['BIRT', 'DEAT', 'SEX', 'TITL', 'RESI', 'REFN'];

int _factOrderIndex(String tag) {
  final i = kFactDisplayOrder.indexOf(tag);
  return i == -1 ? kFactDisplayOrder.length : i;
}

/// Sorts facts by [kFactDisplayOrder], keeping the server's original
/// relative order for anything that ties (same explicit order, or both
/// unlisted).
List<Map<String, dynamic>> _sortedByFieldOrder(
  List<Map<String, dynamic>> facts,
) {
  final indexed = facts.asMap().entries.toList()
    ..sort((a, b) {
      final ai = _factOrderIndex(a.value['tag'] as String);
      final bi = _factOrderIndex(b.value['tag'] as String);
      if (ai != bi) return ai.compareTo(bi);
      return a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// A fact's value as plain text — the date/value plus the place, joined —
/// used both for tap-to-copy and for the "Daten teilen" text summary.
String _factCopyText(Map<String, dynamic> fact) {
  final parts = <String>[];
  final value = fact['value'] as String? ?? '';
  if (value.isNotEmpty) parts.add(value);
  final date = fact['date'] as Map<String, dynamic>?;
  if (date != null) parts.add(date['text'] as String);
  final place = fact['place'] as Map<String, dynamic>?;
  if (place != null) parts.add(place['short'] as String);
  return parts.isEmpty ? '—' : parts.join(' · ');
}

enum _ShareChoice { link, data }

enum _AskForHelpChoice { copyLink, shareLink, email }

/// Julian Day Number for a Gregorian calendar date (Fliegel & Van Flandern).
int _julianDayNumber(DateTime date) {
  final a = (14 - date.month) ~/ 12;
  final y = date.year + 4800 - a;
  final m = date.month + 12 * a - 3;
  return date.day +
      ((153 * m + 2) ~/ 5) +
      365 * y +
      (y ~/ 4) -
      (y ~/ 100) +
      (y ~/ 400) -
      32045;
}

int? _ageInYears(num? birthJd) {
  if (birthJd == null) return null;
  final days = _julianDayNumber(DateTime.now()) - birthJd.toInt();
  if (days < 0) return null;
  return (days / 365.2425).floor();
}

/// Full "review everything we know" view for one person — priority-2 in the
/// project plan — plus the fast fact-capture entry point (priority-1),
/// since every fact needs a person anyway.
class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({super.key, required this.xref, this.depth = 0});

  final String xref;

  /// How many Person Detail screens deep this one is, counting from the
  /// last non-Person screen (Home/Suche). Person -> Person navigation via
  /// parents/spouse/children pushes another screen each time, so the back
  /// stack grows; once it's deep enough that "back to Home" stops being a
  /// single tap, we show a floating Home shortcut instead of making people
  /// hunt for the back button.
  final int depth;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _editing = false;
  GlobalKey<_EditFactsSectionState> _editKey =
      GlobalKey<_EditFactsSectionState>();
  final _savingNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _savingNotifier.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    return client.individual(tree, widget.xref);
  }

  void _toggleEditing() {
    setState(() {
      _editing = !_editing;
      if (_editing) _editKey = GlobalKey<_EditFactsSectionState>();
    });
  }

  void _onEditSaved() {
    setState(() {
      _editing = false;
      _future = _load();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Änderungen gespeichert — wartet ggf. auf Freigabe.'),
      ),
    );
  }

  void _goHome() {
    ref.read(selectedTabProvider.notifier).select(0);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Both FABs live in the same Positioned row (in the body, sized to the
  /// available width minus its side insets) so they always sit at the same
  /// height. This is a plain Stack child, not Scaffold's floatingActionButton
  /// slot — that slot runs its own built-in appear/disappear animation
  /// (a fade+scale on top of whatever floatingActionButtonAnimator does,
  /// not something that can be turned off through it) which is exactly the
  /// "fly in" every fact/home button did; a Stack child has no such
  /// animation, so it's simply there or not.
  Widget? _buildFabs({required bool canEdit, required String name}) {
    final showHome = widget.depth >= 2;
    final showAddFact = canEdit;
    if (!showHome && !showAddFact) return null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (showHome)
          FloatingActionButton(
            heroTag: 'homeFab_${widget.xref}',
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            onPressed: _goHome,
            tooltip: 'Zum Start',
            child: const Icon(Icons.home),
          )
        else
          const SizedBox.shrink(),
        if (showAddFact)
          FloatingActionButton.extended(
            heroTag: 'addFactFab_${widget.xref}',
            onPressed: () => _openAddFact(name),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.bolt),
            label: const Text('Fakt hinzufügen'),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _openAddFact(String name) async {
    final result = await showModalBottomSheet<AddFactResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddFactSheet(xref: widget.xref, personName: name),
    );
    if (!mounted || result == null) return;

    switch (result) {
      case AddFactResult.posted:
        setState(() => _future = _load());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fakt gespeichert — wartet ggf. auf Freigabe.'),
          ),
        );
      case AddFactResult.savedLocally:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Server nicht erreichbar — lokal gespeichert, später synchronisieren.",
            ),
          ),
        );
      case AddFactResult.cancelled:
        break;
    }
  }

  void _openPhotoViewer(String url) {
    final headers = ref.read(webtreesClientProvider).imageHeaders;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url, headers: headers),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Aus Fotos wählen'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Foto aufnehmen'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final result = await client.postMedia(
        tree,
        widget.xref,
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      if (result['ok'] == true) {
        setState(() => _future = _load());
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Foto hochgeladen.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Abgelehnt: ${result['error']}')),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload fehlgeschlagen: $e')));
    }
  }

  Future<void> _openShareMenu({
    required Map<String, dynamic> person,
    required List<Map<String, dynamic>> facts,
  }) async {
    final choice = await showModalBottomSheet<_ShareChoice>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Per Link teilen'),
              onTap: () => Navigator.of(context).pop(_ShareChoice.link),
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Daten teilen'),
              onTap: () => Navigator.of(context).pop(_ShareChoice.data),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _ShareChoice.data:
        await SharePlus.instance.share(
          ShareParams(
            text: _buildShareText(person: person, facts: facts),
          ),
        );
      case _ShareChoice.link:
        await SharePlus.instance.share(ShareParams(uri: _personUrl()));
    }
  }

  /// Creates a webtrees-share request for this person, then lets the user
  /// copy/share the link or send it by email. Distinct from [_openShareMenu]:
  /// this link needs no webtrees login at all and is meant for a relative
  /// who'll never have an account, not someone who already does.
  /// Errors here can be webtrees' own fatal-error HTML page — long, and
  /// worth being able to read/select in full — so a dialog instead of the
  /// usual one-line SnackBar.
  void _showServerErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anfrage fehlgeschlagen'),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAskForHelp(String name) async {
    final tree = ref.read(treeNameProvider);
    final client = ref.read(webtreesClientProvider);

    final Map<String, dynamic> request;
    try {
      request = await client.createShareRequest(tree, widget.xref);
    } on Exception catch (e) {
      if (!mounted) return;
      _showServerErrorDialog(describeServerError(e));
      return;
    }
    if (!mounted) return;
    if (request['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anfrage fehlgeschlagen: ${request['error']}')),
      );
      return;
    }

    final url = request['url'] as String;
    final token = Uri.parse(url).queryParameters['token'] ?? '';

    final choice = await showModalBottomSheet<_AskForHelpChoice>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Link gültig für 2 Tage — kein Konto nötig',
                  style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Link kopieren'),
              subtitle: const Text(
                'Link in die Zwischenablage kopieren, um ihn selbst zu verschicken',
              ),
              onTap: () =>
                  Navigator.of(context).pop(_AskForHelpChoice.copyLink),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Teilen'),
              subtitle: const Text(
                'Über eine andere App teilen, z. B. WhatsApp oder Nachrichten',
              ),
              onTap: () =>
                  Navigator.of(context).pop(_AskForHelpChoice.shareLink),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Per E-Mail senden'),
              subtitle: const Text(
                'Direkt aus der App eine E-Mail mit dem Link verschicken',
              ),
              onTap: () => Navigator.of(context).pop(_AskForHelpChoice.email),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _AskForHelpChoice.copyLink:
        copyToClipboard(url);
      case _AskForHelpChoice.shareLink:
        await SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
      case _AskForHelpChoice.email:
        await _openEmailComposer(tree: tree, token: token);
    }
  }

  Future<void> _openEmailComposer({
    required String tree,
    required String token,
  }) async {
    final client = ref.read(webtreesClientProvider);
    final Map<String, dynamic> template;
    try {
      template = await client.shareRequestEmailTemplate(tree, token);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte E-Mail-Vorlage nicht laden: $e')),
      );
      return;
    }
    if (!mounted) return;

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AskForHelpEmailScreen(
          tree: tree,
          token: token,
          subject: template['subject'] as String? ?? '',
          bodyTemplate: template['body'] as String? ?? '',
        ),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('E-Mail gesendet.')));
    }
  }

  /// The person's normal webtrees page — a plain link, not the temporary,
  /// login-free webtrees-share link from [_openAskForHelp]. Whoever opens it
  /// needs their own webtrees login, same as visiting the site directly; if
  /// they have the app installed, Universal/App Links open it there instead
  /// of a browser (see AASA/assetlinks.json).
  Uri _personUrl() {
    final server = ref.read(serverUrlProvider);
    final tree = ref.read(treeNameProvider);
    return Uri.parse(server).replace(
      path: '/index.php',
      queryParameters: {'route': '/tree/$tree/individual/${widget.xref}'},
    );
  }

  /// A plain-text summary of a person's facts for the system share sheet —
  /// everything shown in the read-only facts card, skipping REFN (the
  /// record ID — a system/bookkeeping field, not something to share).
  String _buildShareText({
    required Map<String, dynamic> person,
    required List<Map<String, dynamic>> facts,
  }) {
    final name = stripNameSlashes(person['name'] as String? ?? '');
    final shown = _sortedByFieldOrder(
      facts.where((f) => f['tag'] != 'NAME' && f['tag'] != 'REFN').toList(),
    );
    final lines = [
      name,
      for (final fact in shown)
        '${fact['label'] as String? ?? fact['tag']}: ${_factCopyText(fact)}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
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
        if (data['ok'] == false) {
          return Scaffold(
            body: SafeArea(
              child: Center(child: Text('Kein Zugriff: ${data['error']}')),
            ),
          );
        }

        final person = data['person'] as Map<String, dynamic>;
        final name = person['name'] as String? ?? '(kein Name)';
        final facts = (data['facts'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final parentFamilies = (data['parentFamilies'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final spouseFamilies = (data['spouseFamilies'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final media = (data['media'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final canEdit = data['canEdit'] as bool? ?? false;
        final photoUrl = person['thumb'] as String?;
        final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

        final fab = _editing ? null : _buildFabs(canEdit: canEdit, name: name);

        return Scaffold(
          bottomNavigationBar: _editing
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _savingNotifier,
                      builder: (context, saving, _) => FilledButton(
                        onPressed: saving
                            ? null
                            : () => _editKey.currentState?.save(),
                        child: saving
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
                  ),
                )
              : null,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _Header(
                      name: name,
                      editing: _editing,
                      onEditToggle: canEdit ? _toggleEditing : null,
                      onShare: _editing
                          ? null
                          : () => _openShareMenu(person: person, facts: facts),
                      onAskForHelp: (_editing || !canEdit)
                          ? null
                          : () => _openAskForHelp(name),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    PersonAvatar(
                                      sex: person['sex'] as String? ?? 'U',
                                      isDead: person['isDead'] as bool? ?? false,
                                      size: 84,
                                      photoUrl: photoUrl,
                                      photoHeaders: ref
                                          .read(webtreesClientProvider)
                                          .imageHeaders,
                                      editable: _editing && canEdit,
                                      onTap: _editing
                                          ? (canEdit ? _pickAndUploadPhoto : null)
                                          : (hasPhoto
                                                ? () => _openPhotoViewer(
                                                    media.isNotEmpty
                                                        ? (media.first['file']
                                                                  as String? ??
                                                              photoUrl)
                                                        : photoUrl,
                                                  )
                                                : (canEdit
                                                      ? _pickAndUploadPhoto
                                                      : null)),
                                    ),
                                    if (!_editing)
                                      Positioned(
                                        left: -52,
                                        child: _TreeViewButton(
                                          onTap: () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  TreeViewScreen(xref: widget.xref),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  stripNameSlashes(name),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (_lifespanText(person).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _lifespanText(person),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!_editing && facts.isNotEmpty)
                            _FactsCard(facts: facts),
                          if (_editing)
                            _EditFactsSection(
                              key: _editKey,
                              xref: widget.xref,
                              facts: facts,
                              savingNotifier: _savingNotifier,
                              onSaved: _onEditSaved,
                            ),
                          for (final family in parentFamilies) ...[
                            if (family['husband'] != null ||
                                family['wife'] != null)
                              _Section(
                                title: 'Eltern',
                                people: [
                                  if (family['husband'] != null)
                                    family['husband'] as Map<String, dynamic>,
                                  if (family['wife'] != null)
                                    family['wife'] as Map<String, dynamic>,
                                ],
                                depth: widget.depth,
                              ),
                          ],
                          for (final family in spouseFamilies) ...[
                            if (family['spouse'] != null)
                              _Section(
                                title:
                                    (family['spouse']
                                            as Map<String, dynamic>)['sex'] ==
                                        'F'
                                    ? 'Ehepartnerin'
                                    : 'Ehepartner',
                                people: [
                                  family['spouse'] as Map<String, dynamic>,
                                ],
                                depth: widget.depth,
                              ),
                          ],
                          if (spouseFamilies
                              .expand(
                                (f) => f['children'] as List<dynamic>? ?? [],
                              )
                              .isNotEmpty)
                            _Section(
                              title:
                                  'Kinder (${spouseFamilies.fold<int>(0, (n, f) => n + (f['children'] as List<dynamic>? ?? []).length)})',
                              people: spouseFamilies
                                  .expand(
                                    (f) =>
                                        (f['children'] as List<dynamic>? ?? [])
                                            .cast<Map<String, dynamic>>(),
                                  )
                                  .toList(),
                              depth: widget.depth,
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (fab != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16 + MediaQuery.paddingOf(context).bottom,
                  child: fab,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Short "* 1930 † 2001" once there's a death date; for someone still
  /// alive, just their current age — the birth date itself already has its
  /// own row in the facts card below, so repeating it here was redundant.
  String _lifespanText(Map<String, dynamic> person) {
    final death = person['death'] as Map<String, dynamic>?;
    if (death != null) {
      return person['lifespan'] as String? ?? '';
    }

    final birth = person['birth'] as Map<String, dynamic>?;
    final birthDate = birth?['date'] as Map<String, dynamic>?;
    final age = _ageInYears(birthDate?['jd'] as num?);
    return age == null ? (person['lifespan'] as String? ?? '') : '$age Jahre';
  }
}

/// Opens the family-tree view, centered on this person — the round
/// tree-icon button to the left of the avatar.
class _TreeViewButton extends StatelessWidget {
  const _TreeViewButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.secondary.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.park_outlined, size: 20, color: AppColors.secondary),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    this.editing = false,
    this.onEditToggle,
    this.onShare,
    this.onAskForHelp,
  });

  final String name;
  final bool editing;
  final VoidCallback? onEditToggle;
  final VoidCallback? onShare;

  /// "Um Mithilfe bitten" (webtrees-share) — deliberately not folded into
  /// [onShare]'s menu: it starts a stateful request/response flow with a
  /// relative, not a one-off system share action, and is a separate,
  /// optional server module besides.
  final VoidCallback? onAskForHelp;

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
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              stripNameSlashes(name),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onAskForHelp != null)
            IconButton(
              onPressed: onAskForHelp,
              icon: const Icon(
                Icons.volunteer_activism_outlined,
                color: AppColors.textPrimary,
              ),
              tooltip: 'Um Mithilfe bitten',
            ),
          if (onShare != null)
            IconButton(
              onPressed: onShare,
              icon: const Icon(
                Icons.share_outlined,
                color: AppColors.textPrimary,
              ),
              tooltip: 'Teilen',
            ),
          if (onEditToggle != null)
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

class _FactsCard extends StatefulWidget {
  const _FactsCard({required this.facts});

  final List<Map<String, dynamic>> facts;

  @override
  State<_FactsCard> createState() => _FactsCardState();
}

class _FactsCardState extends State<_FactsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visible = widget.facts.where((f) => f['tag'] != 'NAME').toList();
    final primary = _sortedByFieldOrder(
      visible.where((f) => _primaryFactTags.contains(f['tag'])).toList(),
    );
    final secondary = _sortedByFieldOrder(
      visible.where((f) => !_primaryFactTags.contains(f['tag'])).toList(),
    );
    final shown = _expanded ? [...primary, ...secondary] : primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++)
            InkWell(
              onTap: () => copyToClipboard(_factCopyText(shown[i])),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shown[i]['label'] as String? ?? shown[i]['tag'] as String,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Flexible(child: _FactValue(fact: shown[i])),
                  ],
                ),
              ),
            ),
          if (secondary.isNotEmpty)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _expanded
                          ? 'Weniger anzeigen'
                          : 'Mehr anzeigen (${secondary.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A fact's value, right-aligned. Facts combining several things (typically
/// a date plus a place) can get long, so the primary part (value/date)
/// stays normal size on its own line and the place — often the longest,
/// least essential-at-a-glance part — drops to a small second line, the
/// same pattern PersonCard uses under a name. A fact with only one part
/// (just a place, just a value, ...) stays a single normal-sized line.
class _FactValue extends StatelessWidget {
  const _FactValue({required this.fact});

  final Map<String, dynamic> fact;

  @override
  Widget build(BuildContext context) {
    final value = fact['value'] as String? ?? '';
    final date = fact['date'] as Map<String, dynamic>?;
    final place = fact['place'] as Map<String, dynamic>?;

    final primaryParts = <String>[
      if (value.isNotEmpty) value,
      if (date != null) date['text'] as String,
    ];
    final placeText = place?['short'] as String?;

    final primary = primaryParts.isNotEmpty
        ? primaryParts.join(' · ')
        : (placeText ?? '—');
    final secondary = primaryParts.isNotEmpty ? placeText : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          primary,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (secondary != null && secondary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              secondary,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// One editable field in edit mode, built from a raw fact JSON object. The
/// widget used depends on the tag: NAME splits into given/surname, SEX gets
/// a segmented picker, BIRT/DEAT/RESI get a place-autocomplete field,
/// everything else falls back to plain value/date/place text fields.
class _EditableFact {
  _EditableFact({
    required this.tag,
    required this.factId,
    required this.label,
    this.givenController,
    this.surnameController,
    this.valueController,
    this.dateController,
    this.placeController,
    String? sex,
  }) : sexValue = sex,
       _originalGiven = givenController?.text,
       _originalSurname = surnameController?.text,
       _originalValue = valueController?.text,
       _originalDate = dateController?.text,
       _originalPlace = placeController?.text,
       _originalSex = sex;

  factory _EditableFact.fromJson(Map<String, dynamic> json) {
    final tag = json['tag'] as String;
    final label = json['label'] as String? ?? tag;
    final factId = json['id'] as String?;
    final value = json['value'] as String? ?? '';
    final dateMap = json['date'] as Map<String, dynamic>?;
    // Pre-fill with the GEDCOM form ("12 MAR 1930"), not the localized
    // display text ("March 12, 1930") — the latter is what gets sent back
    // verbatim if left untouched, and webtrees expects GEDCOM syntax.
    // Falls back to the display text against an older API without `gedcom`.
    final date =
        dateMap?['gedcom'] as String? ?? dateMap?['text'] as String? ?? '';
    final placeMap = json['place'] as Map<String, dynamic>?;
    final place =
        (placeMap?['name'] as String?) ?? (placeMap?['short'] as String?) ?? '';

    switch (tag) {
      case 'NAME':
        final (given, surname) = splitGedcomName(value);
        return _EditableFact(
          tag: tag,
          factId: factId,
          label: label,
          givenController: TextEditingController(text: given),
          surnameController: TextEditingController(text: surname),
        );
      case 'SEX':
        return _EditableFact(
          tag: tag,
          factId: factId,
          label: label,
          sex: value.isEmpty ? 'U' : value,
        );
      case 'RESI':
        return _EditableFact(
          tag: tag,
          factId: factId,
          label: label,
          placeController: TextEditingController(text: place),
        );
      case 'BIRT':
      case 'DEAT':
        return _EditableFact(
          tag: tag,
          factId: factId,
          label: label,
          dateController: TextEditingController(text: date),
          placeController: TextEditingController(text: place),
        );
      default:
        return _EditableFact(
          tag: tag,
          factId: factId,
          label: label,
          valueController: TextEditingController(text: value),
          dateController: date.isNotEmpty
              ? TextEditingController(text: date)
              : null,
          placeController: place.isNotEmpty
              ? TextEditingController(text: place)
              : null,
        );
    }
  }

  final String tag;
  final String? factId;
  final String label;

  final TextEditingController? givenController;
  final TextEditingController? surnameController;
  final TextEditingController? valueController;
  final TextEditingController? dateController;
  final TextEditingController? placeController;
  String? sexValue;

  final String? _originalGiven;
  final String? _originalSurname;
  final String? _originalValue;
  final String? _originalDate;
  final String? _originalPlace;
  final String? _originalSex;

  String? get currentValue {
    if (tag == 'NAME') {
      return buildGedcomName(givenController!.text, surnameController!.text);
    }
    if (tag == 'SEX') return sexValue;
    return valueController?.text;
  }

  String? get currentDate {
    final text = dateController?.text.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  String? get currentPlace {
    final text = placeController?.text.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  bool get isDirty {
    if (tag == 'NAME') {
      return givenController!.text.trim() != (_originalGiven ?? '') ||
          surnameController!.text.trim() != (_originalSurname ?? '');
    }
    if (tag == 'SEX') return sexValue != _originalSex;
    final valueDirty = (valueController?.text ?? '') != (_originalValue ?? '');
    final dateDirty = (dateController?.text ?? '') != (_originalDate ?? '');
    final placeDirty = (placeController?.text ?? '') != (_originalPlace ?? '');
    return valueDirty || dateDirty || placeDirty;
  }

  void dispose() {
    givenController?.dispose();
    surnameController?.dispose();
    valueController?.dispose();
    dateController?.dispose();
    placeController?.dispose();
  }
}

/// The in-place edit form shown instead of [_FactsCard] while editing —
/// every fact the person already has, editable, including the ones normally
/// collapsed under "Mehr anzeigen". Adding a brand-new fact type is still
/// done via the "Fakt hinzufügen" button; this only edits what's here.
class _EditFactsSection extends ConsumerStatefulWidget {
  const _EditFactsSection({
    super.key,
    required this.xref,
    required this.facts,
    required this.savingNotifier,
    required this.onSaved,
  });

  final String xref;
  final List<Map<String, dynamic>> facts;
  final ValueNotifier<bool> savingNotifier;
  final VoidCallback onSaved;

  @override
  ConsumerState<_EditFactsSection> createState() => _EditFactsSectionState();
}

class _EditFactsSectionState extends ConsumerState<_EditFactsSection> {
  late final List<_EditableFact> _fields;
  String? _error;

  @override
  void initState() {
    super.initState();
    final sorted = _sortedByFieldOrder(widget.facts);
    _fields = [for (final f in sorted) _EditableFact.fromJson(f)];
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    widget.savingNotifier.value = true;
    setState(() => _error = null);

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      for (final field in _fields) {
        if (!field.isDirty) continue;
        final result = await client.postFact(
          tree,
          widget.xref,
          factId: field.factId,
          tag: field.tag,
          value: field.currentValue,
          date: field.currentDate,
          place: field.currentPlace,
        );
        if (result['ok'] != true) {
          throw Exception(
            '${field.label}: ${result['error'] ?? 'unbekannter Fehler'}',
          );
        }
      }
      widget.savingNotifier.value = false;
      if (!mounted) return;
      widget.onSaved();
    } on Exception catch (e) {
      widget.savingNotifier.value = false;
      if (!mounted) return;
      setState(() => _error = 'Speichern fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final field in _fields) ...[
            const SizedBox(height: 16),
            _buildFieldEditor(field),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
  );

  Widget _buildFieldEditor(_EditableFact field) {
    switch (field.tag) {
      case 'NAME':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(field.label),
            const SizedBox(height: 6),
            TextField(
              controller: field.givenController,
              decoration: const InputDecoration(labelText: 'Vorname'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: field.surnameController,
              decoration: const InputDecoration(labelText: 'Nachname'),
            ),
          ],
        );
      case 'SEX':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(field.label),
            const SizedBox(height: 6),
            _SexSegment(
              value: field.sexValue,
              onChanged: (v) => setState(() => field.sexValue = v),
            ),
          ],
        );
      case 'RESI':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(field.label),
            const SizedBox(height: 6),
            PlaceAutocompleteField(
              controller: field.placeController!,
              labelText: 'Ort',
            ),
          ],
        );
      case 'BIRT':
      case 'DEAT':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(field.label),
            const SizedBox(height: 6),
            GedcomDateField(controller: field.dateController!),
            const SizedBox(height: 8),
            PlaceAutocompleteField(
              controller: field.placeController!,
              labelText: 'Ort',
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(field.label),
            const SizedBox(height: 6),
            TextField(
              controller: field.valueController,
              decoration: const InputDecoration(labelText: 'Wert'),
            ),
            if (field.dateController != null) ...[
              const SizedBox(height: 8),
              GedcomDateField(controller: field.dateController!),
            ],
            if (field.placeController != null) ...[
              const SizedBox(height: 8),
              PlaceAutocompleteField(
                controller: field.placeController!,
                labelText: 'Ort',
              ),
            ],
          ],
        );
    }
  }
}

class _SexSegment extends StatelessWidget {
  const _SexSegment({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [('M', 'Männlich'), ('F', 'Weiblich'), ('U', 'Unbekannt')];
    return Wrap(
      spacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.$2),
            selected: value == option.$1,
            onSelected: (_) => onChanged(option.$1),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.people, this.depth = 0});

  final String title;
  final List<Map<String, dynamic>> people;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                PersonCard(
                  person: people[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PersonDetailScreen(
                        xref: people[i]['xref'] as String,
                        depth: depth + 1,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
