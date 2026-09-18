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
          followRedirects: true,
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

  /// `GET Info` — also the way we discover/refresh the CSRF token.
  Future<Map<String, dynamic>> info(String tree) async {
    final response = await _dio.getUri(_moduleUri('Info', tree));
    final data = response.data as Map<String, dynamic>;
    final csrf = data['csrf'];
    if (csrf is String) {
      _csrfToken = csrf;
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
    final loginUrl = Uri.parse(_baseUrl);
    final response = await _dio.post(
      'index.php',
      queryParameters: {'route': '/login'},
      data: {
        'username': username,
        'password': password,
        'url': loginUrl.toString(),
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
}
