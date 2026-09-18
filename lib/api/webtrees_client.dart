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
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
          // The only redirect we ever get is login's 302, and it redirects
          // to the *server's* base_url — unreachable from behind a NAT
          // alias like the Android emulator's 10.0.2.2. We only care about
          // the status code, never the redirect target, so don't follow it.
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
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
    ));
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

  Uri _moduleUri(String action, String tree, [Map<String, dynamic>? query]) {
    return Uri.parse(_baseUrl).replace(
      path: '${Uri.parse(_baseUrl).path}index.php',
      queryParameters: {
        'route': '/module/_webtreesand-api_/$action/$tree',
        ...?query,
      },
    );
  }

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

  Future<Map<String, dynamic>> individuals(String tree, {String? query, int page = 1}) async {
    final response = await _dio.getUri(_moduleUri('Individuals', tree, {
      if (query != null && query.isNotEmpty) 'q': query,
      'page': '$page',
    }));
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> individual(String tree, String xref) async {
    final response = await _dio.getUri(_moduleUri('Individual', tree, {'xref': xref}));
    return response.data as Map<String, dynamic>;
  }

  /// Labelled list of fact types the app can offer to add, e.g. for a quick
  /// "pick a fact type" chooser. [type] is `INDI` or `FAM`.
  Future<Map<String, dynamic>> tags(String tree, {String type = 'INDI'}) async {
    final response = await _dio.getUri(_moduleUri('Tags', tree, {'type': type}));
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
}
