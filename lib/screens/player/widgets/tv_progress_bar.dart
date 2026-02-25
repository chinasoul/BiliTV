import 'package:flutter/material.dart';
import 'package:bili_tv_app/services/settings_service.dart';

/// TV 遥控器优化的视频进度条
///
/// 特性:
/// - 进度条显示当前位置
/// - 显示缓冲进度
class TvProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isFocused;
  final ValueChanged<double>? onSeekRequested;

  const TvProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.buffered = Duration.zero,
    this.isFocused = false,
    this.onSeekRequested,
  });

  void _handleSeekFromLocalDx(double localDx, double width) {
    if (onSeekRequested == null || width <= 0) return;
    final ratio = (localDx / width).clamp(0.0, 1.0);
    onSeekRequested!(ratio);
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds;
    final bufferedMs = buffered.inMilliseconds;

    // 计算百分比
    final progress = totalMs > 0 ? positionMs / totalMs : 0.0;
    final bufferedProgress = totalMs > 0 ? bufferedMs / totalMs : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progressDotX = progress * width;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _handleSeekFromLocalDx(details.localPosition.dx, width),
          onHorizontalDragStart: (details) =>
              _handleSeekFromLocalDx(details.localPosition.dx, width),
          onHorizontalDragUpdate: (details) =>
              _handleSeekFromLocalDx(details.localPosition.dx, width),
          child: SizedBox(
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
              // 进度条主体
              Positioned(
                left: 0,
                right: 0,
                top: 16,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                  child: Stack(
                    children: [
                      // 缓冲进度
                      FractionallySizedBox(
                        widthFactor: bufferedProgress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: const Color(
                              0xFFFFF59D,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      // 已播放进度
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: SettingsService.themeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 当前进度圆点
              Positioned(
                left: progressDotX.clamp(8.0, width - 8.0) - 8,
                top: isFocused ? 8 : 10,
                child: Container(
                  width: isFocused ? 20 : 16,
                  height: isFocused ? 20 : 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SettingsService.themeColor,
                    border: isFocused
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.6),
                              blurRadius: 12,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              ],
            ),
          ),
        );
      },
    );
  }
}
