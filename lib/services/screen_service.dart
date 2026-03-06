import 'package:flutter/services.dart';

/// 屏幕常亮服务 — 通过原生 MethodChannel 直接操作 Activity Window，
/// 比 wakelock_plus 插件更可靠地防止电视盒子屏保激活。
class ScreenService {
  static const _channel = MethodChannel('com.bili.tv/screen');

  static Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {}
  }
}
