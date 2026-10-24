import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';

/// All photos of a person (#35): swipe through them, a strip of thumbnails at
/// the bottom, and - with edit rights - make the one in view the main photo
/// or remove it from the person. Pops with true when something changed, so
/// the person page reloads.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.personXref,
    required this.personName,
    required this.photos,
    this.initialIndex = 0,
    this.canEdit = false,
  });

  final String personXref;
  final String personName;

  /// The person's image entries of the individual's `media` list.
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final bool canEdit;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  static const _thumbSize = 56.0;

  late final List<Map<String, dynamic>> _photos = [
    for (final photo in widget.photos) {...photo},
  ];
  late int _index = widget.initialIndex.clamp(0, _photos.length - 1);
  late final _pageController = PageController(initialPage: _index);
  final _thumbController = ScrollController();
  bool _isBusy = false;
  bool _hasChanged = false;

  @override
  void dispose() {
    _pageController.dispose();
    _thumbController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _photo => _photos[_index];

  void _onPageChanged(int index) {
    setState(() => _index = index);
    // Keep the active thumbnail in view.
    if (_thumbController.hasClients) {
      final target = index * (_thumbSize + 8) - (MediaQuery.sizeOf(context).width - _thumbSize) / 2;
      _thumbController.animateTo(
        target.clamp(0, _thumbController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _makePrimary() async {
    final l10n = AppLocalizations.of(context)!;
    final media = _photo['xref'] as String;
    setState(() => _isBusy = true);
    try {
      final result = await ref
          .read(webtreesClientProvider)
          .postPrimaryMedia(ref.read(treeNameProvider), widget.personXref, media: media);
      if (!mounted) return;
      if (result['ok'] == true) {
        setState(() {
          for (final photo in _photos) {
            photo['primary'] = photo['xref'] == media;
          }
          _hasChanged = true;
        });
        _showMessage(l10n.primaryPhotoSet);
      } else {
        _showMessage(l10n.rejectedError('${result['error']}'));
      }
    } on Exception catch (e) {
      if (mounted) _showMessage(l10n.connectionFailedError('$e'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context)!;
    final comment = await showDialog<String>(
      context: context,
      builder: (_) => _RemovePhotoDialog(personName: widget.personName),
    );
    if (comment == null || !mounted) return;

    final media = _photo['xref'] as String;
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    setState(() => _isBusy = true);
    try {
      // The note first: it says where the photo was, which the photo itself no longer does afterwards.
      if (comment.isNotEmpty) {
        await client.postFact(
          tree,
          media,
          tag: 'NOTE',
          value: l10n.removePhotoNote(widget.personName, widget.personXref, comment),
        );
      }
      final result = await client.postUnlinkMedia(tree, widget.personXref, media: media);
      if (!mounted) return;
      if (result['ok'] != true) {
        _showMessage(l10n.rejectedError('${result['error']}'));
        return;
      }
      _hasChanged = true;
      _showMessage(l10n.photoRemoved);
      if (_photos.length == 1) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _photos.removeAt(_index);
        _index = _index.clamp(0, _photos.length - 1);
      });
      _pageController.jumpToPage(_index);
    } on Exception catch (e) {
      if (mounted) _showMessage(l10n.connectionFailedError('$e'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final headers = ref.read(webtreesClientProvider).imageHeaders;
    final isPrimary = _photo['primary'] == true;
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_hasChanged);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_index + 1} / ${_photos.length}', style: const TextStyle(color: Colors.white)),
          actions: [
            if (widget.canEdit) ...[
              IconButton(
                key: const Key('primaryPhotoButton'),
                tooltip: isPrimary ? l10n.isPrimaryPhoto : l10n.makePrimaryPhoto,
                onPressed: isPrimary || _isBusy ? null : _makePrimary,
                icon: Icon(isPrimary ? Icons.star : Icons.star_border),
                disabledColor: isPrimary ? Colors.amber : Colors.white38,
              ),
              IconButton(
                key: const Key('removePhotoButton'),
                tooltip: l10n.removePhoto,
                onPressed: _isBusy ? null : _remove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _photos.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (_, i) => InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      (_photos[i]['file'] ?? _photos[i]['thumb']) as String,
                      headers: headers,
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : const CircularProgressIndicator(color: Colors.white),
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            if (_photos.length > 1)
              SafeArea(
                top: false,
                child: SizedBox(
                  height: _thumbSize + 24,
                  child: ListView.separated(
                    key: const Key('photoThumbnails'),
                    controller: _thumbController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    itemCount: _photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _pageController.jumpToPage(i),
                      child: Container(
                        width: _thumbSize,
                        decoration: BoxDecoration(
                          border: Border.all(color: i == _index ? Colors.white : Colors.transparent, width: 2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Opacity(
                          opacity: i == _index ? 1 : 0.6,
                          child: Image.network(
                            (_photos[i]['thumb'] ?? _photos[i]['file']) as String,
                            headers: headers,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks before removing a photo from a person, with an optional comment that
/// becomes a note at the photo. Pops with the comment ('' for none), or null
/// when cancelled.
class _RemovePhotoDialog extends StatefulWidget {
  const _RemovePhotoDialog({required this.personName});

  final String personName;

  @override
  State<_RemovePhotoDialog> createState() => _RemovePhotoDialogState();
}

class _RemovePhotoDialogState extends State<_RemovePhotoDialog> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.removePhotoTitle(widget.personName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.removePhotoExplanation),
          const SizedBox(height: 12),
          TextField(
            key: const Key('removePhotoComment'),
            controller: _commentController,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: l10n.removePhotoCommentHint),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_commentController.text.trim()),
          child: Text(l10n.remove),
        ),
      ],
    );
  }
}
