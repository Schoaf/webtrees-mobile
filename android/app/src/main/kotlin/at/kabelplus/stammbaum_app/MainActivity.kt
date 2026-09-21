package at.kabelplus.stammbaum_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity - local_auth's BiometricPrompt
// requires a FragmentActivity to attach to.
class MainActivity : FlutterFragmentActivity()
