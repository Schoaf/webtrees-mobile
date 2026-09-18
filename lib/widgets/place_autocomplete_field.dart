import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_providers.dart';
import '../theme/app_theme.dart';

/// A place-name text field with suggestions from webtrees' own autocomplete
/// endpoint (the tree's existing places, falling back to a gazetteer module
/// if the site has one configured) — same source webtrees' own web UI uses.
class PlaceAutocompleteField extends ConsumerStatefulWidget {
  const PlaceAutocompleteField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;

  @override
  ConsumerState<PlaceAutocompleteField> createState() =>
      _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState
    extends ConsumerState<PlaceAutocompleteField> {
  Timer? _debounce;
  List<String> _suggestions = [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final client = ref.read(webtreesClientProvider);
      final tree = ref.read(treeNameProvider);
      try {
        final results = await client.placeAutocomplete(tree, query);
        if (!mounted) return;
        setState(() => _suggestions = results);
      } on Exception {
        // suggestions are best-effort — free text still works without them
      }
    });
  }

  void _select(String place) {
    widget.controller.text = place;
    setState(() => _suggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
          ),
        ),
        for (final place in _suggestions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.place_outlined,
              size: 18,
              color: AppColors.textTertiary,
            ),
            title: Text(place),
            onTap: () => _select(place),
          ),
      ],
    );
  }
}
