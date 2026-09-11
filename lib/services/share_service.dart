import 'package:flutter/services.dart';

/// Receives text shared to the app from other apps (e.g. YouTube's Share
/// button). The native side lives in android/.../MainActivity.kt.
class ShareService {
  static const _channel = MethodChannel('com.ayman.mypodcasts/share');

  /// Text the app was launched with via the share sheet, if any.
  static Future<String?> getInitialSharedText() async {
    try {
      return await _channel.invokeMethod<String>('getInitialSharedText');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Called when text is shared while the app is already running.
  static void listen(void Function(String text) onShared) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        onShared(call.arguments as String);
      }
    });
  }
}
