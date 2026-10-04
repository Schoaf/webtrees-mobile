import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const webtreesUrl = 'https://webtrees.net';
const api4webtreesUrl = 'https://github.com/thobgg/api4webtrees';

/// Text in which every "webtrees" links to webtrees.net and every
/// "api4webtrees" to the module's GitHub page (setup instructions).
/// Selectable when placed inside a SelectionArea.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  static final _pattern = RegExp('api4webtrees|webtrees');
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _pattern.allMatches(widget.text)) {
      if (match.start > start) spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      final url = match[0] == 'api4webtrees' ? api4webtreesUrl : webtreesUrl;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: match[0], style: linkStyle, recognizer: recognizer));
      start = match.end;
    }
    if (start < widget.text.length) spans.add(TextSpan(text: widget.text.substring(start)));

    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
