import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/photo_crop.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/tab_navigation.dart';
import '../../widgets/cropped_photo.dart';
import 'crop_editor_screen.dart';
import 'search_screen.dart';

/// All photos of a person (#35): swipe through them, a strip of thumbnails at
/// the bottom, and - with edit rights - make the one in view the main photo
/// or remove it from the person; frame this person's part, mark others on it
/// and show who is marked where (#37). Pops with true when something
/// changed, so the person page reloads.
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
  bool _isShowingMarks = false;

  /// GET MediaObject per media xref: who is marked where.
  final _mediaObjects = <String, Map<String, dynamic>>{};

  /// Decoded images per URL, for their size (the same image cache as the photo itself).
  final _images = <String, Future<ui.Image>>{};

  String _fileUrl(Map<String, dynamic> photo) => (photo['file'] ?? photo['thumb']) as String;

  Future<ui.Image> _imageOf(String url) => _images.putIfAbsent(
    url,
    () => ref.read(networkImageLoaderProvider)(url, ref.read(webtreesClientProvider).imageHeaders),
  );

  @override
  void dispose() {
    _pageController.dispose();
    _thumbController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _photo => _photos[_index];

  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (_isShowingMarks) _loadMarks(_photo['xref'] as String);
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

  Future<void> _loadMarks(String media) async {
    try {
      final result = await ref.read(webtreesClientProvider).mediaObject(ref.read(treeNameProvider), media);
      if (mounted && result['ok'] != false) setState(() => _mediaObjects[media] = result);
    } on Exception catch (e) {
      if (mounted) _showMessage(AppLocalizations.of(context)!.connectionFailedError('$e'));
    }
  }

  void _toggleMarks() {
    setState(() => _isShowingMarks = !_isShowingMarks);
    if (_isShowingMarks) _loadMarks(_photo['xref'] as String);
  }

  /// The crop editor for the photo in view; null when cancelled.
  Future<PhotoCrop?> _editCrop({required String title, Object? initialCrop}) => Navigator.of(context).push<PhotoCrop>(
    MaterialPageRoute(
      builder: (_) => CropEditorScreen(
        url: _fileUrl(_photo),
        headers: ref.read(webtreesClientProvider).imageHeaders,
        title: title,
        initialCrop: initialCrop,
      ),
    ),
  );

  /// Saves [crop] as [personXref]'s part of the photo in view; false on failure.
  Future<bool> _saveCrop(String personXref, PhotoCrop crop) async {
    final l10n = AppLocalizations.of(context)!;
    final media = _photo['xref'] as String;
    try {
      final result = await ref
          .read(webtreesClientProvider)
          .postMediaCrop(ref.read(treeNameProvider), personXref, media: media, crop: crop.toJson());
      if (!mounted) return false;
      if (result['ok'] != true) {
        _showMessage(l10n.rejectedError('${result['error']}'));
        return false;
      }
      _hasChanged = true;
      if (personXref == widget.personXref) setState(() => _photo['crop'] = crop.toJson());
      if (_isShowingMarks || _mediaObjects.containsKey(media)) _loadMarks(media);
      return true;
    } on Exception catch (e) {
      if (mounted) _showMessage(l10n.connectionFailedError('$e'));
      return false;
    }
  }

  /// Frames [personXref] (default: the person this view is for) on the photo in view.
  Future<void> _adjustCrop({String? personXref, Object? initialCrop}) async {
    final l10n = AppLocalizations.of(context)!;
    final crop = await _editCrop(
      title: l10n.adjustCrop,
      initialCrop: personXref == null ? _photo['crop'] : initialCrop,
    );
    if (crop == null || !mounted) return;
    setState(() => _isBusy = true);
    final isSaved = await _saveCrop(personXref ?? widget.personXref, crop);
    if (mounted) setState(() => _isBusy = false);
    if (isSaved && mounted) _showMessage(l10n.cropSaved);
  }

  /// Draw a frame, say who it is: links the photo to them with that crop. Their
  /// main photo if they have none yet - else asked, showing old and new.
  Future<void> _markPerson() async {
    final l10n = AppLocalizations.of(context)!;
    final crop = await _editCrop(title: l10n.markPersonFrameTitle);
    if (crop == null || !mounted) return;
    final person = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => SearchScreen(pickerTitle: l10n.whoIsThis)));
    if (person == null || !mounted) return;

    final xref = person['xref'] as String;
    final name = person['name'] as String? ?? xref;
    final oldThumb = person['thumb'] as String?;
    final media = _photo['xref'] as String;
    setState(() => _isBusy = true);
    try {
      if (!await _saveCrop(xref, crop) || !mounted) return;
      final isMainPhoto = oldThumb == null || oldThumb.isEmpty || await _asksUseAsMainPhoto(name, oldThumb, crop);
      if (isMainPhoto && mounted) {
        await ref.read(webtreesClientProvider).postPrimaryMedia(ref.read(treeNameProvider), xref, media: media);
      }
      if (mounted) _showMessage(l10n.personMarked(name));
    } on Exception catch (e) {
      if (mounted) _showMessage(l10n.connectionFailedError('$e'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _asksUseAsMainPhoto(String name, String oldThumb, PhotoCrop crop) async {
    final l10n = AppLocalizations.of(context)!;
    final headers = ref.read(webtreesClientProvider).imageHeaders;
    Widget labelled(String label, Widget photo) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: photo),
        const SizedBox(height: 6),
        Text(label),
      ],
    );
    final isNew = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.useAsMainPhotoTitle(name)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            labelled(
              l10n.currentPhoto,
              Image.network(
                oldThumb,
                headers: headers,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const SizedBox.square(dimension: 100, child: Icon(Icons.broken_image_outlined)),
              ),
            ),
            labelled(l10n.newPhoto, CroppedPhoto(url: _fileUrl(_photo), headers: headers, crop: crop, size: 100)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.keepCurrentPhoto)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.useNewPhoto)),
        ],
      ),
    );
    return isNew ?? false;
  }

  /// A marked person tapped: go to them - or, with edit rights, adjust their frame.
  Future<void> _onMarkTapped(Map<String, dynamic> person, bool canMark) async {
    if (!canMark) {
      openPerson(context, person['xref'] as String);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(person['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.goToPerson),
              onTap: () => Navigator.of(context).pop('open'),
            ),
            ListTile(
              leading: const Icon(Icons.crop),
              title: Text(l10n.adjustCrop),
              onTap: () => Navigator.of(context).pop('crop'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'open') openPerson(context, person['xref'] as String);
    if (choice == 'crop') await _adjustCrop(personXref: person['xref'] as String, initialCrop: person['crop']);
  }

  /// The frames of everyone marked on [photo], over the image as shown (BoxFit.contain in [area]).
  List<Widget> _marks(Map<String, dynamic> photo, Size area, ui.Image image, bool canMark) {
    final people = (_mediaObjects[photo['xref']]?['people'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final scale = [area.width / imageSize.width, area.height / imageSize.height].reduce((a, b) => a < b ? a : b);
    final origin = Offset((area.width - imageSize.width * scale) / 2, (area.height - imageSize.height * scale) / 2);
    return [
      for (final person in people)
        if (PhotoCrop.fromJson(person['crop'], imageSize) case final crop?) ...[
          Positioned(
            left: origin.dx + crop.left * scale,
            top: origin.dy + crop.top * scale,
            width: crop.width * scale,
            height: crop.height * scale,
            child: GestureDetector(
              key: Key('mark-${person['xref']}'),
              onTap: () => _onMarkTapped(person, canMark),
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2)),
              ),
            ),
          ),
          // The name below the frame, wider than a small face.
          Positioned(
            left: origin.dx + crop.left * scale + crop.width * scale / 2 - 80,
            top: origin.dy + (crop.top + crop.height) * scale + 2,
            width: 160,
            child: Center(
              child: GestureDetector(
                onTap: () => _onMarkTapped(person, canMark),
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    person['name'] as String? ?? '',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
    ];
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
    final canShowMarks = isApiAtLeast(ref, photoMarkingApiLevel);
    final canMark = widget.canEdit && canShowMarks;
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
            if (canShowMarks)
              IconButton(
                key: const Key('marksButton'),
                tooltip: _isShowingMarks ? l10n.hideMarks : l10n.showMarks,
                onPressed: _toggleMarks,
                icon: Icon(_isShowingMarks ? Icons.people_alt : Icons.people_alt_outlined),
              ),
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
            if (canMark)
              PopupMenuButton<VoidCallback>(
                key: const Key('photoMenu'),
                enabled: !_isBusy,
                icon: const Icon(Icons.more_vert),
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: _adjustCrop, child: Text(l10n.adjustCrop)),
                  PopupMenuItem(value: _markPerson, child: Text(l10n.markPerson)),
                ],
              ),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        // Always fitted like this - the marks are drawn on the same geometry.
                        Positioned.fill(
                          child: Image.network(
                            _fileUrl(_photos[i]),
                            headers: headers,
                            fit: BoxFit.contain,
                            loadingBuilder: (_, child, progress) => progress == null
                                ? child
                                : const Center(child: CircularProgressIndicator(color: Colors.white)),
                            errorBuilder: (_, _, _) =>
                                const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
                          ),
                        ),
                        if (_isShowingMarks && _mediaObjects.containsKey(_photos[i]['xref']))
                          Positioned.fill(
                            child: FutureBuilder<ui.Image>(
                              future: _imageOf(_fileUrl(_photos[i])),
                              builder: (context, snapshot) => snapshot.hasData
                                  ? Stack(children: _marks(_photos[i], constraints.biggest, snapshot.data!, canMark))
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
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
