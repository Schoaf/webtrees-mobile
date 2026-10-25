import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:ui' as ui;

import '../../l10n/app_localizations.dart';
import '../../models/photo_crop.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cropped_photo.dart';
import '../search/crop_editor_screen.dart';

/// webtrees field codes as sent by the server (stable, not display text);
/// see [_fieldLabel] for the localized text shown for each.
String _fieldLabel(AppLocalizations l10n, String key) => switch (key) {
  'GIVN' => l10n.givenName,
  'SURN' => l10n.surname,
  'TITL' => l10n.titleFieldLabel,
  'BIRT_DATE' => l10n.birthDate,
  'BIRT_PLAC' => l10n.birthPlace,
  'DEAT_DATE' => l10n.deathDate,
  'DEAT_PLAC' => l10n.deathPlace,
  _ => key,
};

/// Native equivalent of webtrees-contribution-request's request-review.phtml — one
/// request's before/after field comparison, with a checkbox per field
/// (and note/photo) to select what to accept. Nothing is pre-selected, same
/// as the web page: ticking is how you say "yes, take this".
class ResponseDetailScreen extends ConsumerStatefulWidget {
  const ResponseDetailScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ResponseDetailScreen> createState() => _ResponseDetailScreenState();
}

class _ResponseDetailScreenState extends ConsumerState<ResponseDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  final Set<String> _accepted = {};
  bool _applying = false;
  final _photo = _PhotoEdits();

  @override
  void dispose() {
    _photo.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    return client.shareRequestDetail(tree, widget.id);
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final l10n = AppLocalizations.of(context)!;

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final accept = {for (final key in _accepted) key: true};

    try {
      final result = await client.shareRequestApply(
        tree,
        widget.id,
        accept,
        photo: _accepted.contains('photo') && _photo.isSupported ? _photo.toJson() : null,
      );
      if (!mounted) return;

      final nextId = result['nextId'] as int?;
      if (nextId != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ResponseDetailScreen(id: nextId)));
      } else {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.allResponsesReviewed)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.couldNotApplyError('$e'))));
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardRequestTitle),
        content: Text(l10n.discardRequestMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.discardButton)),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);

    try {
      final ok = await client.shareRequestDelete(tree, widget.id);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.couldNotDiscardMessage)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.couldNotDiscardError('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).pop(), onDelete: _delete),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(l10n.couldNotLoad('${snapshot.error}')));
                  }

                  _photo.initFrom(snapshot.data!);
                  return _Body(
                    data: snapshot.data!,
                    photo: _photo,
                    onPhotoChanged: () => setState(() {}),
                    accepted: _accepted,
                    applying: _applying,
                    onToggle: (key, value) => setState(() {
                      if (value) {
                        _accepted.add(key);
                      } else {
                        _accepted.remove(key);
                      }
                    }),
                    onApply: _apply,
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

/// The reviewer's turn, frame and description of a contributed photo (#39),
/// starting from the guest's - sent along when the photo is applied.
class _PhotoEdits {
  int turns = 0;

  /// In pixels of the image as turned by [turns]; null = no frame.
  Map<String, dynamic>? crop;
  final title = TextEditingController();
  final note = TextEditingController();
  String type = 'photo';
  bool isProfile = false;

  /// The module can take these (it sends `photoType`).
  bool isSupported = false;
  bool _isInitialized = false;

  void initFrom(Map<String, dynamic> data) {
    if (_isInitialized) return;
    _isInitialized = true;
    isSupported = data.containsKey('photoType');
    crop = (data['photoCrop'] as Map?)?.cast<String, dynamic>();
    title.text = data['photoTitle'] as String? ?? '';
    note.text = data['photoNote'] as String? ?? '';
    type = data['photoType'] as String? ?? 'photo';
  }

  Map<String, dynamic> toJson() => {
    'photoTurns': turns,
    'photoCrop': crop,
    'photoTitle': title.text.trim(),
    'photoNote': note.text.trim(),
    'photoType': type,
    'photoIsProfile': isProfile,
  };

  void dispose() {
    title.dispose();
    note.dispose();
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.photo,
    required this.onPhotoChanged,
    required this.data,
    required this.accepted,
    required this.applying,
    required this.onToggle,
    required this.onApply,
  });

  final Map<String, dynamic> data;
  final Set<String> accepted;
  final bool applying;
  final void Function(String key, bool value) onToggle;
  final VoidCallback onApply;
  final _PhotoEdits photo;
  final VoidCallback onPhotoChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final name = data['name'] as String? ?? '';
    final responder = data['responder'] as String? ?? '';
    final appliedAlready = data['applied'] as bool? ?? false;
    // The server always sends an object here, but PHP serializes an empty
    // array as JSON "[]" rather than "{}" - defend against that shape too
    // rather than crashing to a blank screen if that ever slips through again.
    final compareRaw = data['compare'];
    final compare = (compareRaw is Map ? compareRaw : {}).cast<String, Map<String, dynamic>>();
    final note = data['note'] as String? ?? '';
    final photoUrl = data['photoUrl'] as String? ?? '';

    if (appliedAlready) {
      return _InfoMessage(name: name, responder: responder, text: l10n.responseAlreadyApplied);
    }

    if (compare.isEmpty && note.isEmpty && photoUrl.isEmpty) {
      return _InfoMessage(name: name, responder: responder, text: l10n.noChangesProposed);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ForLine(name: name, responder: responder),
        const SizedBox(height: 16),
        if (photoUrl.isNotEmpty)
          _CompareCard(
            title: l10n.acceptPhotoLabel,
            checked: accepted.contains('photo'),
            onChanged: (v) => onToggle('photo', v),
            child: photo.isSupported
                ? _PhotoReview(
                    url: photoUrl,
                    photo: photo,
                    hasProfilePhoto: data['hasProfilePhoto'] == true,
                    onChanged: onPhotoChanged,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      photoUrl,
                      headers: ref.read(webtreesClientProvider).imageHeaders,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
        for (final entry in compare.entries)
          _CompareCard(
            title: _fieldLabel(l10n, entry.key),
            checked: accepted.contains(entry.key),
            onChanged: (v) => onToggle(entry.key, v),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.previousValueLabel(
                    (entry.value['before'] as String?)?.isEmpty ?? true
                        ? l10n.emptyValuePlaceholder
                        : entry.value['before'] as String,
                  ),
                  style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.newValueLabel('${entry.value['after']}'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        if (note.isNotEmpty)
          _CompareCard(
            title: l10n.acceptAsNoteLabel,
            checked: accepted.contains('note'),
            onChanged: (v) => onToggle('note', v),
            child: Text(note, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: (applying || accepted.isEmpty) ? null : onApply,
          child: applying
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(l10n.applySelectedButton),
        ),
      ],
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.title, required this.checked, required this.onChanged, required this.child});

  final String title;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onChanged(!checked),
            child: Row(
              children: [
                Checkbox(value: checked, onChanged: (v) => onChanged(v ?? false)),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.only(left: 4), child: child),
        ],
      ),
    );
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({required this.name, required this.responder, required this.text});

  final String name;
  final String responder;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ForLine(name: name, responder: responder),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.cardShadow,
            ),
            child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _ForLine extends StatelessWidget {
  const _ForLine({required this.name, required this.responder});

  final String name;
  final String responder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.forPersonLabel(name),
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
        if (responder.isNotEmpty)
          Text(
            AppLocalizations.of(context)!.fromResponderLabel(responder),
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onDelete});

  final VoidCallback onBack;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, boxShadow: AppColors.cardShadow),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.reviewResponseTitle,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: AppColors.textPrimary),
            tooltip: AppLocalizations.of(context)!.discardRequestTooltip,
          ),
        ],
      ),
    );
  }
}

/// A contributed photo as the guest left it - turned and framed - with the
/// tools to still turn it, set or adjust the frame and change its
/// description before applying (#39).
class _PhotoReview extends ConsumerStatefulWidget {
  const _PhotoReview({required this.url, required this.photo, required this.hasProfilePhoto, required this.onChanged});

  final String url;
  final _PhotoEdits photo;
  final bool hasProfilePhoto;
  final VoidCallback onChanged;

  @override
  ConsumerState<_PhotoReview> createState() => _PhotoReviewState();
}

class _PhotoReviewState extends ConsumerState<_PhotoReview> {
  late final Future<ui.Image> _image = ref.read(networkImageLoaderProvider)(
    widget.url,
    ref.read(webtreesClientProvider).imageHeaders,
  );

  /// The image size as shown, i.e. turned.
  Size _shownSize(ui.Image image) => widget.photo.turns.isOdd
      ? Size(image.height.toDouble(), image.width.toDouble())
      : Size(image.width.toDouble(), image.height.toDouble());

  void _turn(ui.Image image) {
    final photo = widget.photo;
    final size = _shownSize(image);
    final crop = PhotoCrop.fromJson(photo.crop, size);
    photo.crop = crop?.turnedClockwise(size).toJson();
    photo.turns = (photo.turns + 1) % 4;
    widget.onChanged();
  }

  Future<void> _editFrame() async {
    final l10n = AppLocalizations.of(context)!;
    final crop = await Navigator.of(context).push<PhotoCrop>(
      MaterialPageRoute(
        builder: (_) => CropEditorScreen(
          url: widget.url,
          headers: ref.read(webtreesClientProvider).imageHeaders,
          title: widget.photo.crop == null ? l10n.setFrame : l10n.adjustFrame,
          initialCrop: widget.photo.crop,
          quarterTurns: widget.photo.turns,
        ),
      ),
    );
    if (crop == null) return;
    widget.photo.crop = crop.toJson();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photo = widget.photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<ui.Image>(
          future: _image,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
            }
            final image = snapshot.data!;
            final size = _shownSize(image);
            final crop = PhotoCrop.fromJson(photo.crop, size);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: size.width / size.height,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scale = constraints.maxWidth / size.width;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: RotatedBox(
                                quarterTurns: photo.turns,
                                child: RawImage(image: image, fit: BoxFit.fill),
                              ),
                            ),
                            if (crop != null)
                              Positioned(
                                key: const Key('contributedPhotoFrame'),
                                left: crop.left * scale,
                                top: crop.top * scale,
                                width: crop.width * scale,
                                height: crop.height * scale,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white, width: 2.5),
                                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('turnContributedPhoto'),
                      onPressed: () => _turn(image),
                      icon: const Icon(Icons.rotate_right, size: 18),
                      label: Text(l10n.rotatePhotoTooltip),
                    ),
                    OutlinedButton.icon(
                      key: const Key('frameContributedPhoto'),
                      onPressed: _editFrame,
                      icon: const Icon(Icons.crop_free, size: 18),
                      label: Text(photo.crop == null ? l10n.setFrame : l10n.adjustFrame),
                    ),
                    if (photo.crop != null)
                      TextButton(
                        key: const Key('removeContributedFrame'),
                        onPressed: () {
                          photo.crop = null;
                          widget.onChanged();
                        },
                        child: Text(l10n.removeFrame),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('contributedPhotoTitle'),
          controller: photo.title,
          decoration: InputDecoration(labelText: l10n.photoTitleLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: photo.note,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: l10n.photoDescriptionLabel),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'photo', label: Text(l10n.photoTypePhoto), icon: const Icon(Icons.photo_outlined)),
            ButtonSegment(
              value: 'document',
              label: Text(l10n.photoTypeDocument),
              icon: const Icon(Icons.description_outlined),
            ),
          ],
          selected: {photo.type},
          onSelectionChanged: (selection) {
            photo.type = selection.first;
            widget.onChanged();
          },
        ),
        if (widget.hasProfilePhoto)
          // Not a SwitchListTile: the card's coloured background would hide its ink.
          Row(
            children: [
              Expanded(child: Text(l10n.useAsProfilePhotoInstead)),
              Switch(
                key: const Key('contributedPhotoIsProfile'),
                value: photo.isProfile,
                onChanged: (value) {
                  photo.isProfile = value;
                  widget.onChanged();
                },
              ),
            ],
          ),
      ],
    );
  }
}
