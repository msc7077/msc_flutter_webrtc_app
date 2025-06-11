import 'package:flutter/services.dart';

class AudioRouteHelper {
  static const MethodChannel _channel = MethodChannel(
    'com.example.flutter_webrtc_app/audio',
  );

  static Future<void> setSpeakerOn(bool enable) async {
    await _channel.invokeMethod('setSpeaker', {'enable': enable});
  }
}
