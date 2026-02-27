import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart'; // 引入 Splash Screen
import 'package:bili_tv_app/core/plugin/plugin_manager.dart';
import 'package:bili_tv_app/plugins/sponsor_block_plugin.dart';
import 'package:bili_tv_app/plugins/ad_filter_plugin.dart';
import 'package:bili_tv_app/plugins/danmaku_enhance_plugin.dart';
import 'config/build_flags.dart';
import 'services/auth_service.dart';
import 'services/local_server.dart';
import 'services/settings_service.dart';
import 'widgets/global_memory_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.init();

  // TV 设备内存有限（通常 1~2 GB），严格控制图片解码缓存
  PaintingBinding.instance.imageCache.maximumSize =
      SettingsService.imageCacheMaxSize;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      SettingsService.imageCacheMaxBytes;

  if (BuildFlags.pluginsEnabled) {
    // 初始化插件管理器并注册插件
    final pluginManager = PluginManager();
    await pluginManager.init();
    pluginManager.register(SponsorBlockPlugin());
    pluginManager.register(AdFilterPlugin());
    pluginManager.register(DanmakuEnhancePlugin());
  }

  // 启动本地 HTTP 服务 (用于 MPD，本地插件 API 由编译开关控制)
  await LocalServer.instance.start();

  await AuthService.init(); // 全屏模式 - 隐藏状态栏和导航栏
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // 初始化逻辑已移交至 SplashScreen 处理，这里仅启动 APP
  // 这样可以确保启动画面迅速出现，无需等待初始化完成

  runApp(const BtApp());
}

class BtApp extends StatelessWidget {
  const BtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: SettingsService.themeColor,
        useMaterial3: true,
        focusColor: Colors.white.withValues(alpha: 0.1),
      ),
      builder: (context, child) {
        // 应用全局字体缩放
        final scale = SettingsService.fontScale;
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          // 全局内存监控覆盖层，始终显示在最上层
          child: GlobalMemoryOverlay(child: child!),
        );
      },
      home: const SplashScreen(),
    );
  }
}
