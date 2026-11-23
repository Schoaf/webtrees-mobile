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

  group('several cookies', () {
    // Regression coverage for a real bug report: a hoster's own cookie (load
    // balancer, bot protection) replaced the webtrees session cookie, so the
    // login went through but the next request was signed out again.
    _CannedResponse withCookies(List<String> cookies) => _CannedResponse(
      200,
      '{"csrf":"tok-1"}',
      headers: {
        'content-type': ['application/json'],
        'set-cookie': cookies,
      },
    );

    test('keeps every cookie and sends all of them back', () async {
      adapter.enqueue(withCookies(['webtrees2=abc123; path=//; HttpOnly', 'SERVERID=web3; path=/']));
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.info('Famtree');
      await client.individual('Famtree', 'I1');

      expect(adapter.requests[1].headers['Cookie'], 'webtrees2=abc123; SERVERID=web3');
    });

    test('a later cookie of another name keeps the session', () async {
      adapter.enqueue(withCookies(['webtrees2=abc123; path=//']));
      adapter.enqueue(withCookies(['__cf_bm=xyz; path=/']));

      await client.info('Famtree');
      await client.info('Famtree');

      expect(client.sessionCookie, 'webtrees2=abc123; __cf_bm=xyz');
    });

    test('a new value replaces the old one, a deleted cookie goes', () async {
      adapter.enqueue(withCookies(['webtrees2=abc123; path=//', 'SERVERID=web3']));
      adapter.enqueue(withCookies(['webtrees2=new456; path=//', 'SERVERID=deleted; Max-Age=0']));

      await client.info('Famtree');
      await client.info('Famtree');

      expect(client.sessionCookie, 'webtrees2=new456');
    });

    test('restoreSession takes several cookies', () {
      client.restoreSession(cookie: 'webtrees2=abc123; SERVERID=web3');

      expect(client.sessionCookie, 'webtrees2=abc123; SERVERID=web3');
      expect(client.imageHeaders, {'Cookie': 'webtrees2=abc123; SERVERID=web3'});
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

  group('pair()', () {
    test('posts the code as JSON to the Pair route, with no tree segment', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true,"tree":"Famtree","user":"alice"}'));

      final result = await client.pair('a' * 48);

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/Pair');
      expect(request.contentType, startsWith('application/json'));
      expect(request.data, {'code': 'a' * 48});
      expect(result, {'ok': true, 'tree': 'Famtree', 'user': 'alice'});
    });

    test('an invalid/expired code returns {ok: false, error} rather than throwing', () async {
      adapter.enqueue(_CannedResponse(403, '{"ok":false,"error":"pair-expired","status":403}'));

      final result = await client.pair('deadbeef');

      expect(result['ok'], isFalse);
      expect(result['error'], 'pair-expired');
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

  group('pretty URLs', () {
    test('a redirected Info switches to the pretty form and asks again', () async {
      adapter.enqueue(_CannedResponse(308, '', headers: {'location': ['https://elsewhere/'], 'content-type': ['text/html']}));
      adapter.enqueue(_CannedResponse(200, '{"csrf":"t","rewriteUrls":true}'));
      await client.info(null);
      expect(client.usePrettyUrls, isTrue);
      expect(adapter.requests.last.uri.path, endsWith('/module/_api4webtrees_/Info'));
      expect(adapter.requests.last.uri.queryParameters.containsKey('route'), isFalse);
    });

    test('a 404 in the pretty form goes back to index.php', () async {
      final html = {'content-type': ['text/html; charset=iso-8859-1']};
      adapter.enqueue(_CannedResponse(302, '', headers: {'location': ['https://elsewhere/'], ...html}));
      adapter.enqueue(_CannedResponse(404, 'Not Found', headers: html));
      await expectLater(client.info('Famtree'), throwsA(isA<UnexpectedResponseException>()));
      expect(client.usePrettyUrls, isTrue);

      adapter.enqueue(_CannedResponse(404, 'Not Found', headers: html));
      adapter.enqueue(_CannedResponse(200, '{"csrf":"t","rewriteUrls":false}'));
      await client.info('Famtree');
      expect(client.usePrettyUrls, isFalse);
      expect(adapter.requests.last.uri.queryParameters['route'], '/module/_api4webtrees_/Info/Famtree');
    });
  });

  group('language', () {
    test('sends the app language as lang with every request', () async {
      client.language = 'en';
      adapter.enqueue(_CannedResponse(200, '{"person":{}}'));
      await client.individual('Famtree', 'I1');
      expect(adapter.requests.single.uri.queryParameters['lang'], 'en');
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

      expect(() => client.individual('Famtree', 'I5'), throwsA(isA<UnexpectedResponseException>()));
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

  group('setStartPerson() / updateRealName()', () {
    test('setStartPerson posts the xref to StartPerson on the tree', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.setStartPerson('Famtree', 'I1');
      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/StartPerson/Famtree');
      expect(request.data, {'xref': 'I1'});
    });

    test('updateRealName posts to MyAccount without a tree', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.updateRealName('Alice A.');
      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/MyAccount');
      expect(request.data, {'realName': 'Alice A.'});
    });

    test('an HTML error page becomes a catchable exception, not a TypeError', () async {
      adapter.enqueue(_CannedResponse(404, '<html>Not found</html>', headers: {'content-type': ['text/html']}));
      expect(client.updateRealName('Alice A.'), throwsA(isA<UnexpectedResponseException>()));
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

    test('a name sends only the changed parts, none at all when nothing changed (#28)', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.postFact('Famtree', 'I1', factId: 'n1', tag: 'NAME', value: 'Hans /Beispiel/', nameParts: {'surname': 'Beispiel'});
      await client.postFact('Famtree', 'I1', factId: 'n1', tag: 'NAME', value: 'Hans /Beispiel/', nameParts: {});

      expect(adapter.requests[0].data, containsPair('nameParts', {'surname': 'Beispiel'}));
      expect(adapter.requests[1].data.containsKey('nameParts'), isFalse);
    });
  });

  group('register()', () {
    test('posts the Register action with every field in the JSON body', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      final result = await client.register(
        'Famtree',
        username: 'anna',
        email: 'anna@example.com',
        realName: 'Anna Muster',
        password: 'hunter22',
        comments: 'Ich bin die Enkelin von Franz Muster.',
      );

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/Register/Famtree');
      expect(request.data, {
        'username': 'anna',
        'email': 'anna@example.com',
        'realName': 'Anna Muster',
        'password': 'hunter22',
        'comments': 'Ich bin die Enkelin von Franz Muster.',
      });
      expect(result, {'ok': true});
    });

    test('returns the parsed error body on failure, without throwing', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":false,"error":"username-taken","status":400}'));

      final result = await client.register(
        'Famtree',
        username: 'anna',
        email: 'anna@example.com',
        realName: 'Anna Muster',
        password: 'hunter22',
        comments: 'x',
      );

      expect(result, {'ok': false, 'error': 'username-taken', 'status': 400});
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

    test('sends the description and the kind of media (#38)', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.postMedia('Famtree', 'I1', bytes: [1], filename: 'a.jpg', note: 'Pfarramt', type: 'document');
      final form = adapter.requests.single.data as FormData;
      expect(Map.fromEntries(form.fields), {'note': 'Pfarramt', 'type': 'document'});
    });

    test('omits the title field when none is given', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      await client.postMedia('Famtree', 'I1', bytes: [1], filename: 'a.jpg');
      final form = adapter.requests.single.data as FormData;
      expect(form.fields, isEmpty);
    });
  });

  group('postPrimaryMedia()', () {
    test('posts the media xref for the person (#34)', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.postPrimaryMedia('Famtree', 'I1', media: 'M5');

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/PrimaryMedia/Famtree');
      expect(request.uri.queryParameters['xref'], 'I1');
      expect(request.data, {'media': 'M5'});
    });
  });

  group('postUnlinkMedia()', () {
    test('posts the media xref to remove from the person (#35)', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.postUnlinkMedia('Famtree', 'I1', media: 'M5');

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/UnlinkMedia/Famtree');
      expect(request.uri.queryParameters['xref'], 'I1');
      expect(request.data, {'media': 'M5'});
    });
  });

  group('photo marking (#37)', () {
    test('mediaObject() gets who is on a photo', () async {
      adapter.enqueue(_CannedResponse(200, '{"xref":"M5","people":[]}'));

      final result = await client.mediaObject('Famtree', 'M5');

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/MediaObject/Famtree');
      expect(request.uri.queryParameters['xref'], 'M5');
      expect(result['xref'], 'M5');
    });

    test('postMediaRotate() turns the media object (#40)', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.postMediaRotate('Famtree', 'M5', quarterTurns: 1);

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/MediaRotate/Famtree');
      expect(request.uri.queryParameters['xref'], 'M5');
      expect(request.data, {'quarterTurns': 1});
    });

    test('postMediaCrop() posts the crop, or null to remove it', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      await client.postMediaCrop('Famtree', 'I1', media: 'M5', crop: {'top': 1, 'left': 2, 'height': 3, 'width': 4});
      await client.postMediaCrop('Famtree', 'I1', media: 'M5', crop: null);

      expect(adapter.requests[0].uri.queryParameters['route'], '/module/_api4webtrees_/MediaCrop/Famtree');
      expect(adapter.requests[0].uri.queryParameters['xref'], 'I1');
      expect(adapter.requests[0].data, {
        'media': 'M5',
        'crop': {'top': 1, 'left': 2, 'height': 3, 'width': 4},
      });
      expect(adapter.requests[1].data, {'media': 'M5', 'crop': null});
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

  group('family-health endpoints (#54)', () {
    test('familyHistory() asks the module, for another individual only when given', () async {
      adapter.enqueue(_CannedResponse(200, '{"xref":"I3","illnesses":[]}'));
      adapter.enqueue(_CannedResponse(200, '{"xref":"I6","illnesses":[]}'));

      final own = await client.familyHistory('Famtree');
      final child = await client.familyHistory('Famtree', xref: 'I6');

      expect(adapter.requests[0].uri.queryParameters['route'], '/module/_family-health_/FamilyHistory/Famtree');
      expect(adapter.requests[0].uri.queryParameters.containsKey('xref'), isFalse);
      expect(adapter.requests[1].uri.queryParameters['xref'], 'I6');
      expect(own['xref'], 'I3');
      expect(child['xref'], 'I6');
    });

    test('familyHealthIllnesses() and familyHealthCatalog() read their routes', () async {
      adapter.enqueue(_CannedResponse(200, '{"illnesses":[{"xref":"I2","category":"cancer"}]}'));
      adapter.enqueue(_CannedResponse(200, '{"categories":[{"id":"cancer","name":"Krebs"}]}'));

      final illnesses = await client.familyHealthIllnesses('Famtree');
      final catalog = await client.familyHealthCatalog('Famtree');

      expect(adapter.requests[0].uri.queryParameters['route'], '/module/_family-health_/Illnesses/Famtree');
      expect(adapter.requests[1].uri.queryParameters['route'], '/module/_family-health_/Catalog/Famtree');
      expect((illnesses['illnesses'] as List).single['xref'], 'I2');
      expect((catalog['categories'] as List).single['name'], 'Krebs');
    });

    test('the illnesses of one person: read, change, delete', () async {
      adapter.enqueue(_CannedResponse(200, '{"illnesses":[{"id":"f1","illness":"Asthma"}],"canEdit":true}'));
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      final read = await client.familyHealthPersonIllnesses('Famtree', 'I2');
      await client.postFamilyHealthIllnessUpdate('Famtree', 'I2', id: 'f1', illness: 'Asthma', date: '1990');
      await client.postFamilyHealthIllnessDelete('Famtree', 'I2', id: 'f1');

      expect(adapter.requests[0].uri.queryParameters['route'], '/module/_family-health_/PersonIllnesses/Famtree');
      expect(adapter.requests[0].uri.queryParameters['xref'], 'I2');
      expect(read['canEdit'], isTrue);
      expect(adapter.requests[1].uri.queryParameters['route'], '/module/_family-health_/IllnessUpdate/Famtree');
      expect(adapter.requests[1].data, {'xref': 'I2', 'id': 'f1', 'illness': 'Asthma', 'date': '1990'});
      expect(adapter.requests[2].uri.queryParameters['route'], '/module/_family-health_/IllnessDelete/Famtree');
      expect(adapter.requests[2].data, {'xref': 'I2', 'id': 'f1'});
    });

    test('participation: read and set', () async {
      adapter.enqueue(_CannedResponse(200, '{"subjects":[{"xref":"I3","isOptedOut":false}],"canManage":false}'));
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));

      final read = await client.familyHealthParticipation('Famtree');
      await client.postFamilyHealthParticipation('Famtree', 'I3', isOptedOut: true);

      expect(adapter.requests[0].uri.queryParameters['route'], '/module/_family-health_/Participation/Famtree');
      expect((read['subjects'] as List).single['xref'], 'I3');
      expect(adapter.requests[1].method, 'POST');
      expect(adapter.requests[1].data, {'xref': 'I3', 'isOptedOut': true});
    });

    test('postFamilyHealthIllness() posts JSON, leaving out what is not given', () async {
      adapter.enqueue(_CannedResponse(200, '{"ok":true}'));
      adapter.enqueue(_CannedResponse(400, '{"ok":false,"error":"Nicht erlaubt"}'));

      final saved = await client.postFamilyHealthIllness('Famtree', 'I2', illness: 'Asthma', date: '1990', category: 'other');
      final rejected = await client.postFamilyHealthIllness('Famtree', 'I2', illness: 'Asthma');

      expect(adapter.requests[0].method, 'POST');
      expect(adapter.requests[0].uri.queryParameters['route'], '/module/_family-health_/Illness/Famtree');
      expect(adapter.requests[0].contentType, startsWith('application/json'));
      expect(adapter.requests[0].data, {'xref': 'I2', 'illness': 'Asthma', 'date': '1990', 'category': 'other'});
      expect(adapter.requests[1].data, {'xref': 'I2', 'illness': 'Asthma'});
      expect(saved['ok'], isTrue);
      expect(rejected, {'ok': false, 'error': 'Nicht erlaubt'});
    });
  });

  group('pedigree() and descendants()', () {
    test('send the individual and the number of generations', () async {
      adapter.enqueue(_CannedResponse(200, '{"ancestors":[]}'));
      adapter.enqueue(_CannedResponse(200, '{"xref":"I1"}'));

      await client.pedigree('Famtree', 'I1', 4);
      await client.descendants('Famtree', 'I1', 3);

      expect(adapter.requests[0].uri.queryParameters['route'], '/module/_api4webtrees_/Pedigree/Famtree');
      expect(adapter.requests[0].uri.queryParameters['generations'], '4');
      expect(adapter.requests[1].uri.queryParameters['route'], '/module/_api4webtrees_/Descendants/Famtree');
      expect(adapter.requests[1].uri.queryParameters['xref'], 'I1');
      expect(adapter.requests[1].uri.queryParameters['generations'], '3');
    });
  });

  group('canOpenLinksInApp()', () {
    _CannedResponse page(String body) => _CannedResponse(200, body, headers: {'content-type': ['text/html']});

    test('true when the App page has the set-up for this app', () async {
      adapter.enqueue(page('<form><input name="all" value="always"></form>'));

      expect(await client.canOpenLinksInApp('Famtree'), isTrue);
      final request = adapter.requests.single;
      expect(request.uri.queryParameters['route'], '/module/_api4webtrees_/App/Famtree');
      expect(request.uri.queryParameters['open-in'], isNotEmpty);
      expect(request.headers['User-Agent'], startsWith('webtrees-mobile ('));
    });

    test('false on an older module without it', () async {
      adapter.enqueue(page('<p>webtrees app</p>'));

      expect(await client.canOpenLinksInApp('Famtree'), isFalse);
    });
  });

  group('isWebtrees()', () {
    _CannedResponse text(int status, String body) => _CannedResponse(status, body, headers: {'content-type': ['text/plain']});

    test('OK from /ping is webtrees', () async {
      adapter.enqueue(text(200, 'OK'));

      expect(await client.isWebtrees(), isTrue);
      expect(adapter.requests.single.uri.queryParameters['route'], '/ping');
    });

    test('a redirect switches to pretty URLs and asks again', () async {
      adapter.enqueue(_CannedResponse(302, '', headers: {'location': ['https://tree.example.com/ping']}));
      adapter.enqueue(text(200, 'WARNING'));

      expect(await client.isWebtrees(), isTrue);
      expect(client.usePrettyUrls, isTrue);
      expect(adapter.requests, hasLength(2));
    });

    test('a wrong pretty guess goes back to index.php', () async {
      client.usePrettyUrls = true;
      adapter.enqueue(text(404, 'Not Found'));
      adapter.enqueue(text(200, 'OK'));

      expect(await client.isWebtrees(), isTrue);
      expect(client.usePrettyUrls, isFalse);
      expect(adapter.requests.last.uri.queryParameters['route'], '/ping');
    });

    test('ERROR comes as 503 and is still webtrees, anything else is not', () async {
      adapter.enqueue(text(503, 'ERROR'));
      adapter.enqueue(text(200, '<html>some other site</html>'));

      expect(await client.isWebtrees(), isTrue);
      expect(await client.isWebtrees(), isFalse);
    });
  });

  test('UnexpectedResponseException names the HTTP status', () {
    expect(const UnexpectedResponseException(404).toString(), contains('HTTP 404'));
    expect(const UnexpectedResponseException(null).toString(), contains('HTTP ?'));
  });
}
