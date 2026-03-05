import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart'; // 包含 BiliCacheManager
import '../services/update_service.dart';
import '../services/bilibili_api.dart';
import '../services/device_info_service.dart';
import '../models/video.dart';
import 'home_screen.dart';
import '../utils/image_url_utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    List<Video> preloadedVideos = [];
    // 初始化基础服务
    await Future.wait([
      AuthService.init(),
      SettingsService.init(),
      UpdateService.init(),
      DeviceInfoService.getDeviceInfo().then((info) {
        SettingsService.androidSdkInt = info['sdkInt'] as int? ?? 99;
      }),
    ]);

    // 4. 如果已登录，更新一下用户信息 (获取最新 VIP 状态)
    // 不 await，让它在后台跑，或者如果很快完成也没关系
    // 这里选择放在后面单独调一下，不阻塞核心服务初始化，但尽量在进入主页前完成
    if (AuthService.isLoggedIn) {
      BilibiliApi.fetchAndSaveUserInfo().catchError((e) {
        debugPrint('Failed to update user info on splash: $e');
      });
    }

    // 根据设置决定是否预加载首页数据
    if (SettingsService.autoRefreshOnLaunch) {
      // 【开启自动刷新】异步预加载数据
      final preloadFuture = Future(() async {
        try {
          final videos = await BilibiliApi.getRecommendVideos(idx: 0);
          preloadedVideos = videos;

          if (mounted && preloadedVideos.isNotEmpty) {
            final int count = preloadedVideos.length;
            List<Future<void>> imageTasks = [];

            for (int i = 0; i < count; i++) {
              final url = preloadedVideos[i].pic;
              if (url.isNotEmpty) {
                final optimizedUrl = ImageUrlUtils.getResizedUrl(
                  url,
                  width: 360,
                  height: 200,
                );
                final imageProvider = CachedNetworkImageProvider(
                  optimizedUrl,
                  maxWidth: 360,
                  maxHeight: 200,
                  cacheManager: BiliCacheManager.instance,
                );

                imageTasks.add(
                  precacheImage(imageProvider, context).catchError((e) {
                    debugPrint('Image preload failed: $url');
                  }),
                );
              }
            }
            if (imageTasks.isNotEmpty) {
              await Future.wait(imageTasks);
            }
          }
        } catch (e) {
          debugPrint('Preload videos failed: $e');
        }
      });

      await Future.delayed(const Duration(milliseconds: 150));

      try {
        await preloadFuture.timeout(const Duration(milliseconds: 300));
      } catch (e) {
        // 预加载未完成，忽略异常
      }
    } else {
      // 【关闭自动刷新】不预加载，仅短暂过渡
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, a1, a2) =>
              HomeScreen(preloadedVideos: preloadedVideos),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: const SizedBox.expand(),
    );
  }
}
