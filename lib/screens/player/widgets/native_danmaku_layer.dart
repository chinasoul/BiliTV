import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class NativeDanmakuBridge {
  final MethodChannel _channel;

  NativeDanmakuBridge(int viewId)
      : _channel = MethodChannel('com.bili.tv/native_danmaku_view_$viewId');

  void addDanmaku(DanmakuContentItem item) {
    _channel.invokeMethod<void>('addDanmaku', {
      'text': item.text,
      'color': item.color.toARGB32(),
      'type': item.type.index,
    });
  }

  void updateOption(DanmakuOption option) {
    _channel.invokeMethod<void>('updateOption', {
      'fontSize': option.fontSize,
      'opacity': option.opacity,
      'area': option.area,
      'duration': option.duration,
      'hideTop': option.hideTop,
      'hideBottom': option.hideBottom,
      'hideScroll': option.hideScroll,
      'hideSpecial': option.hideSpecial,
      'strokeWidth': option.strokeWidth,
      'lineHeight': option.lineHeight,
    });
  }

  void clear() {
    _channel.invokeMethod<void>('clear');
  }

  void pause() {
    _channel.invokeMethod<void>('pause');
  }

  void resume() {
    _channel.invokeMethod<void>('resume');
  }
}

class NativeDanmakuLayer extends StatelessWidget {
  final DanmakuOption option;
  final ValueChanged<NativeDanmakuBridge> onCreated;

  const NativeDanmakuLayer({
    super.key,
    required this.option,
    required this.onCreated,
  });

  @override
  Widget build(BuildContext context) {
    final creationParams = {
      'fontSize': option.fontSize,
      'opacity': option.opacity,
      'area': option.area,
      'duration': option.duration,
      'lineHeight': option.lineHeight,
    };
    return Positioned.fill(
      child: IgnorePointer(
        child: PlatformViewLink(
          viewType: 'com.bili.tv/native_danmaku_view',
          surfaceFactory: (context, controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            );
          },
          onCreatePlatformView: (params) {
            final controller = PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: 'com.bili.tv/native_danmaku_view',
              layoutDirection: TextDirection.ltr,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
            );
            controller.addOnPlatformViewCreatedListener((viewId) {
              params.onPlatformViewCreated(viewId);
              final bridge = NativeDanmakuBridge(viewId);
              bridge.updateOption(option);
              onCreated(bridge);
            });
            controller.create();
            return controller;
          },
        ),
      ),
    );
  }
}
