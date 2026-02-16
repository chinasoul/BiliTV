import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PauseIndicator extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isSeeking; // 是否正在快进/快退

  const PauseIndicator({
    super.key,
    required this.controller,
    this.isSeeking = false,
  });

  @override
  Widget build(BuildContext context) {
    if (controller == null) return const SizedBox.shrink();

    // 快进/快退期间不显示暂停图标
    if (isSeeking) return const SizedBox.shrink();

    // 由于 VideoPlayerValue 不是 ValueListenable，我们依赖父组件重建
    final isPlaying = controller!.value.isPlaying;
    final isBuffering = controller!.value.isBuffering;

    if (!isPlaying && !isBuffering) {
      return Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(20),
          child: const Icon(Icons.pause, color: Colors.white, size: 64),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
