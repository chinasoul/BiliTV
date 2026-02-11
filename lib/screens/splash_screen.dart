import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart'; // 包含 BiliCacheManager
import '../services/update_service.dart';
import '../services/bilibili_api.dart';
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
    ]);

    // 4. 如果已登录，更新一下用户信息 (获取最新 VIP 状态)
    // 不 await，让它在后台跑，或者如果很快完成也没关系
    // 这里选择放在后面单独调一下，不阻塞核心服务初始化，但尽量在进入主页前完成
    if (AuthService.isLoggedIn) {
      BilibiliApi.fetchAndSaveUserInfo().catchError((e) {
        debugPrint('Failed to update user info on splash: $e');
      });
    }

    // 异步预加载数据
    final preloadFuture = Future(() async {
      try {
        final videos = await BilibiliApi.getRecommendVideos(idx: 0);
        preloadedVideos = videos;

        if (mounted && preloadedVideos.isNotEmpty) {
          // 【用户请求】取消 12 个的数量限制，全部预加载
          final int count = preloadedVideos.length;

          // 【核心修复】创建预加载任务列表
          List<Future<void>> imageTasks = [];

          for (int i = 0; i < count; i++) {
            final url = preloadedVideos[i].pic;
            if (url.isNotEmpty) {
              // 【必须完全匹配 TvVideoCard 的参数】
              // 1. maxWidth: 360
              // 2. maxHeight: 200 (原本缺失导致缓存不匹配)
              // 3. cacheManager: BiliCacheManager.instance (原本缺失导致路径不匹配)
              final optimizedUrl = ImageUrlUtils.getResizedUrl(
                url,
                width: 640,
                height: 360,
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
          // 并行等待所有图片下载
          if (imageTasks.isNotEmpty) {
            await Future.wait(imageTasks);
          }
        }
      } catch (e) {
        debugPrint('Preload videos failed: $e');
      }
    });

    // 无启动图模式下仅保留短暂过渡，避免白屏闪烁感
    await Future.delayed(const Duration(milliseconds: 150));

    // 尝试拿到预加载结果，超时则直接进主页
    try {
      await preloadFuture.timeout(const Duration(milliseconds: 300));
    } catch (e) {
      // 预加载未完成，忽略异常，preloadedVideos 可能是空的
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
