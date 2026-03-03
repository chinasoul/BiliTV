import 'dart:async';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 轻量级自定义 Toast 工具
///
/// 每次调用 show() 时替换已有 Toast。
class ToastUtils {
  static OverlayEntry? _currentEntry;
  static Timer? _timer;
  static Timer? _fadeTimer;
  static double _opacity = 1.0;

  /// 默认显示时长
  static const Duration defaultDuration = Duration(milliseconds: 1500);

  /// 淡出动画时长
  static const int _fadeSteps = 10;
  static const int _fadeIntervalMs = 20; // 总共 200ms

  /// 显示 Toast，替换已有 Toast
  static void show(
    BuildContext context,
    String msg, {
    Duration duration = defaultDuration,
  }) {
    _timer?.cancel();
    _timer = null;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _opacity = 1.0;
    _removeEntry();

    final overlay = Overlay.of(context);

    _currentEntry = OverlayEntry(
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        final screenWidth = screenSize.width;
        final screenHeight = screenSize.height;
        final sidebarWidth = screenWidth * 0.05;
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
                    color: SettingsService.themeColor.withValues(
                      alpha: 0.9,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    msg,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppFonts.sizeMD,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_currentEntry!);
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
