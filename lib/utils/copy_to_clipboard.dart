import 'package:flutter/services.dart';

/// Copies [text] to the clipboard — used on every read-only value field so a
/// fact can be grabbed with one tap. No confirmation shown here: Android
/// already shows its own system toast when the clipboard changes, so an
/// app-level SnackBar on top of it just duplicated the message.
void copyToClipboard(String text) {
  if (text.isEmpty || text == '—') return;
  Clipboard.setData(ClipboardData(text: text));
}
