import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/utils/html_text.dart';

void main() {
  test('turns webtrees\' terms HTML into readable lines', () {
    expect(
      htmlToPlainText('<p>Notice:</p><ul><li>one;</li><li>two &amp; three.</li></ul>'),
      'Notice:\n• one;\n• two & three.',
    );
  });

  test('line breaks for <br>, empty input stays empty', () {
    expect(htmlToPlainText('A<br>B'), 'A\nB');
    expect(htmlToPlainText(''), '');
  });

  test('decodes named and numeric entities', () {
    expect(htmlToPlainText('f&uuml;r Gro&szlig;eltern &#8211; &#x263A;'), 'für Großeltern – ☺');
  });
}
