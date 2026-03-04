import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/video.dart' as models;
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/mpd_generator.dart';
import '../../../services/local_server.dart';
import '../../../services/api/videoshot_api.dart';
import '../../../config/build_flags.dart';
import '../../../services/native_player_danmaku_service.dart';
import '../widgets/settings_panel.dart';
import '../player_screen.dart';
import '../widgets/quality_picker_sheet.dart';
import 'player_state_mixin.dart';
import '../../../core/plugin/plugin_manager.dart';
import '../../../core/plugin/plugin_types.dart';
import '../../../services/playback_progress_cache.dart';

/// 播放器逻辑 Mixin
mixin PlayerActionMixin on PlayerStateMixin {
  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // 初始化
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      danmakuEnabled = prefs.getBool('danmaku_enabled') ?? true;
      danmakuOpacity = prefs.getDouble('danmaku_opacity') ?? 0.6;
      danmakuFontSize = prefs.getDouble('danmaku_font_size') ?? 17.0;
      danmakuArea = prefs.getDouble('danmaku_area') ?? 0.25;
      danmakuSpeed = prefs.getDouble('danmaku_speed') ?? 10.0;
      hideTopDanmaku = prefs.getBool('hide_top_danmaku') ?? false;
      hideBottomDanmaku = prefs.getBool('hide_bottom_danmaku') ?? false;
      preferNativeDanmaku = prefs.getBool('prefer_native_danmaku') ?? true;
      playbackSpeed = prefs.getDouble('playback_speed') ?? 1.0;
      subtitleEnabled = prefs.getBool('subtitle_enabled') ?? false;
      // 根据设置决定是否显示控制栏
      showControls = !SettingsService.hideControlsOnStart;
    });
    updateDanmakuOption();
  }

  Future<void> saveSettings() async {
    // 视频内的弹幕调整仅对当前播放生效，不保存到全局设置。
    // 全局默认值通过 设置 → 弹幕设置 页面修改。
  }

  Future<void> _persistPlaybackSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', playbackSpeed);
  }

  Future<void> _rebuildCurrentPlaybackForTunnelModeChange() async {
    if (cid == null || videoController == null || !videoController!.value.isInitialized) {
      return;
    }

    final previousPosition = videoController!.value.position;
    final wasPlaying = videoController!.value.isPlaying;

    if (mounted) {
      setState(() => isLoading = true);
    }

    cancelPlayerListeners();
    await videoController?.pause();
    await videoController?.dispose();
    videoController = null;
    LocalServer.instance.clearMpdContent();

    final playInfo = await BilibiliApi.getVideoPlayUrl(
      bvid: widget.video.bvid,
      cid: cid!,
      qn: currentQuality,
    );
    if (playInfo == null) {
      throw Exception('获取播放地址失败');
    }

    currentQuality = playInfo['currentQuality'] ?? currentQuality;
    currentCodec = playInfo['codec'] ?? currentCodec;
    currentAudioUrl = playInfo['audioUrl'];
    videoWidth = int.tryParse(playInfo['width']?.toString() ?? '') ?? 0;
    videoHeight = int.tryParse(playInfo['height']?.toString() ?? '') ?? 0;
    videoFrameRate = double.tryParse(playInfo['frameRate']?.toString() ?? '') ?? 0.0;
    videoDataRateKbps =
        ((int.tryParse(playInfo['videoBandwidth']?.toString() ?? '') ?? 0) / 1000)
            .round();
    qualities = List<Map<String, dynamic>>.from(playInfo['qualities'] ?? []);

    String? playUrl;
    if (playInfo['dashData'] != null) {
      final mpdContent = await MpdGenerator.generate(
        playInfo['dashData'],
        selectedQn: currentQuality,
        selectedCodec: _codecPrefixForMpd(currentCodec),
      );
      LocalServer.instance.setMpdContent(mpdContent);
      playUrl = LocalServer.instance.mpdUrl;
    } else {
      playUrl = playInfo['url'];
    }

    if (playUrl == null || playUrl.isEmpty) {
      throw Exception('当前清晰度暂无可播放地址，请尝试其他清晰度');
    }

    videoController = VideoPlayerController.networkUrl(
      Uri.parse(playUrl),
      viewType: VideoViewType.platformView,
      httpHeaders: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        if (AuthService.sessdata != null) 'Cookie': 'SESSDATA=${AuthService.sessdata}',
      },
    );

    await videoController!.initialize();
    await videoController!.seekTo(previousPosition);
    resetDanmakuIndex(previousPosition);
    resetSubtitleIndex(previousPosition);

    _setupPlayerListeners();
    _startStatsTimer();
    if (wasPlaying) {
      await videoController!.play();
    }

    videoController?.setPlaybackSpeed(playbackSpeed);
    updateDanmakuOption();
    startHideTimer();

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  /// Probe whether the current device supports non-1x playback speed while
  /// tunnel mode is active. Measures actual position advancement over ~1.2s
  /// and compares to expected advancement at the requested speed.
  /// Returns true if the device honors the speed, false otherwise.
  Future<bool> _probeTunnelSpeedSupport(double speed) async {
    final vc = videoController;
    if (vc == null || !vc.value.isInitialized || !vc.value.isPlaying) {
      return false;
    }

    final startPos = vc.value.position;
    final wallStart = DateTime.now();

    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted || videoController == null) return false;

    final endPos = videoController!.value.position;
    final wallElapsed =
        DateTime.now().difference(wallStart).inMilliseconds.toDouble();
    final posElapsed =
        (endPos - startPos).inMilliseconds.toDouble();

    if (wallElapsed < 200) return false;

    final measuredSpeed = posElapsed / wallElapsed;
    // If the speed ratio is within 30 % of the target, consider it supported.
    // e.g. target=2.0 → accept 1.4..2.6 ; target=1.5 → accept 1.05..1.95
    final tolerance = speed * 0.3;
    return (measuredSpeed - speed).abs() <= tolerance;
  }

  Future<void> _syncTunnelModeWithPlaybackSpeed(double speed) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (isSwitchingTunnelModeForSpeed) return;

    final shouldRestoreTunnel =
        speed == 1.0 && tunnelModeTemporarilyDisabledForSpeed;
    final needsCheck = speed != 1.0 && SettingsService.tunnelModeEnabled;
    if (!needsCheck && !shouldRestoreTunnel) return;

    isSwitchingTunnelModeForSpeed = true;
    try {
      if (shouldRestoreTunnel) {
        await SettingsService.setTunnelModeEnabled(true);
        tunnelModeTemporarilyDisabledForSpeed = false;
        await _rebuildCurrentPlaybackForTunnelModeChange();
        ToastUtils.show(context, '已恢复隧道播放模式');
        return;
      }

      // ── Non-1x speed while tunnel is on ──
      final cached = SettingsService.tunnelSpeedSupported;
      if (cached == true) {
        // Device known to support tunnel + speed — no action needed.
        return;
      }

      if (cached == null) {
        // First time: probe whether the device actually honors the speed.
        debugPrint('🔍 Probing tunnel speed support at ${speed}x …');
        final supported = await _probeTunnelSpeedSupport(speed);
        await SettingsService.setTunnelSpeedSupported(supported);
        debugPrint('🔍 Tunnel speed probe result: $supported');
        if (supported) return;
      }

      // cached == false or probe just returned false → disable tunnel.
      await SettingsService.setTunnelModeEnabled(false);
      tunnelModeTemporarilyDisabledForSpeed = true;
      await _rebuildCurrentPlaybackForTunnelModeChange();
      ToastUtils.show(context, '当前设备隧道模式不支持倍速，已临时关闭');
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = '切换隧道播放模式失败: $e';
          isLoading = false;
        });
      }
      ToastUtils.show(context, '隧道播放模式切换失败');
    } finally {
      isSwitchingTunnelModeForSpeed = false;
    }
  }

  /// 隧道播放模式开启时，首次播放提示用户：若画面黑屏可去设置关闭。
  /// 仅在 Android + 隧道模式开启 + 尚未提示过 时触发；关闭再开启后会再次提示。
  void _showTunnelModeHintIfNeeded() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!SettingsService.tunnelModeEnabled) return;
    if (SettingsService.tunnelModeHintShown) return;

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (videoController == null || !videoController!.value.isPlaying) return;
      ToastUtils.show(
        context,
        '若黑屏，请关闭「隧道播放模式」',
        duration: const Duration(seconds: 4),
      );
      SettingsService.setTunnelModeHintShown(true);
    });
  }

  bool get useNativeDanmakuRender {
    if (defaultTargetPlatform != TargetPlatform.android || !preferNativeDanmaku) {
      return false;
    }
    // On API <= 25, PlatformVideoView uses setZOrderMediaOverlay(true) which
    // puts the SurfaceView surface above the window surface. When tunnel mode
    // is on, frames bypass SurfaceView so the DanmakuOverlayView stays visible.
    // When tunnel mode is off, SurfaceView renders on top and covers the
    // DanmakuOverlayView. Fall back to Flutter canvas danmaku in that case.
    if (!SettingsService.tunnelModeEnabled &&
        SettingsService.androidSdkInt <= 25) {
      return false;
    }
    return true;
  }

  Future<void> initializePlayer() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      hasHandledVideoComplete = false; // 重置播放完成标志
      isUserInitiatedPause = false;
      subtitleNeedLogin = false;
      subtitleRequestSeq++;
      subtitleTracks = [];
      subtitleItems = [];
      selectedSubtitleTrackIndex = -1;
      lastSubtitleIndex = 0;
      currentSubtitleText = '';
      subtitleOwnerBvid = null;
      subtitleOwnerCid = null;
    });

    try {
      final videoInfo = await BilibiliApi.getVideoInfo(widget.video.bvid);

      // 🔥 预先获取本地缓存（在 setState 外部执行 async 操作）
      final cachedRecord = await PlaybackProgressCache.getCachedRecord(
        widget.video.bvid,
      );

      if (videoInfo != null) {
        if (mounted) {
          // 🔥 轻量初始化：只用 pages（通常1项），不解析完整合集
          // 完整合集列表在用户打开选集面板时才按需加载
          setState(() {
            fullVideoInfo = videoInfo;
            episodes = videoInfo['pages'] ?? [];

            // 优先检查历史记录中的 cid
            if (videoInfo['history'] != null &&
                videoInfo['history']['cid'] != null) {
              cid = videoInfo['history']['cid'];
              debugPrint('🎬 [Init] Using API history cid: $cid');
            }

            // 🔥 如果 API 没有返回历史记录，检查本地缓存
            if (cid == null && cachedRecord != null) {
              cid = cachedRecord.cid;
              debugPrint('🎬 [Init] Using LOCAL CACHE cid: $cid');
            }

            cid ??= videoInfo['cid'];
            aid = videoInfo['aid'];
          });
          if (cid == null && episodes.isNotEmpty) {
            cid = episodes[0]['cid'];
          }
          final pages = videoInfo['pages'] as List?;
          if (pages != null && pages.isNotEmpty && cid != null) {
            final pageCidSet = pages
                .whereType<Map>()
                .map((e) => _toInt(e['cid']))
                .where((v) => v > 0)
                .toSet();
            if (pageCidSet.isNotEmpty && !pageCidSet.contains(cid)) {
              final fallbackCid = _toInt(videoInfo['cid']);
              cid = fallbackCid > 0 ? fallbackCid : pageCidSet.first;
            }
          }

          // 🔥 轻量预计算：只提取"是否有多集"和"下一集信息"，用于播放完成后行为
          // 不存储完整列表，避免影响渲染
          _precomputeNextEpisode(videoInfo);

          // 获取在线人数（首次获取 + 每60秒更新）
          _fetchOnlineCount();
          onlineCountTimer?.cancel();
          onlineCountTimer = Timer.periodic(
            const Duration(seconds: 60),
            (_) => _fetchOnlineCount(),
          );
        }
      }

      cid ??= await BilibiliApi.getVideoCid(widget.video.bvid);

      if (cid == null) {
        setState(() {
          errorMessage = '获取视频信息失败';
          isLoading = false;
        });
        return;
      }

      // 按性能模式控制是否在初始化阶段预加载快照
      loadVideoshot(
        preloadAllSprites: SettingsService.preloadVideoshotOnPlayerInit,
        precacheFirstSprite: SettingsService.preloadVideoshotOnPlayerInit,
      );

      // 注意：集数焦点索引在延迟加载完整集数列表后设置（见 deferredEpisodes 逻辑）

      // 异步加载相关视频 (用于播放完成后行为)
      BilibiliApi.getRelatedVideos(widget.video.bvid).then((videos) {
        if (mounted) {
          relatedVideos = videos
              .map(
                (v) => {
                  'bvid': v.bvid,
                  'title': v.title,
                  'pic': v.pic,
                  'duration': v.duration,
                  'pubdate': v.pubdate,
                  'owner': {'name': v.ownerName, 'face': v.ownerFace},
                  'stat': {'view': v.view},
                },
              )
              .toList();
        }
      });

      // 编码器回退重试列表:
      // 1. null = 用户设置优先（自动则按硬件最优 AV1>HEVC>AVC）
      // 2. 失败后按兼容性降级: AVC > HEVC > AV1
      final userCodec = SettingsService.preferredCodec;
      final codecRetryList = <VideoCodec?>[
        null, // 首次：用户设置（自动=智能硬解）
        VideoCodec.avc, // H.264 (兼容性最好)
        VideoCodec.hevc, // HEVC
        VideoCodec.av1, // AV1
      ];

      // 去重（跳过和用户设置相同的，因为首次已经用过）
      final uniqueCodecs = <VideoCodec?>[];
      final seen = <String>{};
      for (final codec in codecRetryList) {
        final key = codec?.name ?? 'user_setting';
        if (codec != null &&
            userCodec != VideoCodec.auto &&
            codec == userCodec) {
          continue;
        }
        if (!seen.contains(key)) {
          seen.add(key);
          uniqueCodecs.add(codec);
        }
      }

      String? lastError;
      final baseQn = currentQuality > 0 ? currentQuality : SettingsService.preferredQualityQn;
      final requestedQn = baseQn;
      // 只做“降级”画质兜底，避免出现先升后降导致的额外等待
      final qualityFallbackList = <int>[
        baseQn,
        if (baseQn > 64) 64,
        if (baseQn > 32) 32,
        if (baseQn > 16) 16,
      ];

      // 尝试每个编码器
      for (final tryCodec in uniqueCodecs) {
        // 二次兜底：同一编码器下按画质降级重试
        qualityLoop:
        for (final tryQn in qualityFallbackList) {
          // 1. 首次请求: 使用默认画质(80)或当前设定画质
          // 这样可以获取到视频实际支持的 accept_quality 列表，而不是盲猜
          var playInfo = await BilibiliApi.getVideoPlayUrl(
            bvid: widget.video.bvid,
            cid: cid!,
            qn: tryQn,
            forceCodec: tryCodec,
          );

          // 2. 智能升级 (仅针对 VIP)
          // 只在首次画质尝试时启用，避免兜底降级时又回到超高画质导致循环失败
          if (AuthService.isVip &&
              tryQn == qualityFallbackList.first &&
              playInfo != null &&
              playInfo['qualities'] != null) {
            final qualities = playInfo['qualities'] as List;
            if (qualities.isNotEmpty) {
              // 获取该视频支持的最高画质
              // qualities 是 List<Map<String, dynamic>>, 需提取 qn 并排序
              final supportedQns = qualities
                  .map((e) => e['qn'] as int)
                  .toList();
              if (supportedQns.isNotEmpty) {
                final maxQn = supportedQns.reduce(
                  (curr, next) => curr > next ? curr : next,
                );
                final currentQn = playInfo['currentQuality'] as int? ?? 0;

                // 如果最高画质 > 当前画质 (且当前画质只是默认的80，或者我们想强制升级)
                // 注意: 有时候 maxQn 可能高达 127/126，而 currentQn 只有 80
                if (maxQn > currentQn) {
                  debugPrint(
                    '🎬 [SmartQuality] VIP detected. Upgrading from $currentQn to $maxQn',
                  );

                  final upgradePlayInfo = await BilibiliApi.getVideoPlayUrl(
                    bvid: widget.video.bvid,
                    cid: cid!,
                    qn: maxQn, // 精确请求最高画质
                    forceCodec: tryCodec,
                  );

                  // 如果升级请求成功，使用新数据
                  if (upgradePlayInfo != null) {
                    playInfo = upgradePlayInfo;
                  }
                }
              }
            }
          }

          if (playInfo == null) {
            lastError =
                '解析播放地址失败(codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn)';
            continue qualityLoop;
          }

          // 检查是否返回了错误信息
          if (playInfo['error'] != null) {
            lastError =
                '${playInfo['error']} (codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn)';
            continue qualityLoop;
          }

          if (!mounted) return;
          qualities = List<Map<String, dynamic>>.from(
            playInfo['qualities'] ?? [],
          );
          currentQuality = playInfo['currentQuality'] ?? tryQn;
          currentCodec = playInfo['codec'] ?? '';
          currentAudioUrl = playInfo['audioUrl'];
          videoWidth = int.tryParse(playInfo['width']?.toString() ?? '') ?? 0;
          videoHeight = int.tryParse(playInfo['height']?.toString() ?? '') ?? 0;
          videoFrameRate =
              double.tryParse(playInfo['frameRate']?.toString() ?? '') ?? 0.0;
          videoDataRateKbps =
              ((int.tryParse(playInfo['videoBandwidth']?.toString() ?? '') ??
                          0) /
                      1000)
                  .round();

          if (currentQuality < requestedQn && mounted) {
            final requested = VideoQuality.fromQn(requestedQn).label;
            final actual = VideoQuality.fromQn(currentQuality).label;
            ToastUtils.show(context, '未达到 $requested，当前 $actual');
          }

          String? playUrl;

          // 如果有 DASH 数据，生成 MPD 并使用全局服务器
          if (playInfo['dashData'] != null) {
            final mpdContent = await MpdGenerator.generate(
              playInfo['dashData'],
              selectedQn: currentQuality,
              selectedCodec: _codecPrefixForMpd(currentCodec),
            );

            // 使用全局 LocalServer 提供 MPD 内容 (纯内存)
            LocalServer.instance.setMpdContent(mpdContent);
            playUrl = LocalServer.instance.mpdUrl;
          } else {
            // 回退到直接 URL (mp4/flv)
            playUrl = playInfo['url'];
          }

          // 未登录/受限清晰度场景下，可能拿不到可播放地址
          if (playUrl == null || playUrl.isEmpty) {
            lastError =
                '未获取到可播放地址(codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn)';
            continue qualityLoop;
          }

          // 创建 VideoPlayerController (快速失败 + 轻量重试)
          const maxRetries = 2;
          const retryDelay = Duration(milliseconds: 500);

          for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
              videoController = VideoPlayerController.networkUrl(
                Uri.parse(playUrl),
                viewType: VideoViewType.platformView,
                httpHeaders: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
                  'Referer': 'https://www.bilibili.com/',
                  'Origin': 'https://www.bilibili.com',
                  if (AuthService.sessdata != null)
                    'Cookie': 'SESSDATA=${AuthService.sessdata}',
                },
              );

              // 初始化
              await videoController!.initialize();
              break; // 成功，跳出循环
            } catch (e) {
              // 清理失败的控制器
              await videoController?.dispose();
              videoController = null;

              final err = e.toString();
              final isCodecInitError =
                  err.contains('MediaCodecVideoRenderer') ||
                  err.contains('Decoder init failed') ||
                  err.contains('ExoPlaybackException') ||
                  err.contains('VideoCodec');

              // 典型硬解初始化错误时直接快速切换兜底分支，不再原地等待重试
              if (isCodecInitError) {
                debugPrint(
                  '视频硬解初始化失败，跳过同组合重试(codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn): $e',
                );
                lastError =
                    '播放器初始化失败(codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn): $e';
                continue qualityLoop;
              }

              if (attempt < maxRetries) {
                // 还有重试机会，等待后重试
                debugPrint('视频初始化失败 (尝试 $attempt/$maxRetries): $e');
                await Future.delayed(retryDelay);
              } else {
                // 单画质重试次数用尽，尝试同编码器的更低画质
                debugPrint('Codec/qn execution failed: $e');
                lastError =
                    '播放器初始化失败(codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn): $e';
                continue qualityLoop;
              }
            }
          }

          if (!mounted) return;

          // 监听播放状态变化
          _setupPlayerListeners();

          if (BuildFlags.pluginsEnabled) {
            // 初始化插件
            final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
            for (var plugin in plugins) {
              plugin.onVideoLoad(widget.video.bvid, cid!);
            }
          }

          setState(() {
            isLoading = false;
          });

          debugPrint(
            '🎬 [Init] Player ready: initialized=${videoController!.value.isInitialized}, '
            'size=${videoController!.value.size}, '
            'duration=${videoController!.value.duration.inMilliseconds}ms, '
            'episodes=${episodes.length}, isUgcSeason=$isUgcSeason, '
            'bvid=${widget.video.bvid}, cid=$cid',
          );

          // 自动续播:
          // 1. 如果 API 返回了历史记录，无条件使用历史记录的进度 (解决多端同步和本地列表过期问题)
          // 2. 如果没有 API 历史，才使用本地列表传进来的 progress
          int historyProgress = 0;
          if (videoInfo != null && videoInfo['history'] != null) {
            final historyData = videoInfo['history'];
            debugPrint(
              '🎬 [Resume] API History: cid=${historyData['cid']}, progress=${historyData['progress']}',
            );
            historyProgress = historyData['progress'] as int? ?? 0;
            // 再次确认 CID 匹配 (一般都匹配，因为前面已经强行切换 CID 了)
            final historyCid = historyData['cid'] as int?;
            if (historyCid != null && historyCid != cid) {
              // 如果历史记录的 CID 和当前 CID 不一致（理论上不该发生，防止万一），不自动跳转进度以防错乱
              debugPrint(
                '🎬 [Resume] CID mismatch: historyCid=$historyCid, cid=$cid - resetting progress',
              );
              historyProgress = 0;
            }
          } else {
            debugPrint('🎬 [Resume] No API history available');
          }

          // 2. 优先使用本地缓存（比列表数据更新鲜）
          if (historyProgress == 0 &&
              cachedRecord != null &&
              cachedRecord.cid == cid) {
            debugPrint(
              '🎬 [Resume] Using LOCAL CACHE: cid=${cachedRecord.cid}, progress=${cachedRecord.progress}',
            );
            historyProgress = cachedRecord.progress;
          }

          // 3. 最后兜底：使用列表传入的 progress（可能是旧数据）
          if (historyProgress == 0 && widget.video.progress > 0) {
            debugPrint(
              '🎬 [Resume] Using list progress (fallback): ${widget.video.progress}',
            );
            historyProgress = widget.video.progress;
          }

          if (historyProgress > 0) {
            // 如果进度接近视频总时长（最后5秒内），说明视频已播完，从头开始
            final videoDuration = videoController!.value.duration.inSeconds;
            if (videoDuration > 0 && historyProgress >= videoDuration - 5) {
              debugPrint(
                '🎬 [Resume] Video was completed (progress $historyProgress >= duration $videoDuration - 5), starting from beginning',
              );
              // 不 seek，直接从头开始播放
            } else {
              initialProgress = historyProgress;

              final seekPos = Duration(seconds: historyProgress);
              await videoController!.seekTo(seekPos);
              resetDanmakuIndex(seekPos);

              final min = historyProgress ~/ 60;
              final sec = historyProgress % 60;
              ToastUtils.show(
                context,
                '从${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}继续播放',
              );
            }
          }

          await videoController!.play();
          // 初始化成功后恢复倍速，并同步弹幕速度（含原生弹幕渲染）
          videoController?.setPlaybackSpeed(playbackSpeed);
          updateDanmakuOption();
          startHideTimer();
          _showTunnelModeHintIfNeeded();

          // 同时有合集和分P时提示用户
          if (isUgcSeason && episodes.length > 1) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                ToastUtils.show(
                  context,
                  '该视频含 ${episodes.length} 个分P，可在选集面板中切换',
                );
              }
            });
          }

          await loadDanmaku();
          await loadSubtitles();
          return; // 成功，退出
        } // qualityLoop 结束
      } // codecLoop 结束

      // ── 最终兜底：用非 DASH(durl/mp4/flv) 再试一次 ──
      debugPrint(
        '🎬 [CompatFallback] All DASH codecs failed, trying durl compat...',
      );
      final compatInfo = await BilibiliApi.getVideoPlayUrlCompat(
        bvid: widget.video.bvid,
        cid: cid!,
        qn: 32, // 最低画质，最大兼容
      );

      if (compatInfo != null &&
          compatInfo['error'] == null &&
          compatInfo['url'] != null) {
        if (!mounted) return;
        qualities = List<Map<String, dynamic>>.from(
          compatInfo['qualities'] ?? [],
        );
        currentQuality = compatInfo['currentQuality'] ?? 32;
        currentCodec = compatInfo['codec'] ?? 'avc_compat';
        currentAudioUrl = null;
        videoWidth = int.tryParse(compatInfo['width']?.toString() ?? '') ?? 0;
        videoHeight = int.tryParse(compatInfo['height']?.toString() ?? '') ?? 0;
        videoFrameRate =
            double.tryParse(compatInfo['frameRate']?.toString() ?? '') ?? 0.0;
        videoDataRateKbps =
            ((int.tryParse(compatInfo['videoBandwidth']?.toString() ?? '') ??
                        0) /
                    1000)
                .round();

        final playUrl = compatInfo['url'] as String;

        try {
          videoController = VideoPlayerController.networkUrl(
            Uri.parse(playUrl),
            viewType: VideoViewType.platformView,
            httpHeaders: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
              'Referer': 'https://www.bilibili.com/',
              'Origin': 'https://www.bilibili.com',
              if (AuthService.sessdata != null)
                'Cookie': 'SESSDATA=${AuthService.sessdata}',
            },
          );
          await videoController!.initialize();

          debugPrint('🎬 [CompatFallback] durl playback succeeded!');

          _setupPlayerListeners();

          if (BuildFlags.pluginsEnabled) {
            final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
            for (var plugin in plugins) {
              plugin.onVideoLoad(widget.video.bvid, cid!);
            }
          }

          setState(() {
            isLoading = false;
          });

          await videoController!.play();
          // 兼容回退路径也要恢复倍速，并同步弹幕速度（含原生弹幕渲染）
          videoController?.setPlaybackSpeed(playbackSpeed);
          updateDanmakuOption();
          startHideTimer();
          _showTunnelModeHintIfNeeded();
          await loadDanmaku();
          await loadSubtitles();
          return; // 兜底成功
        } catch (e) {
          await videoController?.dispose();
          videoController = null;
          debugPrint('🎬 [CompatFallback] durl also failed: $e');
          lastError = '兼容模式也失败: $e';
        }
      }

      // 所有方式都失败了
      throw Exception(lastError ?? '视频加载失败');
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
          isLoading = false;
        });
      }
    }
  }

  Future<void> loadDanmaku() async {
    if (cid == null) return;
    try {
      final danmaku = await BilibiliApi.getDanmaku(cid!);
      if (!mounted) return;
      setState(() {
        danmakuList = danmaku;
        danmakuList.sort((a, b) => a.time.compareTo(b.time));
        lastDanmakuIndex = 0;
      });
    } catch (e) {
      debugPrint('Failed to load danmaku: $e');
    }
  }

  bool _isSubtitleRequestStale({
    required int requestSeq,
    required String requestBvid,
    required int requestCid,
  }) {
    return !mounted ||
        subtitleRequestSeq != requestSeq ||
        widget.video.bvid != requestBvid ||
        cid != requestCid;
  }

  void _clearSubtitleState({required bool bumpRequestSeq}) {
    if (bumpRequestSeq) {
      subtitleRequestSeq++;
    }
    subtitleTracks = [];
    subtitleItems = [];
    selectedSubtitleTrackIndex = -1;
    lastSubtitleIndex = 0;
    currentSubtitleText = '';
    subtitleNeedLogin = false;
    subtitleOwnerBvid = null;
    subtitleOwnerCid = null;
  }

  Future<void> loadSubtitles() async {
    if (cid == null) return;
    final requestBvid = widget.video.bvid;
    final requestCid = cid!;
    final requestSeq = ++subtitleRequestSeq;

    if (mounted) {
      setState(() {
        _clearSubtitleState(bumpRequestSeq: false);
      });
    }

    try {
      final trackResult = await BilibiliApi.getSubtitleTracksWithMeta(
        bvid: requestBvid,
        cid: requestCid,
        aid: aid,
      );
      if (_isSubtitleRequestStale(
        requestSeq: requestSeq,
        requestBvid: requestBvid,
        requestCid: requestCid,
      )) {
        return;
      }

      int trackIndex = -1;
      setState(() {
        subtitleNeedLogin = trackResult.needLoginSubtitle;
        subtitleTracks = trackResult.tracks;
        subtitleItems = [];
        currentSubtitleText = '';
        lastSubtitleIndex = 0;
        subtitleOwnerBvid = null;
        subtitleOwnerCid = null;

        if (subtitleTracks.isEmpty) {
          selectedSubtitleTrackIndex = -1;
          trackIndex = -1;
        } else {
          if (selectedSubtitleTrackIndex < 0 ||
              selectedSubtitleTrackIndex >= subtitleTracks.length) {
            selectedSubtitleTrackIndex = 0;
          }
          trackIndex = selectedSubtitleTrackIndex;
        }
      });

      if (trackIndex >= 0) {
        await _loadSubtitleTrack(
          index: trackIndex,
          requestSeq: requestSeq,
          requestBvid: requestBvid,
          requestCid: requestCid,
        );
      }
    } catch (e) {
      debugPrint('Failed to load subtitles: $e');
    }
  }

  Future<void> _loadSubtitleTrack({
    required int index,
    required int requestSeq,
    required String requestBvid,
    required int requestCid,
  }) async {
    if (index < 0 || index >= subtitleTracks.length) return;
    final track = subtitleTracks[index];
    final items = await BilibiliApi.getSubtitleItems(track.subtitleUrl);
    if (_isSubtitleRequestStale(
      requestSeq: requestSeq,
      requestBvid: requestBvid,
      requestCid: requestCid,
    )) {
      return;
    }
    setState(() {
      selectedSubtitleTrackIndex = index;
      subtitleItems = items;
      currentSubtitleText = '';
      lastSubtitleIndex = 0;
      subtitleOwnerBvid = widget.video.bvid;
      subtitleOwnerCid = requestCid;
    });
    if (videoController != null && videoController!.value.isInitialized) {
      resetSubtitleIndex(videoController!.value.position);
    }
  }

  Future<void> _persistSubtitleEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitle_enabled', subtitleEnabled);
  }

  /// 设置播放器监听器
  void _setupPlayerListeners() {
    if (videoController == null) return;

    videoController!.addListener(_onPlayerStateChange);
    _startDanmakuSyncTimer();
    _applyDanmakuOptionWithRetry();
  }

  void _onPlayerStateChange() {
    if (videoController == null || !mounted) return;

    // 如果视频已完成，忽略后续状态变化（防止末尾卡顿循环）
    if (hasHandledVideoComplete) return;

    final value = videoController!.value;

    final now = DateTime.now();

    // 检查是否需要预加载下一张雪碧图
    _checkSpritePreload(value.position);
    _syncSubtitle(value.position);

    // 下一集预览倒计时（多集/合集 + 播放下一集模式）
    _updateNextEpisodePreview(value);

    // ── 播放完成检测 (三级策略) ──
    final int posMs = value.position.inMilliseconds;
    final int durMs = value.duration.inMilliseconds;
    final bool isSeeking =
        pendingSeekTarget != null || isSeekPreviewMode || isProgressBarFocused;

    // 策略1 - 软着陆: 正常播放接近末尾时主动暂停(500ms)
    //   解决: TV 解码器 EOS 帧闪烁
    final bool isSoftEnd =
        !isLoopMode && durMs >= 1000 && value.isPlaying && posMs >= durMs - 500;

    // 策略2 - 末尾停转: 最后 5 秒内 isPlaying 意外变 false
    //   解决: DASH 分段边界导致的末尾卡顿(position停滞→跳到末尾)
    //   排除: 用户主动暂停、缓冲中、快进中
    final bool isEndZoneStall =
        !isLoopMode &&
        durMs >= 1000 &&
        !value.isPlaying &&
        !value.isBuffering &&
        !value.isCompleted &&
        !value.hasError &&
        value.isInitialized &&
        !isUserInitiatedPause &&
        !isSeeking &&
        posMs >= durMs - 5000;

    if (isSoftEnd) {
      completionFallbackTimer?.cancel();
      completionFallbackTimer = null;
      onVideoComplete();
    } else if (value.isCompleted && !isLoopMode) {
      completionFallbackTimer?.cancel();
      completionFallbackTimer = null;
      onVideoComplete();
    } else if (isEndZoneStall) {
      // 短防抖(200ms): 确认不是瞬间状态抖动
      completionFallbackTimer ??= Timer(const Duration(milliseconds: 200), () {
        completionFallbackTimer = null;
        if (!mounted || videoController == null || hasHandledVideoComplete)
          return;
        final v = videoController!.value;
        if (!v.isPlaying &&
            v.isInitialized &&
            v.position.inMilliseconds >= v.duration.inMilliseconds - 5000) {
          onVideoComplete();
        }
      });
    } else if (!isLoopMode) {
      // 策略4 - 兜底: position 接近 duration 且停止播放(800ms 防抖)
      final bool isNearEnd = durMs >= 1000 && posMs >= durMs - 1000;

      if (!value.isPlaying && value.isInitialized && isNearEnd) {
        completionFallbackTimer ??= Timer(
          const Duration(milliseconds: 800),
          () {
            completionFallbackTimer = null;
            if (!mounted || videoController == null || hasHandledVideoComplete)
              return;
            final v = videoController!.value;
            final stillNearEnd =
                v.duration.inSeconds >= 1 &&
                v.position.inMilliseconds >= v.duration.inMilliseconds - 1000;
            if (!v.isPlaying && v.isInitialized && stillNearEnd) {
              onVideoComplete();
            }
          },
        );
      } else {
        completionFallbackTimer?.cancel();
        completionFallbackTimer = null;
      }
    }

    // 插件链路节流，避免每帧触发异步任务
    if (BuildFlags.pluginsEnabled) {
      final shouldHandlePlugin =
          lastPluginHandleAt == null ||
          now.difference(lastPluginHandleAt!) >=
              const Duration(milliseconds: 250);
      if (shouldHandlePlugin) {
        lastPluginHandleAt = now;
        _handlePlugins(value.position);
      }
    }

    // 控制层隐藏时降低 UI 刷新频率，减少 Flutter 侧重建抖动
    final isUiBusy =
        showControls ||
        showSettingsPanel ||
        showEpisodePanel ||
        showUpPanel ||
        showRelatedPanel ||
        showActionButtons ||
        showCommentPanel ||
        showSeekIndicator ||
        isProgressBarFocused ||
        showStatsForNerds ||
        showNextEpisodePreview;
    final uiInterval = isUiBusy
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 2000);
    final shouldRebuildUi =
        (nextEpisodeInfo != null && showNextEpisodePreview) ||
        lastUiRebuildAt == null ||
        now.difference(lastUiRebuildAt!) >= uiInterval;
    if (shouldRebuildUi) {
      lastUiRebuildAt = now;
      setState(() {});
    }
  }

  /// 查找下一集信息（使用预计算数据，O(1)）
  Map<String, dynamic>? _findNextEpisode() {
    return precomputedNextEpisode;
  }

  /// 更新下一集预览倒计时
  void _updateNextEpisodePreview(VideoPlayerValue value) {
    if (SettingsService.playbackCompletionAction !=
            PlaybackCompletionAction.playNextEpisode ||
        hasHandledVideoComplete ||
        !hasMultipleEpisodes) {
      if (showNextEpisodePreview) {
        showNextEpisodePreview = false;
      }
      return;
    }

    // 需要有效的 duration 且视频已播放足够长（防止 duration 尚未稳定时误触发）
    if (value.duration <= Duration.zero ||
        value.duration.inSeconds < 5 ||
        value.position.inSeconds < 3) {
      return;
    }

    final remainingMs =
        value.duration.inMilliseconds - value.position.inMilliseconds;
    final remainingSec = (remainingMs / 1000).ceil();

    // 距离结束 15 秒以内时显示预览
    if (remainingSec <= 15 && remainingSec > 0) {
      if (!showNextEpisodePreview) {
        final next = _findNextEpisode();
        if (next != null) {
          nextEpisodeInfo = next;
          showNextEpisodePreview = true;
        }
      }
      if (showNextEpisodePreview) {
        nextEpisodeCountdown = remainingSec;
      }
    } else if (remainingSec > 15 && showNextEpisodePreview) {
      // 用户拖回进度条，隐藏预览
      showNextEpisodePreview = false;
      nextEpisodeInfo = null;
    }
  }

  void _handlePlugins(Duration position) async {
    if (!BuildFlags.pluginsEnabled) return;
    final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
    if (plugins.isEmpty) return;

    final positionMs = position.inMilliseconds;
    SkipAction? newAction;

    for (var plugin in plugins) {
      final action = await plugin.onPositionUpdate(positionMs);
      if (action is SkipActionSkipTo) {
        if (!mounted) return;
        final skippedSec = ((action.positionMs - positionMs) / 1000).round();
        videoController?.seekTo(Duration(milliseconds: action.positionMs));
        resetDanmakuIndex(Duration(milliseconds: action.positionMs));
        ToastUtils.show(
          context,
          '${action.reason} (${skippedSec}s)',
          duration: const Duration(milliseconds: 2000),
        );
        // 跳过也可能需要清除之前的按钮
        newAction = null;
        break; // 优先处理跳过
      } else if (action is SkipActionShowButton) {
        newAction = action;
      }
    }

    // 更新 UI 状态
    if (mounted && currentSkipAction != newAction) {
      // 简单的去重，如果是同一个片段ID则不更新
      if (currentSkipAction is SkipActionShowButton &&
          newAction is SkipActionShowButton) {
        if (currentSkipAction.segmentId == newAction.segmentId) {
          return;
        }
      }
      setState(() {
        currentSkipAction = newAction;
      });
    } else if (mounted && newAction == null && currentSkipAction != null) {
      setState(() {
        currentSkipAction = null;
      });
    }
  }

  /// 清理播放器监听器
  void cancelPlayerListeners() {
    videoController?.removeListener(_onPlayerStateChange);
    danmakuSyncTimer?.cancel();
    danmakuSyncTimer = null;
    danmakuOptionApplyTimer?.cancel();
    danmakuOptionApplyTimer = null;
    NativePlayerDanmakuService.clear(videoController);
    completionFallbackTimer?.cancel();
    completionFallbackTimer = null;
  }

  Future<void> disposePlayer() async {
    // Snapshot progress data BEFORE releasing the player, so we can report
    // after ExoPlayer is freed (network calls must not block codec release).
    final bvid = widget.video.bvid;
    final cidSnapshot = cid;
    int? posSnapshot;
    if (videoController != null && videoController!.value.isInitialized) {
      posSnapshot = videoController!.value.position.inSeconds;
    }

    // ── Phase 1: Release ExoPlayer / MediaCodec IMMEDIATELY ──
    cancelPlayerListeners();
    seekIndicatorTimer?.cancel();
    seekCommitTimer?.cancel();
    bufferHideTimer?.cancel();
    onlineCountTimer?.cancel();
    statsTimer?.cancel();
    _clearSpritesFromMemory();

    if (BuildFlags.pluginsEnabled) {
      final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
      for (var plugin in plugins) {
        plugin.onVideoEnd();
      }
    }

    await videoController?.pause();
    await videoController?.dispose();
    videoController = null;
    danmakuController = null;
    LocalServer.instance.clearMpdContent();
    subtitleRequestSeq++;
    subtitleTracks = [];
    subtitleItems = [];
    selectedSubtitleTrackIndex = -1;
    lastSubtitleIndex = 0;
    currentSubtitleText = '';
    subtitleNeedLogin = false;
    subtitleOwnerBvid = null;
    subtitleOwnerCid = null;

    // ── Phase 2: Network / storage (player already freed) ──
    if (cidSnapshot != null && posSnapshot != null && posSnapshot > 5) {
      await PlaybackProgressCache.saveProgress(bvid, cidSnapshot, posSnapshot);
      debugPrint(
        '🎬 [Cache] Saved progress: bvid=$bvid, cid=$cidSnapshot, pos=$posSnapshot',
      );
    }

    if (cidSnapshot != null) {
      BilibiliApi.reportProgress(
        bvid: bvid,
        cid: cidSnapshot,
        progress: posSnapshot ?? 0,
      );
    }
  }

  /// 获取在线观看人数
  Future<void> _fetchOnlineCount() async {
    if (aid == null || cid == null) return;

    final result = await BilibiliApi.getOnlineCount(aid: aid!, cid: cid!);
    if (mounted && result != null) {
      setState(() {
        onlineCount = result['total'] ?? result['count'];
      });
    }
  }

  /// 🔥 轻量预计算：从 API 数据中提取当前集标题、是否多集、下一集信息
  /// 不存储完整列表，O(N) 只跑一次
  void _precomputeNextEpisode(Map<String, dynamic> videoInfo) {
    try {
      final ugcSeason = videoInfo['ugc_season'];
      if (ugcSeason != null && ugcSeason is Map) {
        final sections = ugcSeason['sections'];
        if (sections is List && sections.isNotEmpty) {
          // 遍历一次，只提取当前和下一集
          dynamic currentEpRaw;
          Map<String, dynamic>? nextEp;
          bool foundCurrent = false;
          int totalCount = 0;

          for (final section in sections) {
            if (section is! Map) continue;
            final eps = section['episodes'];
            if (eps is! List) continue;
            for (final ep in eps) {
              if (ep is! Map) continue;
              totalCount++;
              if (foundCurrent && nextEp == null) {
                // 上一个是当前集，这个就是下一集
                nextEp = {
                  'bvid': ep['bvid'] ?? '',
                  'cid': ep['cid'] ?? 0,
                  'aid': ep['aid'] ?? 0,
                  'title':
                      ep['title'] ??
                      (ep['arc'] is Map ? ep['arc']['title'] : null) ??
                      '',
                  'pic': (ep['arc'] is Map ? ep['arc']['pic'] : null) ?? '',
                  'duration':
                      (ep['arc'] is Map ? ep['arc']['duration'] : null) ?? 0,
                };
                break; // 找到下一集即可退出
              }
              if (ep['bvid'] == widget.video.bvid) {
                foundCurrent = true;
                currentEpRaw = ep;
              }
            }
            if (nextEp != null) break;
          }

          if (totalCount > 1) {
            isUgcSeason = true;
            hasMultipleEpisodes = true;
            currentEpisodeTitle =
                currentEpRaw?['title'] ??
                (currentEpRaw?['arc'] is Map
                    ? currentEpRaw['arc']['title']
                    : null) ??
                '';
            precomputedNextEpisode = nextEp;
            debugPrint(
              '🎬 [Init] UGC Season: $totalCount eps, '
              'current=$currentEpisodeTitle, hasNext=${nextEp != null}',
            );
            // 不 return：继续检查 pages，若有多P则优先播放下一P
          }
        }
      }
    } catch (e) {
      debugPrint('🎬 [Init] UGC precompute error: $e');
    }

    // 检查 pages 是否多P（同时有合集时，分P优先用于自动播放下一集）
    final pages = videoInfo['pages'] as List?;
    if (pages != null && pages.length > 1) {
      hasMultipleEpisodes = true;
      for (int i = 0; i < pages.length; i++) {
        if (pages[i]['cid'] == cid) {
          if (!isUgcSeason) {
            currentEpisodeTitle =
                pages[i]['part'] ?? pages[i]['page_part'] ?? '';
          }
          if (i + 1 < pages.length) {
            final nextPage = pages[i + 1];
            final partName = nextPage['part'] ?? nextPage['page_part'] ?? '';
            precomputedNextEpisode = {
              'cid': nextPage['cid'],
              'title': 'P${i + 2} $partName',
              'pic': videoInfo['pic'] ?? '',
            };
          }
          break;
        }
      }
      debugPrint(
        '🎬 [Init] Multi-P: ${pages.length} pages, hasNext=${precomputedNextEpisode != null}',
      );
    }
  }

  /// 🔥 按需加载完整集数列表（用户打开选集面板时调用）
  void ensureEpisodesLoaded() {
    if (episodesFullyLoaded) return;
    if (fullVideoInfo == null) return;

    final videoInfo = fullVideoInfo!;
    final pages = videoInfo['pages'] as List?;
    final hasMultiPages = pages != null && pages.length > 1;

    try {
      final ugcSeason = videoInfo['ugc_season'];
      if (ugcSeason != null && ugcSeason is Map) {
        final sections = ugcSeason['sections'];
        if (sections is List && sections.isNotEmpty) {
          final ugcEpisodes = <Map<String, dynamic>>[];
          for (final section in sections) {
            if (section is! Map) continue;
            final eps = section['episodes'];
            if (eps is! List) continue;
            for (final ep in eps) {
              if (ep is! Map) continue;
              ugcEpisodes.add({
                'bvid': ep['bvid'] ?? '',
                'cid':
                    ep['cid'] ??
                    (ep['page'] is Map ? ep['page']['cid'] : null) ??
                    0,
                'aid': ep['aid'] ?? 0,
                'title':
                    ep['title'] ??
                    (ep['arc'] is Map ? ep['arc']['title'] : null) ??
                    '',
                'duration':
                    (ep['arc'] is Map ? ep['arc']['duration'] : null) ??
                    (ep['page'] is Map ? ep['page']['duration'] : null) ??
                    0,
                'pic': (ep['arc'] is Map ? ep['arc']['pic'] : null) ?? '',
              });
            }
          }
          if (ugcEpisodes.length > 1) {
            if (hasMultiPages) {
              // 同时存在合集和分P，保存两份列表，默认显示分P
              setState(() {
                episodeTabUgc = ugcEpisodes;
                episodeTabPages = List<dynamic>.from(pages!);
                hasBothEpisodeTypes = true;
                episodePanelShowingPages = true;
                episodes = episodeTabPages;
              });
              final pageIdx = episodeTabPages.indexWhere(
                (e) => e['cid'] == cid,
              );
              if (pageIdx != -1) {
                focusedEpisodeIndex = pageIdx;
                focusedPageIndex = pageIdx;
              }
              final ugcIdx = episodeTabUgc.indexWhere(
                (e) => e['bvid'] == widget.video.bvid,
              );
              if (ugcIdx != -1) focusedUgcIndex = ugcIdx;
              debugPrint(
                '🎬 [LazyLoad] Both types: ${episodeTabPages.length} pages, '
                '${episodeTabUgc.length} UGC episodes',
              );
            } else {
              // 仅合集
              setState(() {
                episodes = ugcEpisodes;
                isUgcSeason = true;
              });
              final idx = episodes.indexWhere(
                (e) => e['bvid'] == widget.video.bvid,
              );
              if (idx != -1) focusedEpisodeIndex = idx;
              debugPrint(
                '🎬 [LazyLoad] UGC episodes loaded: ${episodes.length}',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('🎬 [LazyLoad] UGC parse error: $e');
    }

    // 对于普通分P（无合集），episodes 已经是 pages，设置焦点索引即可
    if (!isUgcSeason && !hasBothEpisodeTypes && episodes.length > 1) {
      final idx = episodes.indexWhere((e) => e['cid'] == cid);
      if (idx != -1) focusedEpisodeIndex = idx;
    }

    episodesFullyLoaded = true;
  }

  /// 切换选集面板的分P/合集标签
  void switchEpisodeTab() {
    if (!hasBothEpisodeTypes) return;
    setState(() {
      if (episodePanelShowingPages) {
        focusedPageIndex = focusedEpisodeIndex;
        episodes = episodeTabUgc;
        episodePanelShowingPages = false;
        focusedEpisodeIndex = focusedUgcIndex;
      } else {
        focusedUgcIndex = focusedEpisodeIndex;
        episodes = episodeTabPages;
        episodePanelShowingPages = true;
        focusedEpisodeIndex = focusedPageIndex;
      }
    });
  }

  /// 选集面板当前是否在显示分P列表
  bool get isPanelShowingPages =>
      hasBothEpisodeTypes ? episodePanelShowingPages : !isUgcSeason;

  /// 获取用于显示的视频信息（优先使用 API 获取的完整信息）
  models.Video getDisplayVideo() {
    if (fullVideoInfo == null) {
      return widget.video;
    }

    final info = fullVideoInfo!;
    final owner = info['owner'] ?? {};
    final stat = info['stat'] ?? {};

    var displayTitle = info['title'] ?? widget.video.title;

    // 使用预计算的当前集标题（O(1)，不遍历列表）
    if (hasMultipleEpisodes &&
        currentEpisodeTitle != null &&
        currentEpisodeTitle!.isNotEmpty) {
      displayTitle = '$displayTitle - $currentEpisodeTitle';
    }

    return models.Video(
      bvid: widget.video.bvid,
      title: displayTitle,
      pic: info['pic'] ?? widget.video.pic,
      ownerName: owner['name'] ?? widget.video.ownerName,
      ownerFace: owner['face'] ?? widget.video.ownerFace,
      ownerMid: owner['mid'] ?? widget.video.ownerMid,
      view: stat['view'] ?? widget.video.view,
      danmaku: stat['danmaku'] ?? widget.video.danmaku,
      pubdate: info['pubdate'] ?? widget.video.pubdate,
      duration: info['duration'] ?? widget.video.duration,
      // 关键：保留从列表传入的播放进度和观看时间，否则会丢失进度导致从头播放
      progress: widget.video.progress,
      viewAt: widget.video.viewAt,
    );
  }

  void exitPlayer() {
    // Keep manual close/back/completion behavior aligned to avoid focus
    // or status glitches during route transitions.
    cancelPlayerListeners();
    videoController?.pause();
    _popByConfiguredDepth();
  }

  void _popByConfiguredDepth() {
    final navigator = Navigator.of(context);
    var remaining = widget.exitPopDepth;
    navigator.popUntil((route) {
      if (route.isFirst) return true;
      if (remaining <= 0) return true;
      remaining--;
      return false;
    });
  }

  void _exitPlayerAfterCompletion() {
    // 与手动退出保持一致：按来源决定退出层级。
    exitPlayer();
  }

  /// 视频播放完成回调
  void onVideoComplete() {
    // 防止重复触发
    if (hasHandledVideoComplete) return;
    hasHandledVideoComplete = true;

    // 隐藏下一集预览
    showNextEpisodePreview = false;
    nextEpisodeInfo = null;

    // 取消防抖定时器
    completionFallbackTimer?.cancel();
    completionFallbackTimer = null;

    // 暂停播放器即可，不做 seekTo 回退
    // (回退到 duration-100ms 会导致 ExoPlayer 重播最后片段，产生末尾帧闪烁)
    videoController?.pause();

    hideTimer?.cancel();
    setState(() => showControls = true);

    final completionAction = SettingsService.playbackCompletionAction;

    if (completionAction == PlaybackCompletionAction.exit) {
      reportPlaybackProgress(overrideProgress: -1);
      _exitPlayerAfterCompletion();
      return;
    }

    if (completionAction == PlaybackCompletionAction.playNextEpisode) {
      // 检查是否有下一集（使用预计算数据，O(1)）
      if (precomputedNextEpisode != null) {
        final nextEp = precomputedNextEpisode!;
        final nextTitle = nextEp['title'] ?? '下一集';
        ToastUtils.show(context, '自动播放下一集: $nextTitle');

        final nextBvid = nextEp['bvid'] as String? ?? '';
        if (nextBvid.isNotEmpty && nextBvid != widget.video.bvid && mounted) {
          // 合集：目标是不同 bvid，导航到新播放器
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                video: models.Video(
                  bvid: nextBvid,
                  title: nextEp['title'] ?? '',
                  pic: nextEp['pic'] ?? '',
                  ownerName: widget.video.ownerName,
                  ownerFace: widget.video.ownerFace,
                  duration: nextEp['duration'] ?? 0,
                  pubdate: widget.video.pubdate,
                  view: 0,
                ),
              ),
            ),
          );
        } else if (nextEp['cid'] != null) {
          // 分P：同一视频内切换 cid
          switchEpisode(nextEp['cid'] as int);
        }
      }
      reportPlaybackProgress(overrideProgress: -1);
      return;
    }

    if (completionAction == PlaybackCompletionAction.playRecommended) {
      if (relatedVideos.isNotEmpty) {
        final nextVideo = relatedVideos.first;
        ToastUtils.show(context, '自动播放推荐视频');
        // 导航到新视频
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              video: models.Video(
                bvid: nextVideo['bvid'] ?? '',
                title: nextVideo['title'] ?? '',
                pic: nextVideo['pic'] ?? '',
                ownerName: nextVideo['owner']?['name'] ?? '',
                ownerFace: nextVideo['owner']?['face'] ?? '',
                duration: nextVideo['duration'] ?? 0,
                pubdate: nextVideo['pubdate'] ?? 0,
                view: nextVideo['stat']?['view'] ?? 0,
              ),
            ),
          ),
        );
      }
      reportPlaybackProgress(overrideProgress: -1);
      return;
    }

    // pause: 无后续动作，保持暂停状态。

    // 🔥 无论是否有后续动作，都强制上报一次"已看完"
    reportPlaybackProgress(overrideProgress: -1);
  }

  /// 上报播放进度 (暂停/退出时调用)
  Future<void> reportPlaybackProgress({int? overrideProgress}) async {
    if (videoController == null ||
        cid == null ||
        (overrideProgress == null && !videoController!.value.isInitialized)) {
      return;
    }

    final progress =
        overrideProgress ?? videoController!.value.position.inSeconds;

    // 上报到B站
    await BilibiliApi.reportProgress(
      bvid: widget.video.bvid,
      cid: cid!,
      progress: progress,
    );
  }

  void syncDanmaku(double currentTime) {
    if (!danmakuEnabled) {
      return;
    }
    final useNativeDanmaku = useNativeDanmakuRender;
    if (useNativeDanmaku && videoController == null) return;
    if (!useNativeDanmaku && danmakuController == null) return;

    if (lastDanmakuIndex < danmakuList.length) {
      final nextDmTime = danmakuList[lastDanmakuIndex].time;
      // 检测跳转 (Seek)
      if (currentTime - nextDmTime > 5.0) {
        resetDanmakuIndex(Duration(seconds: currentTime.toInt()));
        return;
      }
    }

    final plugins = BuildFlags.pluginsEnabled
        ? PluginManager().getEnabledPlugins<DanmakuPlugin>()
        : const <DanmakuPlugin>[];

    List<DanmakuContentItem>? nativeBatch;
    if (useNativeDanmaku) {
      nativeBatch = <DanmakuContentItem>[];
    }

    while (lastDanmakuIndex < danmakuList.length) {
      final dm = danmakuList[lastDanmakuIndex];
      final time = dm.time;

      if (time <= currentTime) {
        if (currentTime - time < 1.0) {
          Map<String, dynamic>? dmItem = {
            'content': dm.content,
            'color': dm.color,
          };

          DanmakuStyle? style;

          for (var plugin in plugins) {
            if (dmItem == null) break;
            dmItem = plugin.filterDanmaku(dmItem);
            if (dmItem != null) {
              final s = plugin.styleDanmaku(dmItem);
              if (s != null) style = s;
            }
          }

          if (dmItem != null) {
            Color color = Color(dmItem['color'] as int).withValues(alpha: 255);
            if (style != null && style.borderColor != null) {
              color = style.borderColor!;
            }

            final item = DanmakuContentItem(
              dmItem['content'] as String,
              color: color,
            );
            if (nativeBatch != null) {
              nativeBatch.add(item);
            } else if (danmakuController != null) {
              danmakuController!.addDanmaku(item);
            }
          }
        }
        lastDanmakuIndex++;
      } else {
        break;
      }
    }

    if (nativeBatch != null && nativeBatch.isNotEmpty) {
      NativePlayerDanmakuService.addDanmakuBatch(videoController, nativeBatch);
    }
  }

  void _startDanmakuSyncTimer() {
    danmakuSyncTimer?.cancel();
    danmakuSyncTimer = Timer.periodic(SettingsService.danmakuSyncInterval, (_) {
      if (!mounted ||
          !danmakuEnabled ||
          videoController == null ||
          !videoController!.value.isInitialized ||
          !videoController!.value.isPlaying ||
          (useNativeDanmakuRender ? false : danmakuController == null)) {
        return;
      }
      syncDanmaku(videoController!.value.position.inMilliseconds / 1000.0);
    });
  }

  void resetDanmakuIndex(Duration position) {
    if (danmakuList.isEmpty) return;
    final seconds = position.inSeconds.toDouble();
    int index = danmakuList.indexWhere((dm) => dm.time >= seconds);
    if (index == -1) {
      index = danmakuList.length;
    }
    lastDanmakuIndex = index;
  }

  void resetSubtitleIndex(Duration position) {
    if (subtitleItems.isEmpty) {
      if (currentSubtitleText.isNotEmpty) {
        setState(() => currentSubtitleText = '');
      }
      return;
    }
    final seconds = position.inMilliseconds / 1000.0;
    int index = subtitleItems.indexWhere((item) => item.to > seconds);
    if (index < 0) {
      index = subtitleItems.length;
    }
    lastSubtitleIndex = index;
    _syncSubtitle(position);
  }

  void _syncSubtitle(Duration position) {
    final ownerMatched =
        subtitleOwnerBvid == widget.video.bvid && subtitleOwnerCid == cid;
    if (!ownerMatched) {
      if (subtitleItems.isNotEmpty || currentSubtitleText.isNotEmpty) {
        setState(() {
          subtitleItems = [];
          currentSubtitleText = '';
          lastSubtitleIndex = 0;
        });
      }
      return;
    }

    if (!subtitleEnabled || subtitleItems.isEmpty) {
      if (currentSubtitleText.isNotEmpty) {
        setState(() => currentSubtitleText = '');
      }
      return;
    }

    final now = position.inMilliseconds / 1000.0;
    if (lastSubtitleIndex >= subtitleItems.length) {
      if (currentSubtitleText.isNotEmpty) {
        setState(() => currentSubtitleText = '');
      }
      return;
    }

    while (lastSubtitleIndex < subtitleItems.length &&
        subtitleItems[lastSubtitleIndex].to <= now) {
      lastSubtitleIndex++;
    }

    String nextText = '';
    if (lastSubtitleIndex < subtitleItems.length) {
      final item = subtitleItems[lastSubtitleIndex];
      if (now >= item.from && now < item.to) {
        nextText = item.content;
      } else if (now < item.from && lastSubtitleIndex > 0) {
        // 回退 seek 时尝试向前纠正索引。
        int i = lastSubtitleIndex - 1;
        while (i >= 0 && subtitleItems[i].to > now) {
          if (now >= subtitleItems[i].from) {
            lastSubtitleIndex = i;
            nextText = subtitleItems[i].content;
            break;
          }
          i--;
        }
      }
    }

    if (nextText != currentSubtitleText) {
      setState(() {
        currentSubtitleText = nextText;
      });
    }
  }

  /// 获取进度条显示位置
  /// 优先级：播放完成 > pendingSeekTarget > lastCommittedSeekTarget（2秒内）> 播放器实际位置
  Duration getDisplayPosition() {
    if (videoController == null) return Duration.zero;

    // 播放完成（含软着陆），显示为总时长，避免停留在 duration-500ms
    if (hasHandledVideoComplete) {
      return videoController!.value.duration;
    }

    // 正在快进中，使用累积目标位置
    if (pendingSeekTarget != null) {
      return pendingSeekTarget!;
    }

    // 刚提交过快进（2秒内），使用上次提交的位置，避免 seekTo 延迟导致的回退
    if (lastCommittedSeekTarget != null && lastSeekCommitTime != null) {
      final elapsed = DateTime.now().difference(lastSeekCommitTime!);
      if (elapsed.inMilliseconds < 2000) {
        return lastCommittedSeekTarget!;
      }
    }

    // 正常播放，使用播放器实际位置
    return videoController!.value.position;
  }

  void toggleControls() {
    setState(() => showControls = true);
    if (!showSettingsPanel) {
      startHideTimer();
    }
  }

  void startHideTimer() {
    hideTimer?.cancel();
    if (showSettingsPanel) return;

    if (videoController?.value.isPlaying ?? false) {
      hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            showControls = false;
            showActionButtons = false;
          });
        }
      });
    }
  }

  void togglePlayPause() {
    if (videoController == null) return;

    if (videoController!.value.isPlaying) {
      isUserInitiatedPause = true;
      videoController!.pause();
      NativePlayerDanmakuService.pause(videoController);
      danmakuController?.pause();
      hideTimer?.cancel();
      // 暂停时上报进度
      reportPlaybackProgress();
      // 暂停时只显示暂停符号，不显示控制栏
    } else {
      isUserInitiatedPause = false;
      // 播放完成后按播放键：从头开始重播
      if (hasHandledVideoComplete) {
        hasHandledVideoComplete = false;
        videoController!.seekTo(Duration.zero);
        resetDanmakuIndex(Duration.zero);
        resetSubtitleIndex(Duration.zero);
      }
      videoController!.play();
      NativePlayerDanmakuService.resume(videoController);
      danmakuController?.resume();
      startHideTimer();
    }
    setState(() {});
  }

  /// 根据连续快进次数计算步长（渐进加速）
  Duration _getSeekStep() {
    if (seekRepeatCount < 6) return const Duration(seconds: 5);
    if (seekRepeatCount < 16) return const Duration(seconds: 10);
    if (seekRepeatCount < 30) return const Duration(seconds: 20);
    if (seekRepeatCount < 50) return const Duration(seconds: 40);
    return const Duration(seconds: 60);
  }

  void seekForward() {
    if (videoController == null) return;
    if (hasHandledVideoComplete) return; // 已播完，快进无意义
    final total = videoController!.value.duration;

    // 检查是否开启预览模式且有快照数据
    if (SettingsService.seekPreviewMode && videoshotData != null) {
      // 预览模式: 暂停视频，只更新预览位置
      videoController?.pause();
      final current = previewPosition ?? videoController!.value.position;
      final newPos = current + const Duration(seconds: 10);
      final target = newPos < total ? newPos : total;
      // 只在非末尾时对齐到雪碧图时间戳
      final alignedTarget = target < total
          ? videoshotData!.getClosestTimestamp(target)
          : target;
      setState(() {
        isSeekPreviewMode = true;
        previewPosition = alignedTarget;
      });
      _showSeekIndicator();
    } else {
      // 直接跳转模式（带暂停+加速+批量提交）
      if (SettingsService.seekPreviewMode && !hasShownVideoshotFailToast) {
        hasShownVideoshotFailToast = true;
        ToastUtils.show(context, '预览图加载失败，已切换到默认快进模式');
      }
      _batchSeek(forward: true);
    }
  }

  void seekBackward() {
    if (videoController == null) return;

    // 检查是否开启预览模式且有快照数据
    if (SettingsService.seekPreviewMode && videoshotData != null) {
      // 预览模式: 暂停视频，只更新预览位置
      videoController?.pause();
      final current = previewPosition ?? videoController!.value.position;
      final newPos = current - const Duration(seconds: 10);
      final target = newPos > Duration.zero ? newPos : Duration.zero;
      final alignedTarget = videoshotData!.getClosestTimestamp(target);
      setState(() {
        isSeekPreviewMode = true;
        previewPosition = alignedTarget;
      });
      _showSeekIndicator();
    } else {
      // 直接跳转模式（带暂停+加速+批量提交）
      if (SettingsService.seekPreviewMode && !hasShownVideoshotFailToast) {
        hasShownVideoshotFailToast = true;
        ToastUtils.show(context, '预览图加载失败，已切换到默认快进模式');
      }
      _batchSeek(forward: false);
    }
  }

  /// 批量快进/快退：暂停视频、累积目标位置、加速、松手后提交
  void _batchSeek({required bool forward}) {
    if (videoController == null) return;
    final total = videoController!.value.duration;

    // 首次快进：暂停视频，记录播放状态，确定起点
    if (seekRepeatCount == 0) {
      wasPlayingBeforeSeek = videoController!.value.isPlaying;
      if (wasPlayingBeforeSeek) {
        videoController!.pause();
      }

      // 使用上次提交的位置作为起点（如果在 2 秒内），避免 seekTo 延迟导致的回退
      final now = DateTime.now();
      if (lastCommittedSeekTarget != null &&
          lastSeekCommitTime != null &&
          now.difference(lastSeekCommitTime!).inMilliseconds < 2000) {
        pendingSeekTarget = lastCommittedSeekTarget;
      } else {
        pendingSeekTarget = videoController!.value.position;
      }
    }

    seekRepeatCount++;
    final step = _getSeekStep();
    final current = pendingSeekTarget!;

    if (forward) {
      final newPos = current + step;
      pendingSeekTarget = newPos < total ? newPos : total;
    } else {
      final newPos = current - step;
      pendingSeekTarget = newPos > Duration.zero ? newPos : Duration.zero;
    }

    // 更新 UI 指示器（复用 previewPosition 显示目标位置）
    setState(() {
      showSeekIndicator = true;
      previewPosition = pendingSeekTarget;
    });

    // 重置提交定时器（停止操作后 400ms 自动提交）
    // 时间较短以保证单次点击的响应速度，同时避免连续点击时频繁 seek
    seekCommitTimer?.cancel();
    seekCommitTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) commitSeek();
    });
  }

  /// 提交快进结果：seekTo + 恢复播放
  void commitSeek() {
    seekCommitTimer?.cancel();
    if (videoController == null || pendingSeekTarget == null) {
      seekRepeatCount = 0;
      pendingSeekTarget = null;
      return;
    }

    final target = pendingSeekTarget!;

    // 如果 seek 到非末尾位置，重置播放完成标志
    final duration = videoController!.value.duration;
    if (target.inMilliseconds < duration.inMilliseconds - 1000) {
      hasHandledVideoComplete = false;
    }

    // 记录提交的位置和时间，用于连续快进时避免回退
    lastCommittedSeekTarget = target;
    lastSeekCommitTime = DateTime.now();

    videoController!.seekTo(target);
    resetDanmakuIndex(target);
    resetSubtitleIndex(target);

    if (wasPlayingBeforeSeek) {
      videoController!.play();
    }

    // 清除预览位置，但保留指示器 2 秒
    // 短暂隐藏缓冲条，等待播放器更新到新位置的缓冲数据
    setState(() {
      previewPosition = null;
      hideBufferAfterSeek = true;
    });
    _showSeekIndicator(); // 提交后指示器再显示 2 秒，让用户看清跳转位置

    bufferHideTimer?.cancel();
    bufferHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => hideBufferAfterSeek = false);
      }
    });

    seekRepeatCount = 0;
    pendingSeekTarget = null;
    wasPlayingBeforeSeek = false;
  }

  /// 预览模式下继续快进/快退
  void seekPreviewForward() {
    if (videoController == null || previewPosition == null) return;
    if (hasHandledVideoComplete) return;
    final total = videoController!.value.duration;

    // 基于当前预览位置增加
    final nextPos = previewPosition! + const Duration(seconds: 10);
    var target = nextPos < total ? nextPos : total;

    // 时间吸附
    if (videoshotData != null) {
      // 如果有时间戳，确保每次切换到下一个关键帧
      // 这里简单地对新位置进行吸附
      target = videoshotData!.getClosestTimestamp(target);

      // 如果吸附后时间没变（因为间隔大），强制移动到下一帧
      if (target <= previewPosition! && target < total) {
        target =
            previewPosition! + const Duration(seconds: 1); // 增加一点再吸附，尝试找到下一帧
        target = videoshotData!.getClosestTimestamp(target);
      }
    }

    setState(() {
      previewPosition = target;
    });
    _showSeekIndicator();
  }

  void seekPreviewBackward() {
    if (videoController == null || previewPosition == null) return;

    final nextPos = previewPosition! - const Duration(seconds: 10);
    var target = nextPos > Duration.zero ? nextPos : Duration.zero;

    // 时间吸附
    if (videoshotData != null) {
      target = videoshotData!.getClosestTimestamp(target);

      // 如果吸附后时间没变，强制移动到上一帧
      if (target >= previewPosition! && target > Duration.zero) {
        target = previewPosition! - const Duration(seconds: 1);
        target = videoshotData!.getClosestTimestamp(target);
      }
    }

    setState(() {
      previewPosition = target;
    });
    _showSeekIndicator();
  }

  /// 确认预览跳转
  void confirmPreviewSeek() {
    if (previewPosition != null && videoController != null) {
      videoController!.seekTo(previewPosition!);
      videoController!.play(); // 确认后恢复播放
      resetDanmakuIndex(previewPosition!);
      resetSubtitleIndex(previewPosition!);
    }
    _endPreviewMode();
  }

  /// 取消预览跳转
  void cancelPreviewSeek() {
    // 取消预览，恢复播放 (根据用户习惯，通常取消预览意味着继续观看)
    if (videoController != null && !videoController!.value.isPlaying) {
      videoController!.play();
    }
    _endPreviewMode();
  }

  void _endPreviewMode() {
    setState(() {
      isSeekPreviewMode = false;
      previewPosition = null;
      showSeekIndicator = false;
    });
    seekIndicatorTimer?.cancel();
  }

  void _showSeekIndicator() {
    seekIndicatorTimer?.cancel();
    setState(() => showSeekIndicator = true);
    // 预览模式下不自动隐藏
    if (!isSeekPreviewMode) {
      seekIndicatorTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => showSeekIndicator = false);
        }
      });
    }
  }

  /// 加载视频快照(雪碧图)数据
  Future<void> loadVideoshot({
    bool preloadAllSprites = true,
    bool precacheFirstSprite = true,
  }) async {
    try {
      final data = await BilibiliApi.getVideoshot(
        bvid: widget.video.bvid,
        cid: cid,
        preloadAllImages: preloadAllSprites,
      );
      if (mounted && data != null) {
        setState(() => videoshotData = data);
        precachedSpriteIndex = -1;
        if (precacheFirstSprite) {
          // 预缓存第一张雪碧图到 GPU
          _precacheNextSprite(0);
        }
      }
    } catch (e) {
      debugPrint('Failed to load videoshot: $e');
    }
  }

  /// 预缓存指定索引的雪碧图 (滑动窗口: 只保留当前 + 下一张)
  void _precacheNextSprite(int index) {
    if (videoshotData == null || index >= videoshotData!.images.length) return;
    if (index <= precachedSpriteIndex) return; // 已缓存

    // 清理更早的雪碧图 (保留 index-1 和 index)
    if (index > 1) {
      VideoshotApi.evictSprite(videoshotData!.images[index - 2]);
    }

    // 预缓存新的雪碧图
    VideoshotApi.precacheSprite(context, videoshotData!.images[index]);
    precachedSpriteIndex = index;
  }

  /// 检查是否需要预加载下一张雪碧图 (播放过程中调用)
  void _checkSpritePreload(Duration position) {
    if (videoshotData == null) return;

    final l = videoshotData!.framesPerImage;
    final frame = videoshotData!.getIndex(position);
    final spriteIdx = frame ~/ l;

    final threshold = SettingsService.videoshotPreloadThreshold;
    if (frame % l > l * threshold &&
        spriteIdx + 1 < videoshotData!.images.length) {
      _precacheNextSprite(spriteIdx + 1);
    }
  }

  /// 清理所有雪碧图的内存缓存
  void _clearSpritesFromMemory() {
    if (videoshotData == null) return;
    for (final url in videoshotData!.images) {
      VideoshotApi.evictSprite(url);
    }
    videoshotData = null;
    precachedSpriteIndex = -1;
  }

  // ========== 进度条拖动控制 (Feature 4) ==========

  void enterProgressBarMode() {
    if (videoController == null) return;
    setState(() {
      isProgressBarFocused = true;
      previewPosition = null; // 初始无预览，显示当前位置
    });
    hideTimer?.cancel();
  }

  void exitProgressBarMode({bool commit = false}) {
    if (commit && previewPosition != null && videoController != null) {
      // 如果 seek 到非末尾位置，重置播放完成标志
      final duration = videoController!.value.duration;
      if (previewPosition!.inMilliseconds < duration.inMilliseconds - 1000) {
        hasHandledVideoComplete = false;
      }
      videoController!.seekTo(previewPosition!);
      resetDanmakuIndex(previewPosition!);
      resetSubtitleIndex(previewPosition!);
    }
    setState(() {
      isProgressBarFocused = false;
      previewPosition = null;
    });
    startHideTimer();
  }

  /// 开始调整进度 - 设置初始预览位置
  void startAdjustProgress(int seconds) {
    if (videoController == null) return;
    final isPreviewMode =
        SettingsService.seekPreviewMode && videoshotData != null;

    // 首次调整时暂停视频（预览模式）或记录当前位置
    if (previewPosition == null) {
      if (isPreviewMode) {
        videoController!.pause();
      }
      previewPosition = videoController!.value.position;
    }

    adjustProgress(seconds);
  }

  /// 结束调整进度 - 跳转到预览位置
  void commitProgress() {
    if (previewPosition != null && videoController != null) {
      videoController!.seekTo(previewPosition!);
      resetDanmakuIndex(previewPosition!);
      resetSubtitleIndex(previewPosition!);
      setState(() => previewPosition = null);
    }
  }

  void adjustProgress(int seconds) {
    if (videoController == null || previewPosition == null) return;
    final total = videoController!.value.duration;
    final newPos = previewPosition! + Duration(seconds: seconds);

    Duration target;
    if (newPos < Duration.zero) {
      target = Duration.zero;
    } else if (newPos > total) {
      target = total;
    } else {
      target = newPos;
    }

    // 如果有雪碧图且不是末尾，对齐到最近的帧时间戳
    if (videoshotData != null && target < total) {
      target = videoshotData!.getClosestTimestamp(target);
    }

    setState(() {
      previewPosition = target;
    });
  }

  void toggleDanmaku() async {
    setState(() {
      danmakuEnabled = !danmakuEnabled;
    });
    if (!danmakuEnabled) {
      NativePlayerDanmakuService.clear(videoController);
      danmakuController?.clear();
    } else {
      if (useNativeDanmakuRender) {
        danmakuController?.clear();
      }
      _applyDanmakuOptionWithRetry();
    }
    ToastUtils.dismiss();
    ToastUtils.show(context, danmakuEnabled ? '弹幕已开启' : '弹幕已关闭');
    toggleControls();
  }

  void updateDanmakuOption() {
    final option = _buildDanmakuOption();
    danmakuController?.updateOption(option);
    if (!useNativeDanmakuRender) {
      danmakuOptionApplyTimer?.cancel();
      danmakuOptionApplyTimer = null;
      NativePlayerDanmakuService.clear(videoController);
      return;
    }
    _applyDanmakuOptionWithRetry(option: option);
  }

  DanmakuOption _buildDanmakuOption() {
    return DanmakuOption(
      opacity: danmakuOpacity,
      fontSize: danmakuFontSize,
      // 弹幕飞行速度随播放倍速同步调整
      duration: danmakuSpeed / playbackSpeed,
      area: danmakuArea,
      hideTop: hideTopDanmaku,
      hideBottom: hideBottomDanmaku,
    );
  }

  void _applyDanmakuOptionWithRetry({DanmakuOption? option}) {
    if (!useNativeDanmakuRender) return;
    final currentOption = option ?? _buildDanmakuOption();
    NativePlayerDanmakuService.updateOption(
      videoController,
      currentOption,
      nativeStrokeWidth: SettingsService.nativeDanmakuStrokeWidth,
      nativeStrokeAlphaMin: SettingsService.nativeDanmakuStrokeAlphaMin,
    );
    danmakuOptionApplyTimer?.cancel();
    int retries = 0;
    danmakuOptionApplyTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (timer) {
        NativePlayerDanmakuService.updateOption(
          videoController,
          currentOption,
          nativeStrokeWidth: SettingsService.nativeDanmakuStrokeWidth,
          nativeStrokeAlphaMin: SettingsService.nativeDanmakuStrokeAlphaMin,
        );
        retries++;
        if (retries >= 10 || !mounted || videoController == null) {
          timer.cancel();
          if (identical(danmakuOptionApplyTimer, timer)) {
            danmakuOptionApplyTimer = null;
          }
        }
      },
    );
  }

  void toggleStatsForNerds() async {
    setState(() {
      showStatsForNerds = !showStatsForNerds;
      if (showStatsForNerds) {
        videoSpeedKbps = 0;
        networkActivityKb = 0;
        // 重置基线：设为 null 让下一个 tick 只初始化基线、不计算，
        // 避免 lastStatsBuffered 还是 Duration.zero 导致首次采样产生巨大尖峰。
        lastStatsTime = null;
      }
    });
    if (showStatsForNerds) {
      _startStatsTimer();
    } else {
      statsTimer?.cancel();
      statsTimer = null;
    }
    ToastUtils.dismiss();
    ToastUtils.show(context, showStatsForNerds ? '视频数据实时监测已开启' : '视频数据实时监测已关闭');
  }

  void toggleLoopMode() async {
    setState(() {
      isLoopMode = !isLoopMode;
      videoController?.setLooping(isLoopMode);
    });
    ToastUtils.dismiss();
    ToastUtils.show(context, isLoopMode ? '循环播放已开启' : '循环播放已关闭');
  }

  void _startStatsTimer() {
    statsTimer?.cancel();
    if (!showStatsForNerds) return;
    lastStatsBuffered = Duration.zero;
    lastStatsTime = null;
    statsTimer = Timer.periodic(SettingsService.statsInterval, (_) {
      _updateStatsForNerds();
    });
  }

  void _updateStatsForNerds() {
    if (!mounted || videoController == null || !showStatsForNerds) return;
    final value = videoController!.value;
    if (value.duration <= Duration.zero) return;

    final buffered = value.buffered.isNotEmpty
        ? value.buffered.last.end
        : Duration.zero;
    final now = DateTime.now();
    final prevTime = lastStatsTime;

    if (prevTime != null) {
      final dt = now.difference(prevTime).inMilliseconds / 1000.0;
      if (dt > 0.05) {
        final bufferedDeltaSec =
            (buffered - lastStatsBuffered).inMilliseconds / 1000.0;
        final safeDelta = bufferedDeltaSec < 0 ? 0.0 : bufferedDeltaSec;

        // 视频速度: buffer增量 × 码率
        final instantSpeed = safeDelta * videoDataRateKbps / dt;
        // 网络活动: 本采样周期内收到的 KB
        final instantNetworkKb = safeDelta * videoDataRateKbps / 8.0;

        setState(() {
          videoSpeedKbps = instantSpeed;
          networkActivityKb = instantNetworkKb;
        });
      }
    }
    lastStatsBuffered = buffered;
    lastStatsTime = now;
  }

  void adjustDanmakuSetting(int direction) {
    setState(() {
      switch (focusedSettingIndex) {
        case 0:
          danmakuEnabled = !danmakuEnabled;
          break;
        case 1:
          danmakuOpacity = (danmakuOpacity + 0.1 * direction).clamp(0.1, 1.0);
          break;
        case 2:
          danmakuFontSize = (danmakuFontSize + 2.0 * direction).clamp(
            10.0,
            50.0,
          );
          break;
        case 3:
          final areas = [0.125, 0.25, 0.5, 0.75, 1.0];
          int currentIndex = areas.indexWhere(
            (v) => (danmakuArea - v).abs() < 0.001,
          );
          if (currentIndex < 0) {
            final normalized = areas.firstWhere(
              (v) => danmakuArea <= v + 0.001,
              orElse: () => areas.last,
            );
            currentIndex = areas.indexOf(normalized);
          }
          int newIndex = (currentIndex + direction).clamp(0, areas.length - 1);
          danmakuArea = areas[newIndex];
          break;
        case 4:
          danmakuSpeed = (danmakuSpeed + 1.0 * direction).clamp(4.0, 20.0);
          break;
        case 5:
          hideTopDanmaku = !hideTopDanmaku;
          break;
        case 6:
          hideBottomDanmaku = !hideBottomDanmaku;
          break;
      }
      updateDanmakuOption();
      saveSettings();
    });
  }

  void adjustSubtitleSetting(int direction) {
    if (focusedSettingIndex == 0) {
      setState(() {
        subtitleEnabled = !subtitleEnabled;
        if (!subtitleEnabled) {
          currentSubtitleText = '';
        }
      });
      _persistSubtitleEnabled();
      if (subtitleEnabled &&
          subtitleTracks.isNotEmpty &&
          selectedSubtitleTrackIndex >= 0 &&
          subtitleItems.isEmpty) {
        final requestCid = cid;
        if (requestCid != null) {
          final requestSeq = ++subtitleRequestSeq;
          _loadSubtitleTrack(
            index: selectedSubtitleTrackIndex,
            requestSeq: requestSeq,
            requestBvid: widget.video.bvid,
            requestCid: requestCid,
          );
        }
      }
      ToastUtils.dismiss();
      ToastUtils.show(context, subtitleEnabled ? '字幕已开启' : '字幕已关闭');
      return;
    }

    if (subtitleTracks.isEmpty) {
      ToastUtils.dismiss();
      ToastUtils.show(
        context,
        subtitleNeedLogin ? '该视频字幕需登录后可用' : '当前视频无字幕',
      );
      return;
    }

    final targetIndex = (focusedSettingIndex - 1).clamp(0, subtitleTracks.length - 1);
    if (targetIndex == selectedSubtitleTrackIndex && subtitleItems.isNotEmpty) {
      return;
    }
    final requestCid = cid;
    if (requestCid != null) {
      final requestSeq = ++subtitleRequestSeq;
      setState(() {
        subtitleItems = [];
        currentSubtitleText = '';
        lastSubtitleIndex = 0;
        subtitleOwnerBvid = null;
        subtitleOwnerCid = null;
      });
      _loadSubtitleTrack(
        index: targetIndex,
        requestSeq: requestSeq,
        requestBvid: widget.video.bvid,
        requestCid: requestCid,
      );
    }
    if (!subtitleEnabled) {
      setState(() => subtitleEnabled = true);
      _persistSubtitleEnabled();
    }
    final label = subtitleTracks[targetIndex].label.isNotEmpty
        ? subtitleTracks[targetIndex].label
        : subtitleTracks[targetIndex].lang;
    ToastUtils.dismiss();
    ToastUtils.show(context, '已切换字幕: $label');
  }

  /// 切换选集。对于合集 (ugc_season)，传入目标 episode 的 Map；
  /// 对于普通分P，传入 cid。
  Future<void> switchEpisode(int newCid, {String? targetBvid}) async {
    // 合集切换：目标 bvid 与当前不同，需要导航到新播放器
    if (targetBvid != null && targetBvid != widget.video.bvid) {
      // 找到目标 episode 的信息
      final idx = episodes.indexWhere((e) => e['bvid'] == targetBvid);
      if (idx >= 0 && mounted) {
        final targetEp = episodes[idx];
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              video: models.Video(
                bvid: targetEp['bvid'] ?? '',
                title: targetEp['title'] ?? '',
                pic: targetEp['pic'] ?? '',
                ownerName: widget.video.ownerName,
                ownerFace: widget.video.ownerFace,
                duration: targetEp['duration'] ?? 0,
                pubdate: widget.video.pubdate,
                view: 0,
              ),
            ),
          ),
        );
      }
      return;
    }

    if (newCid == cid) return;

    setState(() {
      subtitleRequestSeq++;
      cid = newCid;
      isLoading = true;
      errorMessage = null;
      showEpisodePanel = false;
      lastDanmakuIndex = 0;
      danmakuList = [];
      hasHandledVideoComplete = false; // 重置播放完成标志，确保下一集播完后能继续触发自动播放
      subtitleTracks = [];
      subtitleItems = [];
      selectedSubtitleTrackIndex = -1;
      currentSubtitleText = '';
      lastSubtitleIndex = 0;
      subtitleNeedLogin = false;
      subtitleOwnerBvid = null;
      subtitleOwnerCid = null;
    });

    // 清理旧播放器
    cancelPlayerListeners();
    await videoController?.dispose();
    videoController = null;
    videoController = null;
    LocalServer.instance.clearMpdContent();

    try {
      final playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: widget.video.bvid,
        cid: cid!,
        qn: currentQuality,
      );

      if (playInfo != null) {
        if (!mounted) return;
        currentQuality = playInfo['currentQuality'] ?? SettingsService.preferredQualityQn;
        currentCodec = playInfo['codec'] ?? currentCodec;
        currentAudioUrl = playInfo['audioUrl'];
        videoWidth = int.tryParse(playInfo['width']?.toString() ?? '') ?? 0;
        videoHeight = int.tryParse(playInfo['height']?.toString() ?? '') ?? 0;
        videoFrameRate =
            double.tryParse(playInfo['frameRate']?.toString() ?? '') ?? 0.0;
        videoDataRateKbps =
            ((int.tryParse(playInfo['videoBandwidth']?.toString() ?? '') ?? 0) /
                    1000)
                .round();
        qualities = List<Map<String, dynamic>>.from(
          playInfo['qualities'] ?? [],
        );

        String? playUrl;

        if (playInfo['dashData'] != null) {
          final mpdContent = await MpdGenerator.generate(
            playInfo['dashData'],
            selectedQn: currentQuality,
            selectedCodec: _codecPrefixForMpd(currentCodec),
          );

          LocalServer.instance.setMpdContent(mpdContent);
          playUrl = LocalServer.instance.mpdUrl;
        } else {
          playUrl = playInfo['url'];
        }

        if (playUrl == null || playUrl.isEmpty) {
          throw Exception('当前清晰度暂无可播放地址，请尝试其他清晰度');
        }

        // 创建新播放器
        videoController = VideoPlayerController.networkUrl(
          Uri.parse(playUrl),
          viewType: VideoViewType.platformView,
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
            'Referer': 'https://www.bilibili.com/',
            'Origin': 'https://www.bilibili.com',
            if (AuthService.sessdata != null)
              'Cookie': 'SESSDATA=${AuthService.sessdata}',
          },
        );

        await videoController!.initialize();

        _setupPlayerListeners();
        _startStatsTimer();
        await videoController!.play();

        setState(() => isLoading = false);

        startHideTimer();
        await loadDanmaku();
        await loadSubtitles();

        // 🔥 重新加载当前 P 的雪碧图数据
        _clearSpritesFromMemory();
        loadVideoshot();

        final idx = episodes.indexWhere((e) => e['cid'] == cid);
        if (idx != -1) setState(() => focusedEpisodeIndex = idx);

        // 恢复倍速，并同步弹幕速度（含原生弹幕渲染）
        videoController?.setPlaybackSpeed(playbackSpeed);
        updateDanmakuOption();

        // 切换分P后重新计算下一集，确保自动播放指向正确的下一P
        if (fullVideoInfo != null) {
          _precomputeNextEpisode(fullVideoInfo!);
        }
      } else {
        throw Exception('获取播放地址失败');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = '切换失败: $e';
          isLoading = false;
        });
      }
    }
  }

  void selectPlaybackSpeedByIndex(int index) {
    if (index < 0 || index >= availableSpeeds.length) return;
    final speed = availableSpeeds[index];
    setState(() {
      settingsMenuType = SettingsMenuType.speed;
      focusedSettingIndex = index;
      playbackSpeed = speed;
    });
    videoController?.setPlaybackSpeed(speed);
    // 倍速变化后同步弹幕飞行时长（含原生弹幕渲染）
    updateDanmakuOption();
    _persistPlaybackSpeed();
    unawaited(_syncTunnelModeWithPlaybackSpeed(speed));
    ToastUtils.dismiss();
    ToastUtils.show(context, '倍速已设置为 ${speed}x');
  }

  void activateSetting() {
    if (settingsMenuType == SettingsMenuType.main) {
      switch (focusedSettingIndex) {
        case 0:
          showQualityPicker();
          break;
        case 1:
          setState(() {
            settingsMenuType = SettingsMenuType.danmaku;
            focusedSettingIndex = 0;
          });
          break;
        case 2:
          setState(() {
            settingsMenuType = SettingsMenuType.subtitle;
            focusedSettingIndex = 0;
          });
          break;
        case 3:
          setState(() {
            settingsMenuType = SettingsMenuType.speed;
            focusedSettingIndex = 0;
          });
          break;
      }
    } else if (settingsMenuType == SettingsMenuType.danmaku) {
      if (focusedSettingIndex == 0 ||
          focusedSettingIndex == 5 ||
          focusedSettingIndex == 6) {
        adjustDanmakuSetting(1);
      }
    } else if (settingsMenuType == SettingsMenuType.subtitle) {
      adjustSubtitleSetting(1);
    } else if (settingsMenuType == SettingsMenuType.speed) {
      selectPlaybackSpeedByIndex(focusedSettingIndex);
    }
  }

  Future<void> switchQuality(int qn) async {
    final position = videoController?.value.position ?? Duration.zero;
    final previousQuality = currentQuality;

    try {
      final playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: widget.video.bvid,
        cid: cid!,
        qn: qn,
      );

      if (playInfo == null) {
        ToastUtils.show(context, '切换画质失败');
        return;
      }

      final returnedQuality = playInfo['currentQuality'] as int? ?? qn;

      // 升级请求但不可用（含杜比视界无权限、API 降级等）→ 统一拒绝
      final bool dvUnavailable = qn == 126 &&
          playInfo['dvRequested'] == true &&
          playInfo['dvAvailable'] != true;
      if (dvUnavailable ||
          (qn > previousQuality && returnedQuality <= previousQuality)) {
        final requested = VideoQuality.fromQn(qn).label;
        ToastUtils.show(context, '$requested 不可用，保持当前画质');
        setState(() => isLoading = false);
        return;
      }

      // 有提升但未达到请求画质，先提示再切换
      if (returnedQuality < qn && mounted) {
        final requested = VideoQuality.fromQn(qn).label;
        final actual = VideoQuality.fromQn(returnedQuality).label;
        ToastUtils.show(context, '未达到 $requested，将以 $actual 播放');
      }

      // 确认要切换，此时才进入 loading 状态
      setState(() => isLoading = true);

      // 清理旧播放器
      cancelPlayerListeners();
      await videoController?.dispose();
      videoController = null;
      LocalServer.instance.clearMpdContent();

      // 等待底层 MediaCodec 完全释放，避免硬件解码器资源竞争
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      currentQuality = returnedQuality;
      currentCodec = playInfo['codec'] ?? currentCodec;
      currentAudioUrl = playInfo['audioUrl'];
      videoWidth = int.tryParse(playInfo['width']?.toString() ?? '') ?? 0;
      videoHeight = int.tryParse(playInfo['height']?.toString() ?? '') ?? 0;
      videoFrameRate =
          double.tryParse(playInfo['frameRate']?.toString() ?? '') ?? 0.0;
      videoDataRateKbps =
          ((int.tryParse(playInfo['videoBandwidth']?.toString() ?? '') ?? 0) /
                  1000)
              .round();

      SettingsService.setPreferredQuality(VideoQuality.fromQn(currentQuality));

      String? playUrl;

      if (playInfo['dashData'] != null) {
        final mpdContent = await MpdGenerator.generate(
          playInfo['dashData'],
          selectedQn: currentQuality,
          selectedCodec: _codecPrefixForMpd(currentCodec),
        );

        LocalServer.instance.setMpdContent(mpdContent);
        playUrl = LocalServer.instance.mpdUrl;
      } else {
        playUrl = playInfo['url'];
      }

      if (playUrl == null || playUrl.isEmpty) {
        ToastUtils.show(context, '当前清晰度暂无可播放地址，请切换清晰度');
        setState(() => isLoading = false);
        return;
      }

      // 创建新播放器
      videoController = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        viewType: VideoViewType.platformView,
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
          if (AuthService.sessdata != null)
            'Cookie': 'SESSDATA=${AuthService.sessdata}',
        },
      );

      await videoController!.initialize();
      await videoController!.seekTo(position);
      resetDanmakuIndex(position);
      resetSubtitleIndex(position);

      _setupPlayerListeners();
      _startStatsTimer();
      await videoController!.play();

      // 恢复倍速，并同步弹幕速度（含原生弹幕渲染）
      videoController?.setPlaybackSpeed(playbackSpeed);
      updateDanmakuOption();

      setState(() => isLoading = false);

      if (currentQuality >= qn) {
        ToastUtils.show(context, '已切换到 $currentQualityDesc');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.show(context, '切换画质失败，请重试');
        setState(() => isLoading = false);
      }
    }
  }

  /// 从完整 codec 字符串提取用于 MPD 过滤的前缀。
  /// DV 必须过滤以确保 ExoPlayer 使用 video/dolby-vision 解码器；
  /// 非 DV 编码不需要过滤（同 qn 下不同编码不会导致解码器选错）。
  static String? _codecPrefixForMpd(String codec) {
    if (codec.startsWith('dvhe')) return 'dvhe';
    if (codec.startsWith('dvh1')) return 'dvh1';
    if (codec.startsWith('dvav')) return 'dvav';
    return null;
  }

  void showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      builder: (context) {
        return QualityPickerSheet(
          qualities: qualities,
          currentQuality: currentQuality,
          onSelect: (qn) {
            Navigator.pop(context);
            if (qn != currentQuality) {
              switchQuality(qn);
            }
          },
        );
      },
    );
  }
}
