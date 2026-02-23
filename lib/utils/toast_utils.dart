import 'dart:async';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 轻量级自定义 Toast 工具
///
/// 内存影响评估:
/// - 新增对象: 1个 OverlayEntry + 1个 Timer
/// - 生命周期: 短期（显示后自动销毁）
/// - 预估开销: 可忽略
/// - 清理方式: Timer 结束后自动移除
class ToastUtils {
  static OverlayEntry? _currentEntry;
  static Timer? _timer;
  static Timer? _fadeTimer;
  static double _opacity = 1.0;

  /// 默认显示时长
  static const Duration defaultDuration = Duration(seconds: 1);

  /// 淡出动画时长
  static const int _fadeSteps = 10;
  static const int _fadeIntervalMs = 20; // 总共 200ms

  /// 显示 Toast
  ///
  /// [context] BuildContext
  /// [msg] 显示内容
  /// [duration] 显示时长，默认 1 秒
  static void show(
    BuildContext context,
    String msg, {
    Duration duration = defaultDuration,
  }) {
    // 取消之前的定时器
    _timer?.cancel();
    _timer = null;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _opacity = 1.0;

    // 移除旧的 entry
    _removeEntry();

    final overlay = Overlay.of(context);

    _currentEntry = OverlayEntry(
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        final screenWidth = screenSize.width;
        final screenHeight = screenSize.height;
        // 侧边栏占 5%，内容区占 95%
        final sidebarWidth = screenWidth * 0.05;
        // 垂直位置：屏幕高度 2/3 处
        final topOffset = screenHeight * 2 / 3;

        return Positioned(
          top: topOffset,
          left: sidebarWidth,
          right: 0,
          child: Center(
            child: Opacity(
              opacity: _opacity,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: SettingsService.themeColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    msg,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_currentEntry!);

    // 设置定时器，到时间后开始淡出
    _timer = Timer(duration, _startFadeOut);
  }

  /// 开始淡出动画
  static void _startFadeOut() {
    _timer?.cancel();
    _timer = null;

    int step = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: _fadeIntervalMs), (
      timer,
    ) {
      step++;
      _opacity = 1.0 - (step / _fadeSteps);
      if (_opacity <= 0) {
        timer.cancel();
        _removeEntry();
      } else {
        _currentEntry?.markNeedsBuild();
      }
    });
  }

  /// 移除 entry
  static void _removeEntry() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    try {
      _currentEntry?.remove();
    } catch (_) {}
    _currentEntry = null;
    _opacity = 1.0;
  }

  /// 取消当前 Toast
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _removeEntry();
  }
}
