import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/build_flags.dart';
import '../../models/video.dart';
import '../../services/settings_service.dart';
import 'widgets/video_layer.dart';
import 'widgets/danmaku_layer.dart';
import 'widgets/controls_overlay.dart';
import 'widgets/settings_panel.dart';
import 'widgets/episode_panel.dart';
import 'widgets/pause_indicator.dart';
import 'widgets/action_buttons.dart';
import 'widgets/up_panel.dart';
import 'widgets/related_panel.dart';
import 'widgets/comment_panel.dart';
import 'widgets/mini_progress_bar.dart';
import 'widgets/seek_preview_thumbnail.dart';
import 'widgets/next_episode_preview.dart';
import '../../widgets/time_display.dart';
import '../../services/codec_service.dart';
import 'mixins/player_state_mixin.dart';
import 'mixins/player_action_mixin.dart';
import 'mixins/player_event_mixin.dart';

/// 视频播放器页面 (使用 Mixin 重构)
class PlayerScreen extends StatefulWidget {
  final Video video;

  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with
        PlayerStateMixin,
        PlayerActionMixin,
        PlayerEventMixin,
        WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 保持屏幕常亮，防止电视待机
    WakelockPlus.enable();
    loadSettings();
    initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 应用进入后台时上报进度 (包括按主页键)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      reportPlaybackProgress();
    }
  }

  @override
  void dispose() {
    // 恢复屏幕休眠
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    hideTimer?.cancel();
    progressReportTimer?.cancel();
    // 退出时上报进度
    reportPlaybackProgress();

    // 通过 mixin 方法销毁播放器
    disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onPopInvoked,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: handleGlobalKeyEvent,
          child: Stack(
            children: [
              // 视频层
              VideoLayer(
                controller: videoController,
                isLoading: isLoading,
                errorMessage: errorMessage,
              ),

              // 弹幕层
              if (!isLoading &&
                  videoController != null &&
                  danmakuEnabled &&
                  !(defaultTargetPlatform == TargetPlatform.android &&
                      preferNativeDanmaku))
                DanmakuLayer(
                  onCreated: (c) => danmakuController = c,
                  option: DanmakuOption(
                    opacity: danmakuOpacity,
                    fontSize: danmakuFontSize,
                    // 弹幕飞行速度随播放倍速同步调整
                    duration: danmakuSpeed / playbackSpeed,
                    area: danmakuArea,
                    hideTop: hideTopDanmaku,
                    hideBottom: hideBottomDanmaku,
                  ),
                ),

              // 暂停指示器
              if (!isLoading && videoController != null)
                PauseIndicator(
                  controller: videoController,
                  isSeeking: pendingSeekTarget != null || isSeekPreviewMode,
                ),

              // 迷你进度条 (控制栏隐藏时显示)
              if (!isLoading &&
                  videoController != null &&
                  !showControls &&
                  SettingsService.showMiniProgress)
                MiniProgressBar(
                  // 批量快进时使用累积目标位置，刚提交后使用上次提交位置，否则使用实际播放位置
                  position: getDisplayPosition(),
                  duration: videoController!.value.duration,
                  // 快进中或刚提交后短暂隐藏缓冲条，防止旧数据闪烁
                  bufferedRanges:
                      (pendingSeekTarget != null || hideBufferAfterSeek)
                      ? const []
                      : videoController!.value.buffered,
                ),

              // 快进快退指示器 (含预览缩略图) - 仅快进预览模式且有雪碧图时显示
              if (showSeekIndicator &&
                  videoController != null &&
                  isSeekPreviewMode &&
                  previewPosition != null &&
                  videoshotData != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 显示缩略图
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SeekPreviewThumbnail(
                            videoshotData: videoshotData!,
                            previewPosition: previewPosition!,
                            scale: 0.6,
                          ),
                        ),
                        // 时间指示器
                        Text(
                          '${_formatSeekTime(previewPosition!)} / ${_formatSeekTime(videoController!.value.duration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                blurRadius: 4,
                                color: Colors.black,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        // 操作提示
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '按确定跳转',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 快进快退时间指示器 (无缩略图时) - 普通快进快退模式显示
              if (showSeekIndicator &&
                  videoController != null &&
                  previewPosition != null &&
                  !(isSeekPreviewMode && videoshotData != null))
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_formatSeekTime(previewPosition!)} / ${_formatSeekTime(videoController!.value.duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 控制界面
              if (!isLoading && videoController != null)
                AnimatedOpacity(
                  opacity: showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: ControlsOverlay(
                    video: getDisplayVideo(),
                    controller: videoController!,
                    showControls: showControls,
                    focusedIndex: focusedButtonIndex,
                    onPlayPause: togglePlayPause,
                    onSettings: () {
                      setState(() {
                        showSettingsPanel = true;
                        hideTimer?.cancel();
                      });
                    },
                    onEpisodes: () {
                      ensureEpisodesLoaded(); // 按需加载完整集数列表
                      setState(() {
                        showEpisodePanel = true;
                        hideTimer?.cancel();
                      });
                    },
                    isDanmakuEnabled: danmakuEnabled,
                    onToggleDanmaku: toggleDanmaku,
                    currentQuality: currentQualityDesc,
                    onQualityClick: showQualityPicker,
                    isProgressBarFocused: isProgressBarFocused,
                    previewPosition: previewPosition,
                    alwaysShowPlayerTime: SettingsService.alwaysShowPlayerTime,
                    onlineCount: onlineCount,
                    danmakuCount: danmakuList.length,
                    showStatsForNerds: showStatsForNerds,
                    onToggleStatsForNerds: toggleStatsForNerds,
                    isLoopMode: isLoopMode,
                    onToggleLoop: toggleLoopMode,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),

              // 常驻时间显示
              if (SettingsService.alwaysShowPlayerTime)
                const Positioned(top: 10, right: 14, child: TimeDisplay()),

              // 自动连播提示 (全局开启 + 多集视频时显示)
              if (SettingsService.autoPlay &&
                  hasMultipleEpisodes &&
                  !isLoading &&
                  videoController != null)
                Positioned(
                  top: SettingsService.alwaysShowPlayerTime ? 40 : 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '自动连播已开启',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

              // 视频数据实时监测（类似 YouTube Stats for Nerds）
              if (!isLoading &&
                  videoController != null &&
                  showStatsForNerds &&
                  !showSettingsPanel &&
                  !showEpisodePanel)
                Positioned(top: 20, left: 30, child: _buildStatsForNerds()),

              // 点赞/投币/收藏按钮
              if (showActionButtons && !isLoading && videoController != null)
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ActionButtons(
                      video: widget.video,
                      aid: aid ?? 0,
                      isFocused: showActionButtons,
                      onFocusExit: () {
                        setState(() => showActionButtons = false);
                        startHideTimer();
                      },
                      onUserInteraction: () {
                        startHideTimer();
                      },
                    ),
                  ),
                ),

              // 下一集预览（即将播放完毕时从右下角滑入）
              // 仅在需要时加入 widget 树，避免 AnimatedPositioned 持续占用渲染层
              if (showNextEpisodePreview &&
                  !isLoading &&
                  videoController != null &&
                  nextEpisodeInfo != null)
                NextEpisodePreview(
                  visible: true,
                  title: nextEpisodeInfo?['title'] ?? '',
                  pic: nextEpisodeInfo?['pic'],
                  countdown: nextEpisodeCountdown,
                ),

              // 选集面板
              if (showEpisodePanel)
                EpisodePanel(
                  episodes: episodes,
                  currentCid: cid ?? 0,
                  focusedIndex: focusedEpisodeIndex,
                  onEpisodeSave: switchEpisode,
                  onClose: () {
                    setState(() {
                      showEpisodePanel = false;
                      showControls = true;
                    });
                    startHideTimer();
                  },
                  isUgcSeason: isUgcSeason,
                  currentBvid: widget.video.bvid,
                  onUgcEpisodeSelect: (bvid) {
                    switchEpisode(0, targetBvid: bvid);
                  },
                ),

              // 设置面板
              if (showSettingsPanel)
                SettingsPanel(
                  menuType: settingsMenuType,
                  focusedIndex: focusedSettingIndex,
                  qualityDesc: currentQualityDesc,
                  playbackSpeed: playbackSpeed,
                  availableSpeeds: availableSpeeds,
                  danmakuEnabled: danmakuEnabled,
                  danmakuOpacity: danmakuOpacity,
                  danmakuFontSize: danmakuFontSize,
                  danmakuArea: danmakuArea,
                  danmakuSpeed: danmakuSpeed,
                  hideTopDanmaku: hideTopDanmaku,
                  hideBottomDanmaku: hideBottomDanmaku,
                  onNavigate: (type, index) {
                    setState(() {
                      settingsMenuType = type;
                      focusedSettingIndex = index;
                    });
                  },
                  onQualityPicker: showQualityPicker,
                ),

              // UP主面板
              if (showUpPanel)
                UpPanel(
                  upName: widget.video.ownerName,
                  upFace: widget.video.ownerFace,
                  upMid: widget.video.ownerMid,
                  onVideoSelect: (video) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(video: video),
                      ),
                    );
                  },
                  onClose: () {
                    setState(() {
                      showUpPanel = false;
                      showControls = true;
                    });
                    startHideTimer();
                  },
                ),

              // 评论面板
              if (showCommentPanel && aid != null)
                CommentPanel(
                  aid: aid!,
                  onClose: () {
                    setState(() {
                      showCommentPanel = false;
                      showControls = true;
                    });
                    startHideTimer();
                  },
                ),

              // 更多视频面板
              if (showRelatedPanel)
                RelatedPanel(
                  bvid: widget.video.bvid,
                  onVideoSelect: (video) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(video: video),
                      ),
                    );
                  },
                  onClose: () {
                    setState(() {
                      showRelatedPanel = false;
                      showControls = true;
                    });
                    startHideTimer();
                  },
                ),

              // 插件跳过按钮
              _buildSkipButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsForNerds() {
    final size = videoController!.value.size;
    final width = videoWidth > 0 ? videoWidth : size.width.round();
    final height = videoHeight > 0 ? videoHeight : size.height.round();
    final fps = videoFrameRate > 0 ? videoFrameRate : 0.0;
    final codec = currentCodec.startsWith('av01')
        ? 'AV1'
        : (currentCodec.startsWith('hev') || currentCodec.startsWith('hvc'))
        ? 'H.265'
        : (currentCodec.startsWith('avc') ? 'H.264' : '未知');

    final resolutionText = '$width x $height@${fps.toStringAsFixed(3)}';
    final dataRateText =
        '${videoDataRateKbps <= 0 ? 0 : videoDataRateKbps} Kbps';
    final speedText =
        '${videoSpeedKbps <= 0 ? '0.0' : videoSpeedKbps.toStringAsFixed(1)} Kbps';
    final networkText =
        '${networkActivityKb <= 0 ? '0.00' : networkActivityKb.toStringAsFixed(2)} KB';
    final renderPath = _buildRenderPathText();

    TextStyle labelStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );
    TextStyle valueStyle = const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 190, child: Text(label, style: labelStyle)),
            Expanded(child: Text(value, style: valueStyle)),
          ],
        ),
      );
    }

    return Container(
      width: 620,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '视频数据实时监测',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          row('分辨率', resolutionText),
          row('渲染链路', renderPath),
          row('流(编码)', '$codec（B站下发，本机不编码）'),
          row('视频码率', dataRateText),
          _buildDecodeHintRow(codec, labelStyle, valueStyle),
          row('视频速度', speedText),
          row('网络活动', networkText),
        ],
      ),
    );
  }

  String _buildRenderPathText() {
    final controller = videoController;
    if (controller == null) return 'view=unknown | tunnel=unknown';
    final view = controller.viewType == VideoViewType.platformView
        ? 'platformView'
        : 'textureView';
    final tunnel = defaultTargetPlatform == TargetPlatform.android &&
            controller.viewType == VideoViewType.platformView
        ? 'requested'
        : 'n/a';
    return 'view=$view | tunnel=$tunnel';
  }

  Widget _buildDecodeHintRow(
    String codecLabel,
    TextStyle labelStyle,
    TextStyle valueStyle,
  ) {
    final codecKey = codecLabel == 'AV1'
        ? 'av1'
        : codecLabel == 'H.265'
        ? 'hevc'
        : codecLabel == 'H.264'
        ? 'avc'
        : null;
    if (codecKey == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 190, child: Text('解码', style: labelStyle)),
            Expanded(child: Text('未知', style: valueStyle)),
          ],
        ),
      );
    }
    return FutureBuilder<List<String>>(
      future: CodecService.getHardwareDecoders(),
      builder: (context, snapshot) {
        final hw = snapshot.data ?? [];
        final hasHw = hw.any((e) => e.toLowerCase() == codecKey);
        final hint = hasHw ? '可能硬解' : '可能软解(易卡顿)';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 190, child: Text('解码', style: labelStyle)),
              Expanded(child: Text('$codecLabel $hint', style: valueStyle)),
            ],
          ),
        );
      },
    );
  }

  String _formatSeekTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildSkipButton() {
    if (!BuildFlags.pluginsEnabled || currentSkipAction == null) {
      return const SizedBox.shrink();
    }
    final action = currentSkipAction;

    return Positioned(
      bottom: 120,
      right: 40,
      child: Builder(
        builder: (context) {
          return Focus(
            autofocus: true, // Auto focus when it appears
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter)) {
                _executeSkip(action);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (ctx) {
                final hasFocus = Focus.of(ctx).hasFocus;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: hasFocus
                        ? Theme.of(context).primaryColor
                        : Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: hasFocus ? Colors.white : Colors.white30,
                      width: hasFocus ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        action.label.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _executeSkip(dynamic action) {
    final skipToMs = action?.skipToMs;
    if (skipToMs is! int) return;
    videoController!.seekTo(Duration(milliseconds: skipToMs));
    resetDanmakuIndex(Duration(milliseconds: skipToMs));
    setState(() {
      currentSkipAction = null;
    });
  }
}
