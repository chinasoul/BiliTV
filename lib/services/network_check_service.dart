import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 轻量级 Bilibili API 可达性检测
///
/// 启动时探测一次；失败后在后台周期性重试，
/// 恢复后通过 [onRestored] 回调通知调用方。
class NetworkCheckService {
  NetworkCheckService._();

  static const Duration _timeout = Duration(seconds: 6);
  static const Duration _retryInterval = Duration(seconds: 10);
  static const int _maxRetries = 18; // 最多重试 3 分钟

  static Timer? _retryTimer;
  static int _retryCount = 0;
  static VoidCallback? _onRestored;

  /// 探测 Bilibili API 是否可达
  ///
  /// 返回 `true` = 可达，`false` = 不可达。
  static Future<bool> check() async {
    try {
      final response = await http
          .get(
            Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
            headers: const {'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 在后台周期性重试，网络恢复时调用 [onRestored] 一次后停止。
  static void startRetrying({required VoidCallback onRestored}) {
    stopRetrying();
    _onRestored = onRestored;
    _retryCount = 0;
    _retryTimer = Timer.periodic(_retryInterval, (_) async {
      _retryCount++;
      if (_retryCount > _maxRetries) {
        stopRetrying();
        return;
      }
      final ok = await check();
      if (ok) {
        debugPrint('✅ Network restored after $_retryCount retries');
        final cb = _onRestored;
        stopRetrying();
        cb?.call();
      }
    });
  }

  static void stopRetrying() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _onRestored = null;
    _retryCount = 0;
  }
}
