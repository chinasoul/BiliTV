import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoLayer extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isLoading;
  final String? errorMessage;

  const VideoLayer({
    super.key,
    required this.controller,
    required this.isLoading,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Center(
        child: Text(
          errorMessage!,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    if (isLoading || controller == null || !controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF81C784)),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller!.value.aspectRatio,
        child: VideoPlayer(controller!),
      ),
    );
  }
}
