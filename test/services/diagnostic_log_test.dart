import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/services/diagnostic_log.dart';

void main() {
  late Directory directory;
  final log = DiagnosticLog.instance;

  setUp(() => directory = Directory.systemTemp.createTempSync('diagnostic_log_test'));
  tearDown(() => directory.deleteSync(recursive: true));

  Future<String> sent() async => (await log.fileToSend(header: 'HEADER'))?.readAsStringSync() ?? '';

  test('collects nothing while it is off', () async {
    await log.debugSetUp(directory: directory, isEnabled: false);
    log.info('hello');
    log.error('here', StateError('boom'));

    expect(await log.fileToSend(header: 'HEADER'), isNull);
  });

  test('writes the header, messages and errors with their place while it is on', () async {
    await log.debugSetUp(directory: directory, isEnabled: true);
    log.info('hello');
    log.error('login_screen', StateError('boom'), StackTrace.current);

    final text = await sent();
    expect(text, startsWith('HEADER\n'));
    expect(text, contains('INFO hello'));
    expect(text, contains('ERROR login_screen: StateError: Bad state: boom'));
  });

  test('logs the same error only once', () async {
    await log.debugSetUp(directory: directory, isEnabled: true);
    final error = StateError('boom');
    log.error('screen', error);
    log.error('screen', error);

    expect('ERROR'.allMatches(await sent()).length, 1);
  });

  test('a request: status, content type, cookie names - no cookie values', () async {
    await log.debugSetUp(directory: directory, isEnabled: true);
    final options = RequestOptions(path: 'https://tree.example.com/index.php?route=/login&username=anna');
    log.request(
      options,
      response: Response(
        requestOptions: options,
        statusCode: 302,
        headers: Headers.fromMap({
          'content-type': ['text/html'],
          'set-cookie': ['webtrees2=secret123; path=//', 'SERVERID=web3'],
        }),
      ),
      duration: const Duration(milliseconds: 120),
    );

    final text = await sent();
    expect(text, contains('HTTP GET'));
    expect(text, contains('https://tree.example.com/index.php?route=/login&username=… 302 120ms text/html'));
    expect(text, contains('cookies: webtrees2, SERVERID'));
    expect(text, isNot(contains('secret123')));
    expect(text, isNot(contains('anna')));
  });

  test('a FormatException without what it quotes from its input', () {
    expect(
      DiagnosticLog.describeError(const FormatException('Unexpected character', '{"name":"Anna Muster"}', 3)),
      'FormatException: Unexpected character',
    );
  });

  test('a long message is shortened', () {
    expect(DiagnosticLog.describeError(Exception('x' * 1000)).length, lessThan(400));
  });
}
