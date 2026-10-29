import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/photo_crop.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/gedcom.dart';
import '../../utils/tab_navigation.dart';
import '../../widgets/cropped_photo.dart';
import '../../widgets/person_tag_icon.dart';
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
    this.onAddPhotos,
  });

  final String personXref;
  final String personName;

  /// The person's image entries of the individual's `media` list.
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final bool canEdit;

  /// Picks and uploads more photos of the person; the photos afterwards, or
  /// null when nothing was added.
  final Future<List<Map<String, dynamic>>?> Function()? onAddPhotos;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  static const _thumbSize = 56.0;

  late final List<Map<String, dynamic>> _photos = [
    for (final photo in widget.photos) {...photo},
  ];
  late int _index = widget.initialIndex.clamp(0, _photos.length - 1);
  late var _pageController = PageController(initialPage: _index);
  final _thumbController = ScrollController();
  bool _isBusy = false;
  bool _hasChanged = false;

  /// "Personen markieren": all frames shown, tap one to adjust, + to add.
  bool _isMarking = false;

  /// The person whose frame is shown after tapping their name under the photo.
  String? _highlightedXref;

  /// How often a photo was turned here - part of its image's key, so the turned file is shown.
  final _turnedCount = <String, int>{};

  /// Media whose GET MediaObject has been asked for already.
  final _requestedMarks = <String>{};

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
    setState(() {
      _index = index;
      _highlightedXref = null;
    });
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
        _showMessage(l10n.profilePhotoSet);
      } else {
        _showMessage(l10n.rejectedError('${result['error']}'));
      }
    } on Exception catch (e) {
      if (mounted) _showMessage(l10n.connectionFailedError('$e'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Turns the photo in view by 90° clockwise on the server - its frames turn along.
  Future<void> _turn() async {
    final l10n = AppLocalizations.of(context)!;
    final photo = _photo;
    setState(() => _isBusy = true);
    try {
      final result = await ref
          .read(webtreesClientProvider)
          .postMediaRotate(ref.read(treeNameProvider), photo['xref'] as String, quarterTurns: 1);
      if (!mounted) return;
      if (result['ok'] != true) {
        _showMessage(l10n.rejectedError('${result['error']}'));
        return;
      }
      // Same addresses, new pictures: drop the old ones from every cache.
      final headers = ref.read(webtreesClientProvider).imageHeaders;
      for (final url in {photo['file'], photo['thumb']}.whereType<String>()) {
        await NetworkImage(url, headers: headers).evict();
        _images.remove(url);
      }
      _hasChanged = true;
      setState(() => _turnedCount[photo['xref'] as String] = (_turnedCount[photo['xref']] ?? 0) + 1);
      _loadMarks(photo['xref'] as String);
      _showMessage(l10n.photoTurned);
    } on Exception catch (e) {
      if (mounted) _showMessage(l10n.connectionFailedError('$e'));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _loadMarks(String media) async {
    try {
      final result = await ref.read(webtreesClientProvider).mediaObject(ref.read(treeNameProvider), media);
      if (!mounted || result['ok'] == false) return;
      setState(() {
        _mediaObjects[media] = result;
        // This person's own frame, e.g. after the photo was turned.
        final own = (result['people'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>().where(
          (person) => person['xref'] == widget.personXref,
        );
        for (final photo in _photos.where((photo) => photo['xref'] == media)) {
          if (own.isNotEmpty) photo['crop'] = own.first['crop'];
        }
      });
    } on Exception catch (e) {
      if (mounted) _showMessage(AppLocalizations.of(context)!.connectionFailedError('$e'));
    }
  }

  /// Who is on [media] - once, as soon as the server can tell (level 40).
  void _ensureMarks(String media) {
    if (!_requestedMarks.add(media)) return;
    // After this frame: called from build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMarks(media);
    });
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
      _loadMarks(media);
      return true;
    } on Exception catch (e) {
      if (mounted) _showMessage(l10n.connectionFailedError('$e'));
      return false;
    }
  }

  /// Adjusts the frame of [personXref] on the photo in view.
  Future<void> _adjustFrame(String personXref, Object? initialCrop) async {
    final l10n = AppLocalizations.of(context)!;
    final crop = await _editCrop(title: l10n.adjustFrame, initialCrop: initialCrop);
    if (crop == null || !mounted) return;
    setState(() => _isBusy = true);
    final isSaved = await _saveCrop(personXref, crop);
    if (mounted) setState(() => _isBusy = false);
    if (isSaved && mounted) _showMessage(l10n.frameSaved);
  }

  void _startMarking() {
    _ensureMarks(_photo['xref'] as String);
    setState(() => _isMarking = true);
  }

  /// Draw a frame, say who it is: links the photo to them with that crop. Their
  /// main photo if they have none yet - else asked, showing old and new.
  Future<void> _markPerson() async {
    final l10n = AppLocalizations.of(context)!;
    final crop = await _editCrop(title: l10n.markPersonFrameTitle);
    if (crop == null || !mounted) return;
    final person = await _pickPerson();
    if (person == null || !mounted) return;

    final xref = person['xref'] as String;
    final name = person['name'] as String? ?? xref;
    // Already this person's profile photo: nothing to ask.
    final isAlreadyProfilePhoto = xref == widget.personXref && _photo['primary'] == true;
    final oldThumb = isAlreadyProfilePhoto ? null : person['thumb'] as String?;
    final media = _photo['xref'] as String;
    setState(() => _isBusy = true);
    try {
      if (!await _saveCrop(xref, crop) || !mounted) return;
      final isMainPhoto =
          !isAlreadyProfilePhoto &&
          (oldThumb == null || oldThumb.isEmpty || await _asksUseAsMainPhoto(name, oldThumb, crop));
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

  /// "Wer ist das?": the people linked to the photo first - they are likely on it, those
  /// without a frame at the top - then a search for anyone else. Null when cancelled.
  Future<Map<String, dynamic>?> _pickPerson() async {
    final l10n = AppLocalizations.of(context)!;
    final headers = ref.read(webtreesClientProvider).imageHeaders;
    final linked = [...(_mediaObjects[_photo['xref']]?['people'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()]
      ..sort((a, b) => (a['crop'] == null ? 0 : 1).compareTo(b['crop'] == null ? 0 : 1));
    Future<Map<String, dynamic>?> search() =>
        Navigator.of(context)
            .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => SearchScreen(pickerTitle: l10n.whoIsThis)));
    if (linked.isEmpty) return search();

    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l10n.whoIsThis, style: Theme.of(context).textTheme.titleMedium)),
            for (final person in linked)
              ListTile(
                key: Key('pick-${person['xref']}'),
                leading: CircleAvatar(
                  backgroundImage: (person['thumb'] as String?)?.isNotEmpty == true
                      ? NetworkImage(person['thumb'] as String, headers: headers)
                      : null,
                  child: (person['thumb'] as String?)?.isNotEmpty == true ? null : const Icon(Icons.person),
                ),
                title: Text(person['name'] as String? ?? ''),
                trailing: person['crop'] == null ? null : const Icon(Icons.crop_free, size: 18),
                onTap: () => Navigator.of(context).pop(person),
              ),
            ListTile(
              key: const Key('searchOtherPerson'),
              leading: const Icon(Icons.search),
              title: Text(l10n.searchOtherPerson),
              onTap: () => Navigator.of(context).pop('search'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return null;
    if (choice == 'search') return search();
    return choice as Map<String, dynamic>?;
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

  /// More photos of the person: afterwards the gallery shows the first new one.
  Future<void> _addPhotos() async {
    final before = {for (final photo in _photos) photo['xref']};
    final photos = await widget.onAddPhotos!();
    if (photos == null || !mounted) return;
    final firstNew = photos.indexWhere((photo) => !before.contains(photo['xref']));
    setState(() {
      _photos
        ..clear()
        ..addAll([for (final photo in photos) {...photo}]);
      _index = firstNew < 0 ? _index.clamp(0, _photos.length - 1) : firstNew;
      _hasChanged = true;
      // A new controller starts on that photo - jumping in the old one still
      // stopped at the end of the old list.
      final old = _pageController;
      _pageController = PageController(initialPage: _index);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    });
  }

  /// A frame tapped while marking: adjust it, or go to the person.
  /// A name under the photo tapped: show (or hide again) their frame on it; without one, their menu.
  void _showFrameOf(Map<String, dynamic> person) {
    if (person['crop'] == null) {
      _onMarkTapped(person);
      return;
    }
    setState(() => _highlightedXref = _highlightedXref == person['xref'] ? null : person['xref'] as String);
  }

  /// A frame tapped (or someone without one): go to them - with edit rights also adjust or unlink.
  Future<void> _onMarkTapped(Map<String, dynamic> person) async {
    final l10n = AppLocalizations.of(context)!;
    final canMark = widget.canEdit && (ref.read(apiLevelProvider).value ?? 0) >= photoMarkingApiLevel;
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
              key: const Key('goToPerson'),
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.goToPerson),
              onTap: () => Navigator.of(context).pop('open'),
            ),
            if (canMark) ...[
              ListTile(
                leading: const Icon(Icons.crop_free),
                title: Text(person['crop'] == null ? l10n.setFrame : l10n.adjustFrame),
                onTap: () => Navigator.of(context).pop('crop'),
              ),
              ListTile(
                key: const Key('unlinkPerson'),
                leading: const Icon(Icons.link_off),
                title: Text(l10n.unlinkPerson),
                onTap: () => Navigator.of(context).pop('unlink'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'open') openPerson(context, person['xref'] as String);
    if (choice == 'crop') await _adjustFrame(person['xref'] as String, person['crop']);
    if (choice == 'unlink') await _unlink(person);
  }

  /// The frames of everyone marked on [photo], over the image as shown (BoxFit.contain in [area]).
  List<Widget> _marks(Map<String, dynamic> photo, Size area, ui.Image image) {
    final people = (_mediaObjects[photo['xref']]?['people'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final scale = [area.width / imageSize.width, area.height / imageSize.height].reduce((a, b) => a < b ? a : b);
    final origin = Offset((area.width - imageSize.width * scale) / 2, (area.height - imageSize.height * scale) / 2);
    return [
      for (final person in people)
        // While marking all frames, otherwise only the one picked under the photo.
        if (_isMarking || person['xref'] == _highlightedXref)
          if (PhotoCrop.fromJson(person['crop'], imageSize) case final crop?) ...[
            Positioned(
              left: origin.dx + crop.left * scale,
              top: origin.dy + crop.top * scale,
              width: crop.width * scale,
              height: crop.height * scale,
              child: GestureDetector(
                key: Key('mark-${person['xref']}'),
                onTap: () => _onMarkTapped(person),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                  ),
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
                  onTap: () => _onMarkTapped(person),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

  /// "Auf dem Foto": everyone linked to the photo, as round faces with names - tap to show their frame.
  Widget _onThisPhoto(
    List<Map<String, dynamic>> people,
    Map<String, String> headers, {
    String? label,
    void Function(Map<String, dynamic> person)? onTap,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label ?? l10n.onThisPhoto, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              // Starts at the left for every photo.
              key: ValueKey('people-${_photo['xref']}'),
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final person = people[i];
                final thumb = person['thumb'] as String?;
                return Material(
                  color: Colors.white.withValues(alpha: person['xref'] == _highlightedXref ? 0.4 : 0.16),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    key: Key('onPhoto-${person['xref']}'),
                    customBorder: const StadiumBorder(),
                    onTap: () => (onTap ?? _showFrameOf)(person),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.white24,
                            backgroundImage: thumb == null || thumb.isEmpty
                                ? null
                                : NetworkImage(thumb, headers: headers),
                            child: thumb == null || thumb.isEmpty
                                ? const Icon(Icons.person, size: 16, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(person['name'] as String? ?? '', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Removes the link between [person] and the photo in view - the photo stays on the server.
  Future<void> _unlink(Map<String, dynamic> person) async {
    final l10n = AppLocalizations.of(context)!;
    final xref = person['xref'] as String;
    final name = stripNameSlashes(person['name'] as String? ?? xref);
    final comment = await showDialog<String>(
      context: context,
      builder: (_) => _RemovePhotoDialog(personName: name),
    );
    if (comment == null || !mounted) return;

    final media = _photo['xref'] as String;
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    setState(() => _isBusy = true);
    try {
      // The note first: it says where the photo was, which the photo itself no longer does afterwards.
      if (comment.isNotEmpty) {
        await client.postFact(tree, media, tag: 'NOTE', value: l10n.removePhotoNote(name, xref, comment));
      }
      final result = await client.postUnlinkMedia(tree, xref, media: media);
      if (!mounted) return;
      if (result['ok'] != true) {
        _showMessage(l10n.rejectedError('${result['error']}'));
        return;
      }
      _hasChanged = true;
      _showMessage(l10n.photoRemoved);
      if (xref != widget.personXref) {
        _loadMarks(media);
        return;
      }
      setState(() => _isMarking = false);
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
    final canTurn = widget.canEdit && isApiAtLeast(ref, photoRotateApiLevel);
    if (canShowMarks) _ensureMarks(_photo['xref'] as String);
    final people = (_mediaObjects[_photo['xref']]?['people'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back while marking ends marking, not the media view.
        if (_isMarking) {
          setState(() => _isMarking = false);
        } else {
          Navigator.of(context).pop(_hasChanged);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: _isMarking
              ? IconButton(
                  key: const Key('endMarkingButton'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _isMarking = false),
                )
              : null,
          title: Text(
            _isMarking ? l10n.markPeople : '${_index + 1} / ${_photos.length}',
            style: const TextStyle(color: Colors.white),
          ),
          actions: _isMarking
              ? [
                  IconButton(
                    key: const Key('addMarkButton'),
                    tooltip: l10n.addMarkButton,
                    onPressed: _isBusy ? null : _markPerson,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
                ]
              : [
                  // As in the person's ⋮ menu.
                  if (widget.onAddPhotos != null)
                    IconButton(
                      key: const Key('addPhotosButton'),
                      tooltip: l10n.addPhotos,
                      onPressed: _isBusy ? null : _addPhotos,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                  // Also in the ⋮ menu - as a symbol for those who mark often.
                  if (canMark)
                    IconButton(
                      key: const Key('markPeopleButton'),
                      tooltip: l10n.markPeople,
                      onPressed: _isBusy ? null : _startMarking,
                      icon: const PersonTagIcon(background: Colors.black),
                    ),
                  if (widget.canEdit)
                    PopupMenuButton<VoidCallback>(
                      key: const Key('photoMenu'),
                      enabled: !_isBusy,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) => action(),
                      itemBuilder: (_) => [
                        if (canMark)
                          PopupMenuItem(
                            value: _startMarking,
                            child: _MenuEntry(
                              null,
                              l10n.markPeople,
                              iconWidget: PersonTagIcon(
                                // The menu's own background (see popupMenuTheme).
                                background: AppColors.surface,
                                size: 20,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        if (!isPrimary)
                          PopupMenuItem(
                            value: _makePrimary,
                            child: _MenuEntry(Icons.account_circle_outlined, l10n.useAsProfilePhoto),
                          ),
                        if (canTurn)
                          PopupMenuItem(value: _turn, child: _MenuEntry(Icons.rotate_right, l10n.rotatePhotoTooltip)),
                        PopupMenuItem(
                          key: const Key('removePhotoItem'),
                          value: () => _unlink({'xref': widget.personXref, 'name': widget.personName}),
                          child: _MenuEntry(Icons.link_off, l10n.unlinkPerson),
                        ),
                      ],
                    ),
                ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
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
                                  key: ValueKey('${_photos[i]['xref']}-${_turnedCount[_photos[i]['xref']] ?? 0}'),
                                  _fileUrl(_photos[i]),
                                  headers: headers,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (_, child, progress) => progress == null
                                      ? child
                                      : const Center(child: CircularProgressIndicator(color: Colors.white)),
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                                  ),
                                ),
                              ),
                              // "Profilbild" at the top left of the image itself.
                              if (_photos[i]['primary'] == true && !_isMarking)
                                Positioned.fill(
                                  child: FutureBuilder<ui.Image>(
                                    future: _imageOf(_fileUrl(_photos[i])),
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) return const SizedBox.shrink();
                                      final image = snapshot.data!;
                                      final area = constraints.biggest;
                                      final scale = [
                                        area.width / image.width,
                                        area.height / image.height,
                                      ].reduce((a, b) => a < b ? a : b);
                                      return Stack(
                                        children: [
                                          Positioned(
                                            left: (area.width - image.width * scale) / 2 + 10,
                                            top: (area.height - image.height * scale) / 2 + 10,
                                            child: IgnorePointer(
                                              child: Container(
                                                key: const Key('profilePhotoLabel'),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  l10n.profilePhoto,
                                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              if ((_isMarking || _highlightedXref != null) &&
                                  _mediaObjects.containsKey(_photos[i]['xref']))
                                Positioned.fill(
                                  child: FutureBuilder<ui.Image>(
                                    future: _imageOf(_fileUrl(_photos[i])),
                                    builder: (context, snapshot) => snapshot.hasData
                                        ? Stack(children: _marks(_photos[i], constraints.biggest, snapshot.data!))
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Always the same height while marking, so switching photos moves nothing.
            if (!_isMarking && people.isNotEmpty) _onThisPhoto(people, headers),
            if (_isMarking)
              SizedBox(
                height: 84,
                child: people.any((person) => person['crop'] == null)
                    ? _onThisPhoto(
                        people.where((person) => person['crop'] == null).toList(),
                        headers,
                        label: l10n.withoutFrame,
                        onTap: _onMarkTapped,
                      )
                    : null,
              ),
            if (_photos.length > 1 && !_isMarking)
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
                            key: ValueKey('thumb-${_photos[i]['xref']}-${_turnedCount[_photos[i]['xref']] ?? 0}'),
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

class _MenuEntry extends StatelessWidget {
  const _MenuEntry(this.icon, this.label, {this.iconWidget});

  final IconData? icon;
  final String label;

  /// Instead of [icon], for a composed one.
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      iconWidget ?? Icon(icon, size: 20, color: AppColors.textSecondary),
      const SizedBox(width: 12),
      Flexible(child: Text(label)),
    ],
  );
}
