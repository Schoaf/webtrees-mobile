import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/copy_to_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test has no built-in Clipboard mock (unlike some other platform
  // channels), so fake the 'flutter/platform' channel calls Clipboard.* make
  // ourselves - an in-memory store is enough to observe what
  // copyToClipboard() actually sent.
  String? clipboardText;

  Future<Object?> handleClipboardCall(MethodCall call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        clipboardText = (call.arguments as Map)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        return clipboardText == null ? null : {'text': clipboardText};
      case 'Clipboard.hasStrings':
        return {'value': clipboardText != null};
    }
    return null;
  }

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      handleClipboardCall,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  test('copies non-empty, non-placeholder text to the clipboard', () async {
    copyToClipboard('Hans Müller');
    await Future<void>.delayed(Duration.zero);
    expect(clipboardText, 'Hans Müller');
  });

  test('does nothing for an empty string', () async {
    clipboardText = 'unchanged';
    copyToClipboard('');
    await Future<void>.delayed(Duration.zero);
    expect(clipboardText, 'unchanged');
  });

  test('does nothing for the "—" placeholder value', () async {
    clipboardText = 'unchanged';
    copyToClipboard('—');
    await Future<void>.delayed(Duration.zero);
    expect(clipboardText, 'unchanged');
  });
}
