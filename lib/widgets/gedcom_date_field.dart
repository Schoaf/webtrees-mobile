import 'package:flutter/material.dart';

import '../utils/gedcom_date.dart';

/// A date field that's always backed by a picker (never free-text keyboard
/// entry) - [controller]'s text stays the source of truth in GEDCOM syntax
/// ("12 MAR 1930"), same convention the rest of the edit form already sends
/// to the server. If the current value doesn't parse (a GEDCOM qualifier
/// like "ABT 1930"), it's shown as a read-only hint below rather than lost.
class GedcomDateField extends StatefulWidget {
  const GedcomDateField({
    super.key,
    required this.controller,
    this.labelText = 'Datum',
  });

  final TextEditingController controller;
  final String labelText;

  @override
  State<GedcomDateField> createState() => _GedcomDateFieldState();
}

class _GedcomDateFieldState extends State<GedcomDateField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  Future<void> _pickDate() async {
    final parsed = gedcomDateToDateTime(widget.controller.text);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1500),
      lastDate: DateTime(now.year + 100),
      helpText: widget.labelText,
      cancelText: 'Abbrechen',
      confirmText: 'Übernehmen',
    );
    if (picked != null) {
      widget.controller.text = dateTimeToGedcom(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.controller.text;
    final parsed = gedcomDateToDateTime(raw);
    final display = parsed != null ? formatGermanDate(parsed) : raw;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: _pickDate,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: widget.labelText,
              suffixIcon: raw.isEmpty
                  ? const Icon(Icons.calendar_today_outlined)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Datum entfernen',
                      onPressed: () =>
                          setState(() => widget.controller.clear()),
                    ),
            ),
            child: Text(
              display.isEmpty ? 'Datum wählen' : display,
              style: display.isEmpty
                  ? TextStyle(color: Theme.of(context).hintColor)
                  : null,
            ),
          ),
        ),
        if (raw.isNotEmpty && parsed == null) ...[
          const SizedBox(height: 4),
          Text(
            'Bisheriger Wert: $raw',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ],
    );
  }
}
