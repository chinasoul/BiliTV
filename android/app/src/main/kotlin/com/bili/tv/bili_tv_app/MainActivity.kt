package com.bili.tv.bili_tv_app

import android.content.Intent
import android.media.MediaCodecList
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val UPDATE_CHANNEL = "com.bili.tv/update"
    private val CODEC_CHANNEL = "com.bili.tv/codec"
    private val DEVICE_INFO_CHANNEL = "com.bili.tv/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 更新安装 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "APK path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 编码器检测 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CODEC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareDecoders" -> {
                    try {
                        val hwCodecs = getHardwareDecoders()
                        result.success(hwCodecs)
                    } catch (e: Exception) {
                        result.error("CODEC_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 本机信息 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    try {
                        result.success(getDeviceInfo())
                    } catch (e: Exception) {
                        result.error("DEVICE_INFO_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    // 获取硬件解码器支持的格式
    private fun getHardwareDecoders(): List<String> {
        val supportedFormats = mutableSetOf<String>()
        val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
        
        for (info in codecList.codecInfos) {
            // 只检查解码器，跳过编码器
            if (info.isEncoder) continue
            
            // 检查是否是硬件解码器 (不包含 google/software)
            val name = info.name.lowercase()
            val isHardware = !name.contains("google") && 
                            !name.contains("software") &&
                            !name.contains("sw") &&
                            !name.startsWith("c2.android")
            
            if (isHardware) {
                for (type in info.supportedTypes) {
                    when {
                        type.equals("video/avc", ignoreCase = true) -> supportedFormats.add("avc")
                        type.equals("video/hevc", ignoreCase = true) -> supportedFormats.add("hevc")
                        type.equals("video/av01", ignoreCase = true) -> supportedFormats.add("av1")
                        type.equals("video/x-vnd.on2.vp9", ignoreCase = true) -> supportedFormats.add("vp9")
                    }
                }
            }
        }
        
        return supportedFormats.toList()
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw Exception("APK file not found: $path")
        }

        val intent = Intent(Intent.ACTION_VIEW)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
            intent.setDataAndType(uri, "application/vnd.android.package-archive")
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            intent.setDataAndType(
                android.net.Uri.fromFile(file),
                "application/vnd.android.package-archive"
            )
        }

        startActivity(intent)
    }

    private fun getDeviceInfo(): Map<String, Any> {
        val supportedAbis = Build.SUPPORTED_ABIS?.toList() ?: emptyList()
        val primaryAbi = if (supportedAbis.isNotEmpty()) supportedAbis[0] else "unknown"
        val gpuInfo = getSystemProperty("ro.hardware.egl")
            .ifEmpty { getSystemProperty("ro.board.platform") }
            .ifEmpty { Build.HARDWARE ?: "unknown" }

        // 运行内存信息
        val activityManager = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        val memInfo = android.app.ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        val totalRamMb = memInfo.totalMem / (1024 * 1024)
        val availRamMb = memInfo.availMem / (1024 * 1024)

        return mapOf(
            "platform" to "Android",
            "androidVersion" to (Build.VERSION.RELEASE ?: "unknown"),
            "sdkInt" to Build.VERSION.SDK_INT,
            "model" to (Build.MODEL ?: "unknown"),
            "manufacturer" to (Build.MANUFACTURER ?: "unknown"),
            "brand" to (Build.BRAND ?: "unknown"),
            "device" to (Build.DEVICE ?: "unknown"),
            "product" to (Build.PRODUCT ?: "unknown"),
            "board" to (Build.BOARD ?: "unknown"),
            "hardware" to (Build.HARDWARE ?: "unknown"),
            "cpuAbi" to primaryAbi,
            "supportedAbis" to supportedAbis,
            "arch" to (System.getProperty("os.arch") ?: "unknown"),
            "kernel" to (System.getProperty("os.version") ?: "unknown"),
            "gpu" to gpuInfo,
            "glEsVersion" to getGlEsVersion(),
            "totalRamMb" to totalRamMb,
            "availRamMb" to availRamMb
        )
    }

    private fun getGlEsVersion(): String {
        return try {
            val activityManager = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            activityManager.deviceConfigurationInfo.glEsVersion ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }

    private fun getSystemProperty(key: String): String {
        return try {
            val systemProperties = Class.forName("android.os.SystemProperties")
            val getMethod = systemProperties.getMethod("get", String::class.java, String::class.java)
            getMethod.invoke(null, key, "") as String
        } catch (e: Exception) {
            ""
        }
    }
}
