import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'diagnostic_log_enabled';
const _fileName = 'diagnostic.log';

/// Past this size the oldest half of the log goes.
const _maxBytes = 512 * 1024;

/// Longest error message kept - a message can quote what it failed on.
const _maxMessageLength = 300;

/// Query parameters whose values are kept in a logged URL; every other
/// value (a search term, a name ...) becomes `…`.
const _keptQueryParameters = {'route', 'lang'};

/// An opt-in log the user can send to the developer when something goes
/// wrong: errors with stack traces, the app's own output and every request
/// (method, path, status, duration, size, cookie names). Never contents,
/// passwords, cookie values or tokens. Off until the user turns it on - and
/// collects nothing before; turning it off deletes it.
class DiagnosticLog {
  DiagnosticLog._();

  static final instance = DiagnosticLog._();

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  File? _file;

  /// Writes go one after another, never two at once.
  Future<void> _pending = Future.value();

  /// Errors already logged, so a builder that rebuilds with the same error
  /// doesn't log it again and again.
  final _loggedErrors = Expando<bool>();

  /// Test-only: a log in [directory], on or off.
  @visibleForTesting
  Future<void> debugSetUp({required Directory directory, required bool isEnabled}) async {
    _file = File('${directory.path}/$_fileName');
    _isEnabled = isEnabled;
    _pending = Future.value();
  }

  /// Reads whether the user turned it on - before anything is logged.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefKey) ?? false;
      if (_isEnabled) await _openFile();
    } on Exception {
      _isEnabled = false;
    }
  }

  Future<void> setEnabled(bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, isEnabled);
    _isEnabled = isEnabled;
    if (isEnabled) {
      await _openFile();
      info('Diagnostic log turned on');
    } else {
      await _pending;
      final file = _file;
      if (file != null && await file.exists()) await file.delete();
    }
  }

  Future<void> _openFile() async {
    if (_file != null) return;
    final directory = await getApplicationSupportDirectory();
    _file = File('${directory.path}/$_fileName');
  }

  void info(String message) => _write('INFO', message);

  /// Logs [error] where it was caught ([where]) with its stack trace.
  void error(String where, Object error, [StackTrace? stackTrace]) {
    if (!_isEnabled) return;
    try {
      if (_loggedErrors[error] == true) return;
      _loggedErrors[error] = true;
    } on ArgumentError {
      // Strings, numbers ... can't be marked - log them every time.
    }
    final trace = stackTrace == null ? '' : '\n${_shortStackTrace(stackTrace)}';
    _write('ERROR', '$where: ${describeError(error)}$trace');
  }

  /// One request: `GET /path?route=… 200 123ms application/json 4.5 kB cookies: a, b`.
  void request(RequestOptions options, {Response<dynamic>? response, DioException? error, Duration? duration}) {
    if (!_isEnabled) return;
    final parts = <String>[options.method, describeUrl(options.uri)];
    if (response?.statusCode case final status?) parts.add('$status');
    if (duration != null) parts.add('${duration.inMilliseconds}ms');
    if (response?.headers.value('content-type') case final contentType?) parts.add(contentType);
    if (response?.headers.value('content-length') case final length?) parts.add('$length B');
    if (response?.headers.value('location') case final location?) parts.add('-> ${describeUrl(Uri.parse(location))}');
    final cookieNames = [
      for (final header in response?.headers['set-cookie'] ?? const <String>[]) header.split('=').first.trim(),
    ];
    if (cookieNames.isNotEmpty) parts.add('cookies: ${cookieNames.join(', ')}');
    if (error != null) parts.add('${error.type.name}: ${_shorten('${error.error ?? error.message ?? ''}')}');
    _write(error == null ? 'HTTP' : 'HTTP-ERROR', parts.join(' '));
  }

  /// The whole log for sending, with the device and app in its first line.
  Future<File?> fileToSend({required String header}) async {
    await _pending;
    final file = _file;
    if (file == null || !await file.exists()) return null;
    final sendFile = File('${file.parent.path}/webtrees-mobile-diagnostic.txt');
    await sendFile.writeAsString('$header\n\n${await file.readAsString()}');
    return sendFile;
  }

  void _write(String level, String message) {
    if (!_isEnabled) return;
    final line = '${DateTime.now().toIso8601String()} $level $message\n';
    _pending = _pending.then((_) => _append(line)).catchError((Object _) {});
  }

  Future<void> _append(String line) async {
    final file = _file;
    if (file == null) return;
    await file.writeAsString(line, mode: FileMode.append, flush: true);
    if (await file.length() > _maxBytes) {
      final text = await file.readAsString();
      final cut = text.indexOf('\n', text.length ~/ 2);
      await file.writeAsString(text.substring(cut + 1));
    }
  }

  /// The error's type and message - without what a [FormatException]
  /// quotes from its input (that could be a person's data), and shortened.
  @visibleForTesting
  static String describeError(Object error) => switch (error) {
    FormatException(:final message) => 'FormatException: ${_shorten(message)}',
    DioException(:final type, :final response, :final requestOptions) =>
      'DioException ${type.name} ${response?.statusCode ?? ''} ${describeUrl(requestOptions.uri)}',
    _ => '${error.runtimeType}: ${_shorten('$error')}',
  };

  /// The URL without the values of query parameters that could be personal
  /// (a search term ...), only `route` and `lang` stay.
  @visibleForTesting
  static String describeUrl(Uri uri) {
    final origin = uri.hasAuthority ? '${uri.scheme}://${uri.authority}' : '';
    if (uri.queryParameters.isEmpty) return '$origin${uri.path}';
    final query = uri.queryParameters.entries
        .map((entry) => '${entry.key}=${_keptQueryParameters.contains(entry.key) ? entry.value : '…'}')
        .join('&');
    return '$origin${uri.path}?$query';
  }

  static String _shorten(String text) =>
      text.length <= _maxMessageLength ? text : '${text.substring(0, _maxMessageLength)}…';

  static String _shortStackTrace(StackTrace stackTrace) =>
      stackTrace.toString().split('\n').where((line) => line.trim().isNotEmpty).take(12).join('\n');
}
