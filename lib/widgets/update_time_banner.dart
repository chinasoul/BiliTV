import 'dart:async';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 更新时间横幅组件
///
/// 在屏幕中央显示"更新于x分钟前"的横幅
/// 延迟出现，显示一段时间后自动淡出
class UpdateTimeBanner extends StatefulWidget {
  /// 要显示的时间文本，如 "更新于5分钟前"
  final String timeText;

  /// 出现前的延迟时间
  final Duration showDelay;

  /// 显示时长（淡出前）
  final Duration displayDuration;

  const UpdateTimeBanner({
    super.key,
    required this.timeText,
    this.showDelay = const Duration(milliseconds: 500),
    this.displayDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<UpdateTimeBanner> createState() => _UpdateTimeBannerState();
}

class _UpdateTimeBannerState extends State<UpdateTimeBanner> {
  Timer? _showTimer;
  Timer? _hideTimer;
  Timer? _fadeTimer;
  bool _visible = false;
  bool _dismissed = false;
  double _opacity = 1.0;

  // 淡出动画参数
  static const int _fadeSteps = 10;
  static const int _fadeIntervalMs = 20; // 总共 200ms

  @override
  void initState() {
    super.initState();

    // 延迟后显示
    _showTimer = Timer(widget.showDelay, () {
      if (mounted) {
        setState(() => _visible = true);
        // 显示后再延迟淡出
        _hideTimer = Timer(widget.displayDuration, _startFadeOut);
      }
    });
  }

  void _startFadeOut() {
    int step = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: _fadeIntervalMs), (
      timer,
    ) {
      step++;
      if (mounted) {
        setState(() {
          _opacity = 1.0 - (step / _fadeSteps);
          if (_opacity <= 0) {
            timer.cancel();
            _dismissed = true;
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.timeText.isEmpty || _dismissed || !_visible) {
      return const SizedBox.shrink();
    }

    final themeColor = SettingsService.themeColor;

    return UnconstrainedBox(
      child: Opacity(
        opacity: _opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: themeColor.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.timeText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
