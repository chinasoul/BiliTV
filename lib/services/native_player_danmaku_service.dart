// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class NativePlayerDanmakuService {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.dev/video_player_android_danmaku',
  );

  static int? _playerIdOf(VideoPlayerController? controller) {
    if (controller == null ||
        controller.playerId == VideoPlayerController.kUninitializedPlayerId) {
      return null;
    }
    return controller.playerId;
  }

  static void addDanmaku(
    VideoPlayerController? controller,
    DanmakuContentItem item,
  ) {
    final playerId = _playerIdOf(controller);
    if (playerId == null) return;
    _channel.invokeMethod<void>('addDanmaku', {
      'playerId': playerId,
      'text': item.text,
      'color': item.color.toARGB32(),
    });
  }

  static void addDanmakuBatch(
    VideoPlayerController? controller,
    List<DanmakuContentItem> items,
  ) {
    if (items.isEmpty) return;
    final playerId = _playerIdOf(controller);
    if (playerId == null) return;
    final batch = items
        .map((item) => {'text': item.text, 'color': item.color.toARGB32()})
        .toList(growable: false);
    _channel.invokeMethod<void>('addDanmakuBatch', {
      'playerId': playerId,
      'items': batch,
    });
  }

  static void updateOption(
    VideoPlayerController? controller,
    DanmakuOption option,
  ) {
    final playerId = _playerIdOf(controller);
    if (playerId == null) return;
    _channel.invokeMethod<void>('updateOption', {
      'playerId': playerId,
      'opacity': option.opacity,
      'fontSize': option.fontSize,
      'area': option.area,
      'duration': option.duration,
      'hideScroll': option.hideScroll,
      'strokeWidth': option.strokeWidth,
      'lineHeight': option.lineHeight,
    });
  }

  static void clear(VideoPlayerController? controller) {
    final playerId = _playerIdOf(controller);
    if (playerId == null) return;
    _channel.invokeMethod<void>('clear', {'playerId': playerId});
  }

  static void pause(VideoPlayerController? controller) {
    final playerId = _playerIdOf(controller);
    if (playerId == null) return;
    _channel.invokeMethod<void>('pause', {'playerId': playerId});
  }

  static void resume(VideoPlayerController? controller) {
    final playerId = _playerIdOf(controller);
    if (playerId == null) return;
    _channel.invokeMethod<void>('resume', {'playerId': playerId});
  }
}
