package com.bili.tv.bili_tv_app

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class NativeDanmakuPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Any?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val overlayView = NativeDanmakuOverlayView(context)
    private val channel = MethodChannel(messenger, "com.bili.tv/native_danmaku_view_$viewId")

    init {
        channel.setMethodCallHandler(this)
        overlayView.post {
            overlayView.bringToFront()
            overlayView.invalidate()
        }
        @Suppress("UNCHECKED_CAST")
        val map = args as? Map<String, Any?>
        if (map != null) {
            overlayView.updateOption(map)
        }
    }

    override fun getView() = overlayView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        overlayView.clearDanmaku()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "addDanmaku" -> {
                val text = call.argument<String>("text") ?: ""
                val color = call.argument<Int>("color") ?: 0xFFFFFFFF.toInt()
                overlayView.addDanmaku(text, color)
                result.success(null)
            }
            "updateOption" -> {
                @Suppress("UNCHECKED_CAST")
                val option = call.arguments as? Map<String, Any?> ?: emptyMap()
                overlayView.updateOption(option)
                result.success(null)
            }
            "clear" -> {
                overlayView.clearDanmaku()
                result.success(null)
            }
            "pause" -> {
                overlayView.pauseDanmaku()
                result.success(null)
            }
            "resume" -> {
                overlayView.resumeDanmaku()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
