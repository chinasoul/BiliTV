import 'package:flutter/services.dart';

class DeviceInfoService {
  static const MethodChannel _channel = MethodChannel('com.bili.tv/device_info');

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final info = await _channel.invokeMethod<dynamic>('getDeviceInfo');
      if (info is Map) {
        return Map<String, dynamic>.from(info);
      }
    } catch (_) {
      // Ignore channel errors, return empty map for UI fallback.
    }
    return {};
  }
}
