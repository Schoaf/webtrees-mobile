import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';

/// A canned response for [_RecordingAdapter] to hand back for the next
/// request it sees.
class _CannedResponse {
  _CannedResponse(this.statusCode, this.body, {Map<String, List<String>>? headers})
    : headers = headers ?? {'content-type': ['application/json']};

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
}

/// A fake [HttpClientAdapter] that never touches the network: it records
/// every [RequestOptions] Dio builds (so tests can assert on the exact
/// URL/query/body a [WebtreesClient] method sends) and hands back
/// pre-queued canned responses (or a canned connection error, to exercise
/// the stale-connection retry) in order. Because this plugs in at the
/// adapter level (not by mocking [Dio] itself), the real Dio request
/// pipeline still runs - including [WebtreesClient]'s cookie/CSRF/retry
/// interceptor - so that logic gets exercised too, not bypassed.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<Object> _queue = []; // _CannedResponse or a DioExceptionType to throw

  void enqueue(_CannedResponse response) => _queue.add(response);
  void enqueueError(DioExceptionType type, {String message = ''}) => _queue.add((type, message));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_queue.isEmpty) {
      throw StateError('No canned response queued for ${options.method} ${options.uri}');
    }
    final canned = _queue.removeAt(0);
    if (canned case (DioExceptionType type, String message)) {
      throw DioException(requestOptions: options, type: type, error: message.isEmpty ? null : message);
    }
    canned as _CannedResponse;
    return ResponseBody.fromString(canned.body, canned.statusCode, headers: canned.headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late WebtreesClient client;
  late _RecordingAdapter adapter;

  setUp(() {
    client = WebtreesClient(baseUrl: 'https://tree.example.com/');
    adapter = _RecordingAdapter();
    client.debugDio.httpClientAdapter = adapter;
  });

  group('request timeouts', () {
    // Regression coverage for a real bug report: with no timeout configured
    // at all, a request the server accepts but never actually answers (a
    // stuck worker, a proxy holding the connection open, ...) hung forever
    // - no exception, no way out, just an infinite loading spinner. Every
    // WebtreesClient request must have a finite bound.
    test('connect/send/receive all have a finite bound', () {
      expect(client.debugDio.options.connectTimeout, isNotNull);
      expect(client.debugDio.options.sendTimeout, isNotNull);
      expect(client.debugDio.options.receiveTimeout, isNotNull);
    });
  });

  group('session state (no network)', () {
    test('starts with no session', () {
      expect(client.hasSession, isFalse);
      expect(client.sessionCookie, isNull);
      expect(client.imageHeaders, isEmpty);
    });

    test('restoreSession sets the cookie (and optional CSRF token)', () {
      client.restoreSession(cookie: 'wtcookie=abc123', csrfToken: 'tok');
      expect(client.hasSession, isTrue);
      expect(client.sessionCookie, 'wtcookie=abc123');
      expect(client.imageHeaders, {'Cookie': 'wtcookie=abc123'});
    });

    test('clearSession wipes both cookie and CSRF token', () {
      client.restoreSession(cookie: 'wtcookie=abc123', csrfToken: 'tok');
      client.clearSession();
      expect(client.hasSession, isFalse);
      expect(client.sessionCookie, isNull);
      expect(client.imageHeaders, isEmpty);
    });
  });

  group('info()', () {
    test('builds the Info module route and returns the parsed body', () async {
      adapter.enqueue(
        _CannedResponse(200, '{"csrf":"tok-1","baseUrl":"https://tree.example.com/","user":{"loggedIn":false}}'),
      );

      final data = await client.info('Famtree');

      expect(data['user'], {'loggedIn': false});
      final uri = adapter.requests.single.uri;
      expect(uri.path, '/index.php');
      expect(uri.queryParameters['route'], '/module/_api4webtrees_/Info/Famtree');
    });

    test('captures the CSRF token and server baseUrl for later requests', () async {
      adapter.enqueue(
        _CannedResponse(200, '{"csrf":"tok-1","baseUrl":"https://real.example.com/"}'),
      );
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.info('Famtree');
      await client.individual('Famtree', 'I1');

      final secondRequestHeaders = adapter.requests[1].headers;
      expect(secondRequestHeaders['X-CSRF-TOKEN'], 'tok-1');
    });

    test('a non-string csrf/baseUrl is ignored rather than crashing', () async {
      adapter.enqueue(_CannedResponse(200, '{"csrf":123,"baseUrl":456}'));
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.info('Famtree');
      await client.individual('Famtree', 'I1');

      expect(adapter.requests[1].headers.containsKey('X-CSRF-TOKEN'), isFalse);
    });

    test('captures the session cookie from Set-Cookie via the response interceptor', () async {
      adapter.enqueue(
        _CannedResponse(
          200,
          '{"csrf":"tok-1"}',
          headers: {
            'content-type': ['application/json'],
            'set-cookie': ['webtrees2=abc123; path=//; HttpOnly'],
          },
        ),
      );

      await client.info('Famtree');

      expect(client.sessionCookie, 'webtrees2=abc123');
      expect(client.hasSession, isTrue);
    });

    test('an established session cookie is sent back on the next request', () async {
      adapter.enqueue(
        _CannedResponse(
          200,
          '{"csrf":"tok-1"}',
          headers: {
            'content-type': ['application/json'],
            'set-cookie': ['webtrees2=abc123; path=//; HttpOnly'],
          },
        ),
      );
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.info('Famtree');
      await client.individual('Famtree', 'I1');

      expect(adapter.requests[1].headers['Cookie'], 'webtrees2=abc123');
    });
  });

  group('login()', () {
    test('posts credentials to /login, form-encoded, and returns true on a 302', () async {
      adapter.enqueue(_CannedResponse(200, '{"csrf":"tok-1","baseUrl":"https://real.example.com/"}'));
      adapter.enqueue(_CannedResponse(302, ''));

      await client.info('Famtree');
      final ok = await client.login(username: 'alice', password: 's3cret');

      expect(ok, isTrue);
      final loginRequest = adapter.requests[1];
      expect(loginRequest.method, 'POST');
      expect(loginRequest.uri.queryParameters['route'], '/login');
      expect(loginRequest.contentType, startsWith('application/x-www-form-urlencoded'));
      expect(loginRequest.data, {
        'username': 'alice',
        'password': 's3cret',
        // The server's own baseUrl (from Info), not the client's configured
        // one - see the docstring on login() for why.
        'url': 'https://real.example.com/',
        '_csrf': 'tok-1',
      });
    });

    test('falls back to the configured baseUrl when info() was never called', () async {
      adapter.enqueue(_CannedResponse(200, ''));

      await client.login(username: 'alice', password: 's3cret');

      expect(adapter.requests.single.data, containsPair('url', 'https://tree.example.com/'));
    });

    test('returns false when the server re-renders the login form instead of redirecting', () async {
      adapter.enqueue(
        _CannedResponse(
          200,
          '<html>bad credentials</html>',
          headers: {'content-type': ['text/html']},
        ),
      );

      final ok = await client.login(username: 'alice', password: 'wrong');

      expect(ok, isFalse);
    });
  });

  group('individuals()', () {
    test('omits the q parameter when no search query is given, defaults page to 1', () async {
      adapter.enqueue(_CannedResponse(200, '{"individuals":[]}'));

      await client.individuals('Famtree');

      final uri = adapter.requests.single.uri;
      expect(uri.queryParameters.containsKey('q'), isFalse);
      expect(uri.queryParameters['page'], '1');
      expect(uri.queryParameters['route'], '/module/_api4webtrees_/Individuals/Famtree');
    });

    test('includes q and page when given, and parses the response', () async {
      adapter.enqueue(_CannedResponse(200, '{"individuals":[{"xref":"I1"}]}'));

      final result = await client.individuals('Famtree', query: 'Müller', page: 3);

      final uri = adapter.requests.single.uri;
      expect(uri.queryParameters['q'], 'Müller');
      expect(uri.queryParameters['page'], '3');
      expect(result['individuals'], [{'xref': 'I1'}]);
    });

    test('an empty query string is treated the same as no query', () async {
      adapter.enqueue(_CannedResponse(200, '{}'));
      await client.individuals('Famtree', query: '');
      expect(adapter.requests.single.uri.queryParameters.containsKey('q'), isFalse);
    });
  });

  group('individual()', () {
    test('passes xref as a query parameter and returns the parsed body', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true,"person":{"xref":"I5"}}'));

      final result = await client.individual('Famtree', 'I5');

      expect(adapter.requests.single.uri.queryParameters['xref'], 'I5');
      expect(result['person'], {'xref': 'I5'});
    });

    test('throws when the response body is not a JSON object', () async {
      adapter.enqueue(_CannedResponse(200, '[1,2,3]'));

      expect(() => client.individual('Famtree', 'I5'), throwsA(isA<TypeError>()));
    });

    test('a 500 response is surfaced as a DioException (error-path)', () async {
      adapter.enqueue(_CannedResponse(500, 'Internal Server Error', headers: {'content-type': ['text/plain']}));

      expect(
        () => client.individual('Famtree', 'I5'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('stale-connection retry (GET only)', () {
    test('a connectionError is retried once, transparently, on a GET', () async {
      adapter.enqueueError(DioExceptionType.connectionError);
      adapter.enqueue(_CannedResponse(200, '{"ok":true,"person":{"xref":"I5"}}'));

      final result = await client.individual('Famtree', 'I5');

      expect(result['person'], {'xref': 'I5'});
      expect(adapter.requests, hasLength(2), reason: 'the failed attempt plus the retry');
    });

    test('"Connection closed before full header was received" (type unknown) is retried too', () async {
      adapter.enqueueError(DioExceptionType.unknown, message: 'Connection closed before full header was received');
      adapter.enqueue(_CannedResponse(200, '{"ok":true,"person":{"xref":"I5"}}'));

      final result = await client.individual('Famtree', 'I5');

      expect(result['person'], {'xref': 'I5'});
      expect(adapter.requests, hasLength(2));
    });

    test('if the retry also fails, the original error surfaces (not a third attempt)', () async {
      adapter.enqueueError(DioExceptionType.connectionError);
      adapter.enqueueError(DioExceptionType.connectionError);

      await expectLater(() => client.individual('Famtree', 'I5'), throwsA(isA<DioException>()));
      expect(adapter.requests, hasLength(2), reason: 'no infinite/third retry');
    });

    test('a POST is never retried, even on a connectionError - only GET is safe to repeat', () async {
      adapter.enqueueError(DioExceptionType.connectionError);

      await expectLater(
        () => client.postFact('Famtree', 'I1', tag: 'BIRT'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('an unrelated error type (e.g. a 500) is not retried', () async {
      adapter.enqueue(_CannedResponse(500, 'Internal Server Error', headers: {'content-type': ['text/plain']}));

      await expectLater(() => client.individual('Famtree', 'I5'), throwsA(isA<DioException>()));
      expect(adapter.requests, hasLength(1));
    });
  });

  group('tags()', () {
    test('defaults to type=INDI', () async {
      adapter.enqueue(_CannedResponse(200, '{"tags":[]}'));
      await client.tags('Famtree');
      expect(adapter.requests.single.uri.queryParameters['type'], 'INDI');
    });

    test('passes a custom type through', () async {
      adapter.enqueue(_CannedResponse(200, '{"tags":["MARR"]}'));
      final result = await client.tags('Famtree', type: 'FAM');
      expect(adapter.requests.single.uri.queryParameters['type'], 'FAM');
      expect(result['tags'], ['MARR']);
    });
  });

  group('updateAccount()', () {
    test('only sends the fields that were provided', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.updateAccount('Famtree', realName: 'Alice A.');
      final request = adapter.requests.single;
      expect(request.data, {'realName': 'Alice A.'});
      expect(request.contentType, startsWith('application/json'));
    });

    test('sends both fields when both are provided', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.updateAccount('Famtree', realName: 'Alice A.', defaultXref: 'I1');
      expect(adapter.requests.single.data, {'realName': 'Alice A.', 'defaultXref': 'I1'});
    });

    test('sends an empty body when nothing was provided', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.updateAccount('Famtree');
      expect(adapter.requests.single.data, <String, dynamic>{});
    });
  });

  group('postFact()', () {
    test('adding a new fact (no factId) puts xref in the query, fields in the body', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.postFact('Famtree', 'I1', tag: 'BIRT', value: '', date: '3 MAY 1980', place: 'Wien');

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['xref'], 'I1');
      expect(request.data, {'tag': 'BIRT', 'value': '', 'date': '3 MAY 1980', 'place': 'Wien'});
      expect(request.data.containsKey('factId'), isFalse);
    });

    test('editing an existing fact includes factId', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.postFact('Famtree', 'I1', factId: 'F1', tag: 'BIRT');
      expect(adapter.requests.single.data, containsPair('factId', 'F1'));
    });
  });

  group('postMedia()', () {
    test('sends a multipart form with the file and optional title', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.postMedia(
        'Famtree',
        'I1',
        bytes: [1, 2, 3],
        filename: 'photo.jpg',
        title: 'Portrait',
      );

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['xref'], 'I1');
      final form = request.data as FormData;
      expect(form.fields, hasLength(1));
      expect(form.fields.single.key, 'title');
      expect(form.fields.single.value, 'Portrait');
      expect(form.files, hasLength(1));
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'photo.jpg');
    });

    test('omits the title field when none is given', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.postMedia('Famtree', 'I1', bytes: [1], filename: 'a.jpg');
      final form = adapter.requests.single.data as FormData;
      expect(form.fields, isEmpty);
    });
  });

  group('postAddIndividual()', () {
    test('sends the full default body for an unlinked individual', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true,"xref":"I9"}'));

      final result = await client.postAddIndividual('Famtree', given: 'Hans', surname: 'Müller');

      expect(adapter.requests.single.data, {
        'relation': 'none',
        'given': 'Hans',
        'surname': 'Müller',
        'sex': 'U',
        'dead': false,
      });
      expect(result['xref'], 'I9');
    });

    test('includes relation/relativeTo/family and optional date/place fields when given', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.postAddIndividual(
        'Famtree',
        relation: 'child',
        relativeTo: 'I1',
        family: 'F1',
        given: 'Eva',
        surname: 'Müller',
        sex: 'F',
        birthDate: '1 JAN 2000',
        birthPlace: 'Graz',
        dead: true,
        deathDate: '1 JAN 2050',
        deathPlace: 'Wien',
        marriageDate: '1 JUN 2020',
        marriagePlace: 'Linz',
      );

      expect(adapter.requests.single.data, {
        'relation': 'child',
        'relativeTo': 'I1',
        'family': 'F1',
        'given': 'Eva',
        'surname': 'Müller',
        'sex': 'F',
        'birthDate': '1 JAN 2000',
        'birthPlace': 'Graz',
        'dead': true,
        'deathDate': '1 JAN 2050',
        'deathPlace': 'Wien',
        'marriageDate': '1 JUN 2020',
        'marriagePlace': 'Linz',
      });
    });
  });

  group('anniversaries()', () {
    test('defaults to 14 days', () async {
      adapter.enqueue(_CannedResponse(200, '{"anniversaries":[]}'));
      await client.anniversaries('Famtree');
      expect(adapter.requests.single.uri.queryParameters['days'], '14');
    });

    test('passes a custom day count and parses the result', () async {
      adapter.enqueue(_CannedResponse(200, '{"anniversaries":[{"xref":"I1"}]}'));
      final result = await client.anniversaries('Famtree', days: 30);
      expect(adapter.requests.single.uri.queryParameters['days'], '30');
      expect(result['anniversaries'], [{'xref': 'I1'}]);
    });
  });

  group('placeAutocomplete()', () {
    test('returns the string list from data on success', () async {
      adapter.enqueue(_CannedResponse(200, '{"data":["Wien","Wien, Austria"]}'));
      final result = await client.placeAutocomplete('Famtree', 'Wi');
      expect(adapter.requests.single.uri.queryParameters['q'], 'Wi');
      expect(result, ['Wien', 'Wien, Austria']);
    });

    test('filters out non-string entries', () async {
      adapter.enqueue(_CannedResponse(200, '{"data":["Wien",42,null]}'));
      final result = await client.placeAutocomplete('Famtree', 'Wi');
      expect(result, ['Wien']);
    });

    test('returns an empty list when data is missing or not a list (malformed response)', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":false}'));
      final result = await client.placeAutocomplete('Famtree', 'Wi');
      expect(result, isEmpty);
    });
  });

  group('webtrees-contribution-request endpoints', () {
    test('createShareRequest posts xref to the CreateRequest route on the share module', () async {
      adapter.enqueue(_CannedResponse(200, '{"url":"https://tree.example.com/s/abc","expires":"2026-01-01"}'));

      final result = await client.createShareRequest('Famtree', 'I1');

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_webtrees-contribution-request_/CreateRequest/Famtree');
      expect(request.data, {'xref': 'I1'});
      expect(result['url'], 'https://tree.example.com/s/abc');
    });

    test('shareRequestEmailTemplate passes the token and parses subject/body', () async {
      adapter.enqueue(_CannedResponse(200, '{"subject":"Hilfe","body":"Hallo {{PERSONAL_MESSAGE}}"}'));

      final result = await client.shareRequestEmailTemplate('Famtree', 'tok-xyz');

      expect(adapter.requests.single.uri.queryParameters['token'], 'tok-xyz');
      expect(result['body'], 'Hallo {{PERSONAL_MESSAGE}}');
    });

    test('sendShareRequestEmail sends all fields, defaulting personalMessage to empty', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.sendShareRequestEmail(
        'Famtree',
        token: 'tok-xyz',
        recipientEmail: 'onkel@example.com',
      );

      expect(adapter.requests.single.data, {
        'token': 'tok-xyz',
        'recipient_email': 'onkel@example.com',
        'personal_message': '',
      });
    });

    test('sendShareRequestEmail includes recipient_name when given', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.sendShareRequestEmail(
        'Famtree',
        token: 'tok-xyz',
        recipientEmail: 'onkel@example.com',
        recipientName: 'Onkel Franz',
        personalMessage: 'Bitte hilf mir',
      );
      expect(adapter.requests.single.data, {
        'token': 'tok-xyz',
        'recipient_email': 'onkel@example.com',
        'recipient_name': 'Onkel Franz',
        'personal_message': 'Bitte hilf mir',
      });
    });

    test('shareRequestUnreadCount parses the unread count', () async {
      adapter.enqueue(_CannedResponse(200, '{"unread":5}'));
      final count = await client.shareRequestUnreadCount('Famtree');
      expect(count, 5);
      expect(
        adapter.requests.single.uri.queryParameters['route'],
        '/module/_webtrees-contribution-request_/RequestNotifications/Famtree',
      );
    });

    test('shareRequestUnreadCount defaults to 0 when unread is missing (malformed response)', () async {
      adapter.enqueue(_CannedResponse(200, '{}'));
      final count = await client.shareRequestUnreadCount('Famtree');
      expect(count, 0);
    });

    test('shareRequestList casts the requests array', () async {
      adapter.enqueue(
        _CannedResponse(200, '{"requests":[{"id":1,"xref":"I1","name":"Anna","status":"pending"}]}'),
      );
      final result = await client.shareRequestList('Famtree');
      expect(result, [{'id': 1, 'xref': 'I1', 'name': 'Anna', 'status': 'pending'}]);
    });

    test('shareRequestDetail sends the id as a string query parameter', () async {
      // Regression coverage for the documented bug: Uri.queryParameters
      // rejects a raw int (throws deep in dart:core), so id must be
      // stringified before it gets there.
      adapter.enqueue(_CannedResponse(200, '{"id":7,"name":"Anna","compare":{}}'));

      final result = await client.shareRequestDetail('Famtree', 7);

      expect(adapter.requests.single.uri.queryParameters['id'], '7');
      expect(result['name'], 'Anna');
    });

    test('shareRequestApply posts id and the accept map', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true,"nextId":8}'));

      final result = await client.shareRequestApply('Famtree', 7, {'name': true, 'birthDate': false});

      expect(adapter.requests.single.data, {
        'id': 7,
        'accept': {'name': true, 'birthDate': false},
      });
      expect(result['nextId'], 8);
    });

    test('shareRequestDelete returns true on a 302 redirect', () async {
      adapter.enqueue(_CannedResponse(302, ''));
      final ok = await client.shareRequestDelete('Famtree', 7);
      expect(ok, isTrue);
      expect(adapter.requests.single.data, {'id': 7});
    });

    test('shareRequestDelete returns false when the server responds with anything else', () async {
      adapter.enqueue(_CannedResponse(200, '{"error":"not found"}'));
      final ok = await client.shareRequestDelete('Famtree', 999);
      expect(ok, isFalse);
    });
  });
}
