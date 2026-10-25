import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// What the person said about photos before uploading them (#38). Empty
/// fields are null and not sent.
class PhotoDescription {
  const PhotoDescription({this.title, this.note, this.type = 'photo'});

  final String? title;
  final String? note;

  /// `photo` or `document` - the media type webtrees stores.
  final String type;
}

/// Asks for a title, a description and photo vs. document before an upload -
/// all optional, so "Hochladen" right away stays one tap. Pops with the
/// [PhotoDescription], or null when cancelled.
Future<PhotoDescription?> showPhotoDescriptionSheet(BuildContext context, List<Uint8List> previews) {
  return showModalBottomSheet<PhotoDescription>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PhotoDescriptionSheet(previews: previews),
  );
}

class _PhotoDescriptionSheet extends StatefulWidget {
  const _PhotoDescriptionSheet({required this.previews});

  final List<Uint8List> previews;

  @override
  State<_PhotoDescriptionSheet> createState() => _PhotoDescriptionSheetState();
}

class _PhotoDescriptionSheetState extends State<_PhotoDescriptionSheet> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  String _type = 'photo';

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final count = widget.previews.length;
    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.describePhotosTitle(count), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: count,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(widget.previews[i], width: 72, height: 72, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('photoTitleField'),
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.photoTitleLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('photoDescriptionField'),
                controller: _noteController,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.photoDescriptionLabel),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'photo',
                    label: Text(l10n.photoTypePhoto),
                    icon: const Icon(Icons.photo_outlined),
                  ),
                  ButtonSegment(
                    value: 'document',
                    label: Text(l10n.photoTypeDocument),
                    icon: const Icon(Icons.description_outlined),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => setState(() => _type = selection.first),
              ),
              const SizedBox(height: 8),
              Text(
                count > 1 ? '${l10n.describePhotosHint} ${l10n.appliesToAllPhotos}' : l10n.describePhotosHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('uploadPhotosButton'),
                onPressed: () => Navigator.of(context).pop(
                  PhotoDescription(
                    title: _textOrNull(_titleController),
                    note: _textOrNull(_noteController),
                    type: _type,
                  ),
                ),
                child: Text(l10n.uploadButton),
              ),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
            ],
          ),
        ),
      ),
    );
  }
}
