import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/video.dart' as models;
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/mpd_generator.dart';
import '../../../services/local_server.dart';
import '../../../services/api/videoshot_api.dart';
import '../../../config/build_flags.dart';
import '../widgets/settings_panel.dart';
import '../player_screen.dart';
import '../widgets/quality_picker_sheet.dart';
import 'player_state_mixin.dart';
import '../../../core/plugin/plugin_manager.dart';
import '../../../core/plugin/plugin_types.dart';
import '../../../services/playback_progress_cache.dart';

/// 播放器逻辑 Mixin
mixin PlayerActionMixin on PlayerStateMixin {
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
      // 根据设置决定是否显示控制栏
      showControls = !SettingsService.hideControlsOnStart;
      updateDanmakuOption();
    });
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('danmaku_enabled', danmakuEnabled);
    await prefs.setDouble('danmaku_opacity', danmakuOpacity);
    await prefs.setDouble('danmaku_font_size', danmakuFontSize);
    await prefs.setDouble('danmaku_area', danmakuArea);
    await prefs.setDouble('danmaku_speed', danmakuSpeed);
    await prefs.setBool('hide_top_danmaku', hideTopDanmaku);
    await prefs.setBool('hide_bottom_danmaku', hideBottomDanmaku);
  }

  Future<void> initializePlayer() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      hasHandledVideoComplete = false; // 重置播放完成标志
    });

    try {
      final videoInfo = await BilibiliApi.getVideoInfo(widget.video.bvid);

      // 🔥 预先获取本地缓存（在 setState 外部执行 async 操作）
      final cachedRecord = await PlaybackProgressCache.getCachedRecord(
        widget.video.bvid,
      );

      if (videoInfo != null) {
        if (mounted) {
          setState(() {
            fullVideoInfo = videoInfo; // 保存完整视频信息
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
            aid = videoInfo['aid']; // 保存 aid 用于操作 API
          });
          if (cid == null && episodes.isNotEmpty) {
            cid = episodes[0]['cid'];
          }

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

      // 立即启动快照数据预加载 (并行执行)
      loadVideoshot();

      // Initialize focus index based on cid
      if (episodes.isNotEmpty) {
        final idx = episodes.indexWhere((e) => e['cid'] == cid);
        if (idx != -1) focusedEpisodeIndex = idx;
      }

      // 异步加载相关视频 (用于自动连播)
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
      final baseQn = currentQuality > 0 ? currentQuality : 80;
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
              final supportedQns = qualities.map((e) => e['qn'] as int).toList();
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
            lastError = '解析播放地址失败(codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn)';
            continue qualityLoop;
          }

          // 检查是否返回了错误信息
          if (playInfo['error'] != null) {
            lastError = '${playInfo['error']} (codec=${tryCodec?.name ?? 'auto'}, qn=$tryQn)';
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
              ((int.tryParse(playInfo['videoBandwidth']?.toString() ?? '') ?? 0) /
                      1000)
                  .round();

          String? playUrl;

          // 如果有 DASH 数据，生成 MPD 并使用全局服务器
          if (playInfo['dashData'] != null) {
            final mpdContent = await MpdGenerator.generate(playInfo['dashData']);

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
          _startStatsTimer();

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
              Fluttertoast.showToast(
                msg:
                    '从${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}继续播放',
                toastLength: Toast.LENGTH_SHORT,
              );
            }
          }

          await videoController!.play();
          startHideTimer();

          await loadDanmaku();
          return; // 成功，退出
        } // qualityLoop 结束
      } // codecLoop 结束

      // ── 最终兜底：用非 DASH(durl/mp4/flv) 再试一次 ──
      debugPrint('🎬 [CompatFallback] All DASH codecs failed, trying durl compat...');
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
            ((int.tryParse(compatInfo['videoBandwidth']?.toString() ?? '') ?? 0) /
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
          _startStatsTimer();

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
          startHideTimer();
          await loadDanmaku();
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
        danmakuList.sort(
          (a, b) => (a['time'] as double).compareTo(b['time'] as double),
        );
        lastDanmakuIndex = 0;
      });
    } catch (e) {
      debugPrint('Failed to load danmaku: $e');
    }
  }

  /// 设置播放器监听器
  void _setupPlayerListeners() {
    if (videoController == null) return;

    videoController!.addListener(_onPlayerStateChange);
  }

  void _onPlayerStateChange() {
    if (videoController == null || !mounted) return;

    final value = videoController!.value;

    // 同步弹幕
    if (danmakuEnabled && danmakuController != null) {
      syncDanmaku(value.position.inSeconds.toDouble());
    }

    // 检查是否需要预加载下一张雪碧图
    _checkSpritePreload(value.position);

    // 检查播放完成
    if (value.position >= value.duration &&
        value.duration > Duration.zero &&
        !value.isPlaying) {
      // 通过位置判断播放结束
      onVideoComplete();
    }

    // 触发重绘以更新 UI (进度条等)
    setState(() {});

    if (BuildFlags.pluginsEnabled) {
      // 插件处理 (Debounce logic internal to plugin, but we update UI here)
      _handlePlugins(value.position);
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
        videoController?.seekTo(Duration(milliseconds: action.positionMs));
        resetDanmakuIndex(Duration(milliseconds: action.positionMs));
        Fluttertoast.showToast(msg: action.reason);
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
  }

  Future<void> disposePlayer() async {
    // 退出前上报进度并保存到本地缓存
    await reportPlaybackProgress();

    // 🔥 保存进度到本地缓存（解决 B站 API history 字段不可靠的问题）
    if (cid != null && videoController != null) {
      final currentPos = videoController!.value.position.inSeconds;
      if (currentPos > 5) {
        // 只有播放超过 5 秒才缓存
        await PlaybackProgressCache.saveProgress(
          widget.video.bvid,
          cid!,
          currentPos,
        );
        debugPrint(
          '🎬 [Cache] Saved progress: bvid=${widget.video.bvid}, cid=$cid, pos=$currentPos',
        );
      }
    }

    cancelPlayerListeners();
    seekIndicatorTimer?.cancel();
    onlineCountTimer?.cancel(); // 取消在线人数定时器
    statsTimer?.cancel();
    _clearSpritesFromMemory(); // 清理雪碧图内存缓存

    if (BuildFlags.pluginsEnabled) {
      // 通知插件视频结束
      final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
      for (var plugin in plugins) {
        plugin.onVideoEnd();
      }
    }

    await videoController?.dispose();
    videoController = null;
    LocalServer.instance.clearMpdContent();
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

  /// 获取用于显示的视频信息（优先使用 API 获取的完整信息）
  models.Video getDisplayVideo() {
    if (fullVideoInfo == null) {
      return widget.video;
    }

    final info = fullVideoInfo!;
    final owner = info['owner'] ?? {};
    final stat = info['stat'] ?? {};

    var displayTitle = info['title'] ?? widget.video.title;

    // 多P视频，在标题后追加分P名称
    if (episodes.length > 1 && cid != null) {
      final currentEp = episodes.firstWhere(
        (e) => e['cid'] == cid,
        orElse: () => {},
      );
      if (currentEp.isNotEmpty) {
        final partName = currentEp['part'] ?? currentEp['title'] ?? '';
        final pageIndex = currentEp['page'] ?? episodes.indexOf(currentEp) + 1;
        if (partName.isNotEmpty) {
          displayTitle = '$displayTitle - P$pageIndex $partName';
        }
      }
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

  /// 视频播放完成回调
  void onVideoComplete() {
    // 防止重复触发
    if (hasHandledVideoComplete) return;
    hasHandledVideoComplete = true;

    hideTimer?.cancel();
    setState(() => showControls = true);

    // 检查是否开启自动连播
    if (!SettingsService.autoPlay) return;

    // 暂停当前视频
    if (videoController != null && videoController!.value.isPlaying) {
      videoController!.pause();
    }

    // 1. 检查是否有下一集
    if (episodes.length > 1 && cid != null) {
      final currentIndex = episodes.indexWhere((ep) => ep['cid'] == cid);
      if (currentIndex >= 0 && currentIndex < episodes.length - 1) {
        // 有下一集，自动播放
        final nextEp = episodes[currentIndex + 1];
        final nextCid = nextEp['cid'] as int;
        Fluttertoast.showToast(
          msg:
              '自动播放下一集: ${nextEp['title'] ?? nextEp['part'] ?? 'P${currentIndex + 2}'}',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.TOP,
        );
        switchEpisode(nextCid);
        return;
      }
    }

    // 2. 所有集数播完，检查相关视频
    if (relatedVideos.isNotEmpty) {
      final nextVideo = relatedVideos.first;
      Fluttertoast.showToast(
        msg: '自动播放推荐视频',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
      );
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

    // 🔥 3. 无论是否有后续动作，都强制上报一次"已看完"
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
    if (danmakuController == null || !danmakuEnabled) return;

    if (lastDanmakuIndex < danmakuList.length) {
      final nextDmTime = danmakuList[lastDanmakuIndex]['time'] as double;
      // 检测跳转 (Seek)
      if (currentTime - nextDmTime > 5.0) {
        resetDanmakuIndex(Duration(seconds: currentTime.toInt()));
        return;
      }
    }

    final plugins = BuildFlags.pluginsEnabled
        ? PluginManager().getEnabledPlugins<DanmakuPlugin>()
        : const <DanmakuPlugin>[];

    while (lastDanmakuIndex < danmakuList.length) {
      final dm = danmakuList[lastDanmakuIndex];
      final time = dm['time'] as double;

      if (time <= currentTime) {
        if (currentTime - time < 1.0) {
          // 构造插件传递对象 (目前简单用 Map 传递)
          // 真实项目中建议定义 DanmakuItem 模型
          Map<String, dynamic>? dmItem = {
            'content': dm['content'],
            'color': dm['color'],
          };

          DanmakuStyle? style;

          // 插件过滤管道
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
              // 高亮样式暂时用颜色替代，或如果库支持边框则设置
              // 这里简单将文字变色，并加粗（如果库支持）
              color = style.borderColor!;
            }

            danmakuController!.addDanmaku(
              DanmakuContentItem(dmItem['content'] as String, color: color),
            );
          }
        }
        lastDanmakuIndex++;
      } else {
        break;
      }
    }
  }

  void resetDanmakuIndex(Duration position) {
    if (danmakuList.isEmpty) return;
    final seconds = position.inSeconds.toDouble();
    int index = danmakuList.indexWhere(
      (dm) => (dm['time'] as double) >= seconds,
    );
    if (index == -1) {
      index = danmakuList.length;
    }
    lastDanmakuIndex = index;
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
      videoController!.pause();
      hideTimer?.cancel();
      // 暂停时上报进度
      reportPlaybackProgress();
      // 暂停时只显示暂停符号，不显示控制栏
    } else {
      videoController!.play();
      startHideTimer();
    }
    setState(() {});
  }

  void seekForward() {
    if (videoController == null) return;
    final current = videoController!.value.position;
    final total = videoController!.value.duration;
    final newPos = current + const Duration(seconds: 10);
    final target = newPos < total ? newPos : total;

    // 检查是否开启预览模式且有快照数据
    if (SettingsService.seekPreviewMode && videoshotData != null) {
      // 预览模式: 暂停视频，只更新预览位置
      videoController?.pause();

      // 时间吸附
      final alignedTarget = videoshotData!.getClosestTimestamp(target);

      setState(() {
        isSeekPreviewMode = true;
        previewPosition = alignedTarget;
      });
      _showSeekIndicator();
    } else {
      // 直接跳转模式 (默认)
      // 如果用户开启了预览模式但雪碧图加载失败，显示提示
      if (SettingsService.seekPreviewMode && !hasShownVideoshotFailToast) {
        hasShownVideoshotFailToast = true;
        Fluttertoast.showToast(
          msg: '预览图加载失败，已切换到默认快进模式',
          toastLength: Toast.LENGTH_SHORT,
        );
      }
      videoController!.seekTo(target);
      resetDanmakuIndex(target);
      _showSeekIndicator();
    }
  }

  void seekBackward() {
    if (videoController == null) return;
    final current = videoController!.value.position;
    final newPos = current - const Duration(seconds: 10);
    final target = newPos > Duration.zero ? newPos : Duration.zero;

    // 检查是否开启预览模式且有快照数据
    if (SettingsService.seekPreviewMode && videoshotData != null) {
      // 预览模式: 暂停视频，只更新预览位置
      videoController?.pause();

      // 时间吸附
      final alignedTarget = videoshotData!.getClosestTimestamp(target);

      setState(() {
        isSeekPreviewMode = true;
        previewPosition = alignedTarget;
      });
      _showSeekIndicator();
    } else {
      // 直接跳转模式 (默认)
      // 如果用户开启了预览模式但雪碧图加载失败，显示提示
      if (SettingsService.seekPreviewMode && !hasShownVideoshotFailToast) {
        hasShownVideoshotFailToast = true;
        Fluttertoast.showToast(
          msg: '预览图加载失败，已切换到默认快进模式',
          toastLength: Toast.LENGTH_SHORT,
        );
      }
      videoController!.seekTo(target);
      resetDanmakuIndex(target);
      _showSeekIndicator();
    }
  }

  /// 预览模式下继续快进/快退
  void seekPreviewForward() {
    if (videoController == null || previewPosition == null) return;
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
  Future<void> loadVideoshot() async {
    // 始终尝试加载数据，以便在用户启用设置时能够立即使用
    try {
      final data = await BilibiliApi.getVideoshot(
        bvid: widget.video.bvid,
        cid: cid,
      );
      if (mounted && data != null) {
        setState(() => videoshotData = data);
        precachedSpriteIndex = -1;
        // 预缓存第一张雪碧图到 GPU
        _precacheNextSprite(0);
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

    // 如果当前帧已超过该雪碧图的 80%，预加载下一张
    if (frame % l > l * 0.8 && spriteIdx + 1 < videoshotData!.images.length) {
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
      videoController!.seekTo(previewPosition!);
      resetDanmakuIndex(previewPosition!);
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
    previewPosition ??= videoController!.value.position;
    adjustProgress(seconds);
  }

  /// 结束调整进度 - 跳转到预览位置
  void commitProgress() {
    if (previewPosition != null && videoController != null) {
      videoController!.seekTo(previewPosition!);
      resetDanmakuIndex(previewPosition!);
      setState(() => previewPosition = null);
    }
  }

  void adjustProgress(int seconds) {
    if (videoController == null || previewPosition == null) return;
    final total = videoController!.value.duration;
    final newPos = previewPosition! + Duration(seconds: seconds);
    setState(() {
      if (newPos < Duration.zero) {
        previewPosition = Duration.zero;
      } else if (newPos > total) {
        previewPosition = total;
      } else {
        previewPosition = newPos;
      }
    });
  }

  void toggleDanmaku() {
    setState(() {
      danmakuEnabled = !danmakuEnabled;
    });
    Fluttertoast.showToast(msg: danmakuEnabled ? '弹幕已开启' : '弹幕已关闭');
    toggleControls();
  }

  void updateDanmakuOption() {
    danmakuController?.updateOption(
      DanmakuOption(
        opacity: danmakuOpacity,
        fontSize: danmakuFontSize,
        // 弹幕飞行速度随播放倍速同步调整
        duration: danmakuSpeed / playbackSpeed,
        area: danmakuArea,
        hideTop: hideTopDanmaku,
        hideBottom: hideBottomDanmaku,
      ),
    );
  }

  void toggleStatsForNerds() {
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
    Fluttertoast.showToast(
      msg: showStatsForNerds ? '视频数据实时监测已开启' : '视频数据实时监测已关闭',
    );
  }

  void _startStatsTimer() {
    statsTimer?.cancel();
    lastStatsBuffered = Duration.zero;
    lastStatsTime = null;
    statsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
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

  Future<void> switchEpisode(int newCid) async {
    if (newCid == cid) return;

    setState(() {
      cid = newCid;
      isLoading = true;
      errorMessage = null;
      showEpisodePanel = false;
      lastDanmakuIndex = 0;
      danmakuList = [];
      hasHandledVideoComplete = false; // 重置播放完成标志，确保下一集播完后能继续触发自动播放
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
        currentQuality = playInfo['currentQuality'] ?? 80;
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
          final mpdContent = await MpdGenerator.generate(playInfo['dashData']);

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

        // 🔥 重新加载当前 P 的雪碧图数据
        _clearSpritesFromMemory();
        loadVideoshot();

        final idx = episodes.indexWhere((e) => e['cid'] == cid);
        if (idx != -1) setState(() => focusedEpisodeIndex = idx);

        // 恢复倍速
        videoController?.setPlaybackSpeed(playbackSpeed);
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
    } else if (settingsMenuType == SettingsMenuType.speed) {
      final speed = availableSpeeds[focusedSettingIndex];
      setState(() => playbackSpeed = speed);
      videoController?.setPlaybackSpeed(speed);
      Fluttertoast.showToast(msg: '倍速已设置为 ${speed}x');
    }
  }

  Future<void> switchQuality(int qn) async {
    final position = videoController?.value.position ?? Duration.zero;

    setState(() => isLoading = true);

    try {
      final playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: widget.video.bvid,
        cid: cid!,
        qn: qn,
      );

      if (playInfo == null) {
        Fluttertoast.showToast(msg: '切换画质失败');
        setState(() => isLoading = false);
        return;
      }

      // 清理旧播放器
      cancelPlayerListeners();
      await videoController?.dispose();
      LocalServer.instance.clearMpdContent();

      currentQuality = playInfo['currentQuality'] ?? qn;
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

      String? playUrl;

      if (playInfo['dashData'] != null) {
        final mpdContent = await MpdGenerator.generate(playInfo['dashData']);

        LocalServer.instance.setMpdContent(mpdContent);
        playUrl = LocalServer.instance.mpdUrl;
      } else {
        playUrl = playInfo['url'];
      }

      if (playUrl == null || playUrl.isEmpty) {
        Fluttertoast.showToast(msg: '当前清晰度暂无可播放地址，请切换清晰度');
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

      _setupPlayerListeners();
      _startStatsTimer();
      await videoController!.play();

      // 恢复倍速
      videoController?.setPlaybackSpeed(playbackSpeed);

      setState(() => isLoading = false);

      Fluttertoast.showToast(msg: '已切换到 $currentQualityDesc');
    } catch (e) {
      setState(() {
        errorMessage = '切换失败: $e';
        isLoading = false;
      });
    }
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
