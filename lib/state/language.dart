import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLanguagePrefKey = 'app_language';

/// The language picked in "Mein Konto": a language code ('de', 'en'), or
/// null for "like the device" (see [resolveAppLocale]). Read once in
/// `main()` before runApp ([loadLanguagePreference]), like the active server.
class LanguageNotifier extends Notifier<String?> {
  LanguageNotifier({this.initial});

  final String? initial;

  @override
  String? build() => initial;

  Future<void> set(String? languageCode) async {
    state = languageCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (languageCode == null) {
        await prefs.remove(_kLanguagePrefKey);
      } else {
        await prefs.setString(_kLanguagePrefKey, languageCode);
      }
    } on Exception {
      // Storage unavailable - the choice still applies until the app restarts.
    }
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, String?>(LanguageNotifier.new);

Future<String?> loadLanguagePreference() async {
  try {
    return (await SharedPreferences.getInstance()).getString(_kLanguagePrefKey);
  } on Exception {
    return null;
  }
}

/// Languages the app is translated into, with their own names for the picker.
const appLanguages = {'de': 'Deutsch', 'en': 'English', 'nl': 'Nederlands'};

/// The app's locale: the [picked] language, or "like the device" - the device
/// language if the app has it, English otherwise. Keeps the device's country
/// when the language matches (en_GB, nl_BE ...), so dates, the date picker's
/// typed input (dd/mm/yyyy vs mm/dd/yyyy) etc. follow the device's region -
/// plain "en" would mean US formats.
Locale resolveAppLocale(Iterable<Locale>? deviceLocales, {String? picked}) {
  final device = deviceLocales?.firstOrNull;
  final code = picked ?? (appLanguages.containsKey(device?.languageCode) ? device!.languageCode : 'en');
  return Locale(code, device?.languageCode == code ? device?.countryCode : null);
}
