import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart'; // 引入 Splash Screen
import 'package:bili_tv_app/core/plugin/plugin_manager.dart';
import 'package:bili_tv_app/plugins/sponsor_block_plugin.dart';
import 'package:bili_tv_app/plugins/ad_filter_plugin.dart';
import 'package:bili_tv_app/plugins/danmaku_enhance_plugin.dart';
import 'config/build_flags.dart';
import 'config/app_style.dart';
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
  static const double _baseFontScaleMultiplier = 1.2;

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: SettingsService.themeColor,
      useMaterial3: true,
      focusColor: Colors.white.withValues(alpha: 0.1),
      colorScheme: ColorScheme.fromSeed(
        seedColor: SettingsService.themeColor,
        brightness: Brightness.dark,
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      primaryColor: SettingsService.themeColor,
      useMaterial3: true,
      focusColor: Colors.black.withValues(alpha: 0.08),
      colorScheme: ColorScheme.fromSeed(
        seedColor: SettingsService.themeColor,
        brightness: Brightness.light,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsService.themeModeListenable,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'BT',
          debugShowCheckedModeBanner: false,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: themeMode,
          builder: (context, child) {
            // 仅重建 MediaQuery 层，避免整体重建 MaterialApp
            return ValueListenableBuilder<double>(
              valueListenable: SettingsService.fontScaleListenable,
              builder: (context, scale, _) {
                final effectiveScale = scale * _baseFontScaleMultiplier;
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(effectiveScale)),
                  // 全局内存监控覆盖层，始终显示在最上层
                  child: GlobalMemoryOverlay(child: child!),
                );
              },
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
