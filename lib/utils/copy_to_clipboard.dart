import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies [text] to the clipboard and shows a brief confirmation — used on
/// every read-only value field so a fact can be grabbed with one tap.
void copyToClipboard(BuildContext context, String text) {
  if (text.isEmpty || text == '—') return;
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Kopiert'),
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
      width: 140,
    ),
  );
}
