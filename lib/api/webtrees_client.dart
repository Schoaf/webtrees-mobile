import 'package:dio/dio.dart';

/// Talks to a webtrees instance's `webtreesand-api` module.
///
/// webtrees uses session-cookie auth (`GET Info` for a CSRF token, `POST
/// /login`, then `X-CSRF-TOKEN` on writes). We manage the session cookie
/// manually instead of using a standard RFC 6265 cookie jar: webtrees emits
/// `Set-Cookie` with `path=//` for any site installed at its domain root
/// (see fisharebest/webtrees Session.php — path is built as `$path . '/'`
/// where `$path` is already `/`). Strict cookie jars refuse to resend a
/// cookie whose path doesn't prefix-match the request path, so `//` silently
/// breaks the session. Until that's fixed upstream, every real-world
/// instance can hit this, so we just track the raw cookie ourselves.
class WebtreesClient {
  WebtreesClient({required String baseUrl})
    : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
          // The only redirect we ever get is login's 302, and it redirects
          // to the *server's* base_url — unreachable from behind a NAT
          // alias like the Android emulator's 10.0.2.2. We only care about
          // the status code, never the redirect target, so don't follow it.
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_cookie != null) {
            options.headers['Cookie'] = _cookie;
          }
          if (_csrfToken != null) {
            options.headers['X-CSRF-TOKEN'] = _csrfToken;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          _captureCookie(response);
          handler.next(response);
        },
        onError: (error, handler) {
          if (error.response != null) {
            _captureCookie(error.response!);
          }
          handler.next(error);
        },
      ),
    );
  }

  final String _baseUrl;
  final Dio _dio;

  String? _cookie;
  String? _csrfToken;
  String? _serverBaseUrl;

  bool get hasSession => _cookie != null;

  void _captureCookie(Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    // Keep only the "name=value" pair, drop path/domain/flags — we send it
    // back verbatim on every request regardless of path, sidestepping the
    // path=// bug entirely.
    _cookie = setCookie.last.split(';').first;
  }

  /// Restore a previously-saved session cookie (e.g. from secure storage) so
  /// the user doesn't have to log in again on every app launch.
  void restoreSession({required String cookie, String? csrfToken}) {
    _cookie = cookie;
    _csrfToken = csrfToken;
  }

  String? get sessionCookie => _cookie;

  void clearSession() {
    _cookie = null;
    _csrfToken = null;
  }

  /// Headers to pass to `Image.network`/`NetworkImage` so photo requests
  /// carry the same session — Flutter's image loader doesn't go through
  /// this client's Dio instance (and its cookie interceptor) on its own.
  Map<String, String> get imageHeaders => {
    if (_cookie != null) 'Cookie': _cookie!,
  };

  /// webtrees names every custom module's route `_<folder-name>_`
  /// (ModuleService::customModules) regardless of what the README shows for
  /// readability — `modules_v4/webtrees-contribution-request` really is `_webtrees-contribution-request_`
  /// on the wire, same as `_webtreesand-api_`.
  Uri _moduleUri(
    String action,
    String tree, [
    Map<String, dynamic>? query,
    String moduleSlug = '_webtreesand-api_',
  ]) {
    return Uri.parse(_baseUrl).replace(
      path: '${Uri.parse(_baseUrl).path}index.php',
      queryParameters: {
        'route': '/module/$moduleSlug/$action/$tree',
        ...?query,
      },
    );
  }

  Uri _shareModuleUri(
    String action,
    String tree, [
    Map<String, dynamic>? query,
  ]) => _moduleUri(action, tree, query, '_webtrees-contribution-request_');

  /// `GET Info` — also the way we discover/refresh the CSRF token and the
  /// server's own idea of its base URL (see [login]).
  Future<Map<String, dynamic>> info(String tree) async {
    final response = await _dio.getUri(_moduleUri('Info', tree));
    final data = response.data as Map<String, dynamic>;
    final csrf = data['csrf'];
    if (csrf is String) {
      _csrfToken = csrf;
    }
    final baseUrl = data['baseUrl'];
    if (baseUrl is String && baseUrl.isNotEmpty) {
      _serverBaseUrl = baseUrl;
    }
    return data;
  }

  /// Logs in with a webtrees username/password. Call [info] first (on this
  /// same client instance) so a CSRF token and session cookie already exist
  /// — webtrees' CheckCsrf middleware rejects the login POST otherwise.
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    // webtrees validates `url` with `str_starts_with($url, $base_url)`,
    // where $base_url is the server's *own* configured base_url — not
    // whatever host/port the client happened to connect through. Those
    // differ whenever there's a NAT alias or proxy in between (e.g. the
    // Android emulator's 10.0.2.2), so send the server's own baseUrl (from
    // Info) rather than our locally-configured one, or the login gets
    // rejected with "The parameter 'url' is invalid" before it even reaches
    // the credential check.
    final loginUrl = _serverBaseUrl ?? _baseUrl;
    final response = await _dio.post(
      'index.php',
      queryParameters: {'route': '/login'},
      data: {
        'username': username,
        'password': password,
        'url': loginUrl,
        '_csrf': _csrfToken,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    // Success is a 302 redirect back to the site; failure re-renders the
    // login form (200) with a flash message, or 400 on a bad/missing CSRF.
    return response.statusCode == 302;
  }

  Future<Map<String, dynamic>> individuals(
    String tree, {
    String? query,
    int page = 1,
  }) async {
    final response = await _dio.getUri(
      _moduleUri('Individuals', tree, {
        if (query != null && query.isNotEmpty) 'q': query,
        'page': '$page',
      }),
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> individual(String tree, String xref) async {
    final response = await _dio.getUri(
      _moduleUri('Individual', tree, {'xref': xref}),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Labelled list of fact types the app can offer to add, e.g. for a quick
  /// "pick a fact type" chooser. [type] is `INDI` or `FAM`.
  Future<Map<String, dynamic>> tags(String tree, {String type = 'INDI'}) async {
    final response = await _dio.getUri(
      _moduleUri('Tags', tree, {'type': type}),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Updates the logged-in user's own account: display name and/or which
  /// person is the tree's Startperson. Deliberately doesn't cover which
  /// person the account is *linked* to — in webtrees itself that's an
  /// admin-only setting (user management), not self-service.
  Future<Map<String, dynamic>> updateAccount(
    String tree, {
    String? realName,
    String? defaultXref,
  }) async {
    final response = await _dio.postUri(
      _moduleUri('Account', tree),
      data: {
        if (realName != null) 'realName': realName,
        if (defaultXref != null) 'defaultXref': defaultXref,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Adds or edits a single fact. Omit [factId] to add a new fact.
  Future<Map<String, dynamic>> postFact(
    String tree,
    String xref, {
    String? factId,
    required String tag,
    String? value,
    String? date,
    String? place,
  }) async {
    final response = await _dio.postUri(
      _moduleUri('Fact', tree, {'xref': xref}),
      data: {
        if (factId != null) 'factId': factId,
        'tag': tag,
        if (value != null) 'value': value,
        if (date != null) 'date': date,
        if (place != null) 'place': place,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Uploads a photo and links it to [xref] as its highlighted media.
  Future<Map<String, dynamic>> postMedia(
    String tree,
    String xref, {
    required List<int> bytes,
    required String filename,
    String? title,
  }) async {
    final form = FormData.fromMap({
      if (title != null) 'title': title,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.postUri(
      _moduleUri('Media', tree, {'xref': xref}),
      data: form,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Creates a new individual, optionally linked to [relativeTo] as their
  /// child, spouse, father or mother. `relation: 'none'` (the default)
  /// creates an unlinked individual.
  Future<Map<String, dynamic>> postAddIndividual(
    String tree, {
    String relation = 'none',
    String? relativeTo,
    String? family,
    required String given,
    required String surname,
    String sex = 'U',
    String? birthDate,
    String? birthPlace,
    bool dead = false,
    String? deathDate,
    String? deathPlace,
    String? marriageDate,
    String? marriagePlace,
  }) async {
    final response = await _dio.postUri(
      _moduleUri('AddIndividual', tree),
      data: {
        'relation': relation,
        if (relativeTo != null) 'relativeTo': relativeTo,
        if (family != null) 'family': family,
        'given': given,
        'surname': surname,
        'sex': sex,
        if (birthDate != null) 'birthDate': birthDate,
        if (birthPlace != null) 'birthPlace': birthPlace,
        'dead': dead,
        if (deathDate != null) 'deathDate': deathDate,
        if (deathPlace != null) 'deathPlace': deathPlace,
        if (marriageDate != null) 'marriageDate': marriageDate,
        if (marriagePlace != null) 'marriagePlace': marriagePlace,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Upcoming birthdays/anniversaries within [days] days, soonest first.
  Future<Map<String, dynamic>> anniversaries(
    String tree, {
    int days = 14,
  }) async {
    final response = await _dio.getUri(
      _moduleUri('Anniversaries', tree, {'days': '$days'}),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Place-name suggestions from the tree's own places, up to 20 — the
  /// `webtreesand-api` module's own endpoint (API level 8+), not webtrees
  /// core's `/autocomplete/place` route. That route isn't a documented,
  /// stable API and the module's README warns it can change with webtrees
  /// 2.3; `Places` is versioned and meant for exactly this. Requires editor
  /// rights on [tree].
  Future<List<String>> placeAutocomplete(String tree, String query) async {
    final response = await _dio.getUri(
      _moduleUri('Places', tree, {'q': query}),
    );
    final data = (response.data as Map<String, dynamic>?)?['data'];
    if (data is! List) return [];
    return data.whereType<String>().toList();
  }

  // --- webtrees-contribution-request: "ask a relative to help" (separate, optional module,
  // not to be confused with the plain-link/text share in person_detail) ---

  /// Snapshots [xref]'s key facts and creates a share request for it.
  /// Returns `{url, expires}`. Requires editor rights on the record.
  Future<Map<String, dynamic>> createShareRequest(
    String tree,
    String xref,
  ) async {
    final response = await _dio.postUri(
      _shareModuleUri('CreateRequest', tree),
      data: {'xref': xref},
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data as Map<String, dynamic>;
  }

  /// The canonical subject/body for the "please help" email, `body`
  /// containing a `{{PERSONAL_MESSAGE}}` marker to fill in before sending —
  /// for previewing/editing the message before [sendShareRequestEmail].
  Future<Map<String, dynamic>> shareRequestEmailTemplate(
    String tree,
    String token,
  ) async {
    final response = await _dio.getUri(
      _shareModuleUri('RequestEmailTemplate', tree, {'token': token}),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Sends the request by email — server-rendered, so [personalMessage] is
  /// the only free text the client contributes; subject/body always come
  /// from the server.
  Future<Map<String, dynamic>> sendShareRequestEmail(
    String tree, {
    required String token,
    required String recipientEmail,
    String? recipientName,
    String personalMessage = '',
  }) async {
    final response = await _dio.postUri(
      _shareModuleUri('SendRequestEmail', tree),
      data: {
        'token': token,
        'recipient_email': recipientEmail,
        if (recipientName != null) 'recipient_name': recipientName,
        'personal_message': personalMessage,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data as Map<String, dynamic>;
  }

  /// `{unread}` — how many share-request answers are waiting for review.
  Future<int> shareRequestUnreadCount(String tree) async {
    final response = await _dio.getUri(
      _shareModuleUri('RequestNotifications', tree),
    );
    return (response.data as Map<String, dynamic>)['unread'] as int? ?? 0;
  }

  /// `{requests: [{id, xref, name, status, respondedAt}, ...]}` — the
  /// creator's own answered/applied share requests, for the native
  /// "Antworten" review screen.
  Future<List<Map<String, dynamic>>> shareRequestList(String tree) async {
    final response = await _dio.getUri(_shareModuleUri('RequestList', tree));
    final data = response.data as Map<String, dynamic>;
    return (data['requests'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// `{id, name, applied, compare: {FIELD: {before, after}}, note, photoUrl}`
  /// for one request — the before/after fields a guest changed, ready to
  /// review and selectively accept.
  Future<Map<String, dynamic>> shareRequestDetail(String tree, int id) async {
    // Uri's queryParameters only accepts String/Iterable<String> values - an
    // int here throws "type 'int' is not a subtype of type 'Iterable<...>'"
    // deep inside dart:core, which is exactly what surfaced as "Konnte
    // nicht laden" with no useful detail.
    final response = await _dio.getUri(
      _shareModuleUri('RequestDetail', tree, {'id': '$id'}),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Applies exactly the fields/note/photo in [accept] (a `{key: true}` map
  /// for whatever the reviewer ticked) to the tree, under the reviewer's own
  /// session. Returns `{ok, nextId}` — `nextId` is the next request still
  /// waiting for review, or null once none are left.
  Future<Map<String, dynamic>> shareRequestApply(
    String tree,
    int id,
    Map<String, bool> accept,
  ) async {
    final response = await _dio.postUri(
      _shareModuleUri('RequestApply', tree),
      data: {'id': id, 'accept': accept},
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Discards a request entirely (the row and any photo files it's
  /// holding) under the reviewer's own session. Same endpoint the web
  /// "Verwerfen" form posts to — it always responds with a redirect, so
  /// (like [login]) success is just the status code, not a JSON body.
  Future<bool> shareRequestDelete(String tree, int id) async {
    final response = await _dio.postUri(
      _shareModuleUri('RequestDelete', tree),
      data: {'id': id},
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.statusCode == 302;
  }
}
