import 'package:flutter/material.dart';

/// 迷你进度条 - 显示在屏幕底部，当控制栏隐藏时显示
class MiniProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;

  const MiniProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.buffered = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final progress = totalMs > 0 ? position.inMilliseconds / totalMs : 0.0;
    final bufferedProgress = totalMs > 0
        ? buffered.inMilliseconds / totalMs
        : 0.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            // 背景条
            Container(color: Colors.white.withValues(alpha: 0.3)),
            // 缓冲进度
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: bufferedProgress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF59D).withValues(alpha: 0.5),
                ),
              ),
            ),
            // 进度条
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFfb7299), // B站粉
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
