import 'package:flutter/material.dart';

/// TV 遥控器优化的视频进度条
///
/// 特性:
/// - 进度条显示当前位置
/// - 支持快进/快退预览时间标签
/// - 显示缓冲进度
class TvProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isFocused;
  final Duration? previewPosition; // 预览位置（快进/快退时显示）

  const TvProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.buffered = Duration.zero,
    this.isFocused = false,
    this.previewPosition,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds;
    final bufferedMs = buffered.inMilliseconds;
    final previewMs = previewPosition?.inMilliseconds;

    // 计算百分比
    final progress = totalMs > 0 ? positionMs / totalMs : 0.0;
    final bufferedProgress = totalMs > 0 ? bufferedMs / totalMs : 0.0;
    final previewProgress = (previewMs != null && totalMs > 0)
        ? previewMs / totalMs
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final previewDotX = previewProgress != null
            ? previewProgress * width
            : null;

        return SizedBox(
          height: 40, // 增加高度以容纳预览标签
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
                            color: Colors.white24,
                          ),
                        ),
                      ),
                      // 已播放进度
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: const Color(0xFFfb7299), // B站粉
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 预览时间标签
              if (previewPosition != null && previewDotX != null)
                Positioned(
                  left: (previewDotX - 30).clamp(0.0, width - 60),
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(previewPosition!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
