import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

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
          style: const TextStyle(color: Colors.white, fontSize: AppFonts.sizeLG),
        ),
      );
    }

    if (isLoading || controller == null || !controller!.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(color: SettingsService.themeColor),
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
