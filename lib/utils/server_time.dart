import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// 服务器时间校正工具：通过 HTTP Date 头计算设备时钟与服务器时钟的偏移量
class ServerTime {
  static const String _offsetKey = 'server_time_offset_ms';

  static Duration _offset = Duration.zero;

  /// 获取校正后的当前时间
  static DateTime get now => DateTime.now().add(_offset);

  /// 从本地缓存加载上次保存的偏移量（应在 app 启动时调用）
  static void load(SharedPreferences prefs) {
    final ms = prefs.getInt(_offsetKey);
    if (ms != null) _offset = Duration(milliseconds: ms);
  }

  /// 从 HTTP 响应头解析服务器时间并更新偏移量
  static void updateFromHeader(String? dateHeader) {
    if (dateHeader == null) return;
    try {
      final serverTime = HttpDate.parse(dateHeader);
      _offset = serverTime.difference(DateTime.now());
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt(_offsetKey, _offset.inMilliseconds);
      });
    } catch (_) {}
  }
}
