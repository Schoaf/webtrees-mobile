import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

const _secureStorage = FlutterSecureStorage();
const _prefKey = 'biometric_lock_enabled';

/// Wraps `local_auth` plus the on/off preference for the app's optional
/// biometric lock. This gates *revealing* a session restored from a
/// previous launch behind Face ID/fingerprint - it sits on top of the
/// existing webtrees username/password login, not instead of it, so a
/// fresh interactive login is never itself biometric-gated.
class BiometricAuthService {
  final _auth = LocalAuthentication();

  Future<bool> isDeviceSupported() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } on Exception {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    final value = await _secureStorage.read(key: _prefKey);
    return value == '1';
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await _secureStorage.write(key: _prefKey, value: '1');
    } else {
      await _secureStorage.delete(key: _prefKey);
    }
  }

  /// Prompts Face ID/fingerprint (falling back to device PIN/pattern if
  /// biometrics aren't available, so a sensor failure can't lock someone
  /// out entirely). Returns false on any failure - cancelled, not
  /// enrolled, lockout, ... - rather than throwing; the caller just keeps
  /// showing the lock screen either way.
  Future<bool> authenticate({required String localizedReason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } on Exception {
      return false;
    }
  }
}
