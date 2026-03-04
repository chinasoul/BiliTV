import 'dart:async';
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
import 'widgets/subtitle_layer.dart';
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
import '../../utils/toast_utils.dart';
import '../../core/plugin/plugin_manager.dart';
import '../../plugins/sponsor_block_plugin.dart';
import 'mixins/player_state_mixin.dart';
import 'mixins/player_action_mixin.dart';
import 'mixins/player_event_mixin.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 视频播放器页面 (使用 Mixin 重构)
class PlayerScreen extends StatefulWidget {
  final Video video;
  final int exitPopDepth;

  const PlayerScreen({
    super.key,
    required this.video,
    this.exitPopDepth = 1,
  }) : assert(exitPopDepth >= 1);

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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      reportPlaybackProgress();
    } else if (state == AppLifecycleState.resumed) {
      // Reclaim focus after returning from background.
      // On some TV boxes (especially Android 6.0), the PlatformView's
      // SurfaceView can cause focus drift when the app is backgrounded
      // and resumed, making the remote control unresponsive.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !playerFocusNode.hasFocus) {
          playerFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    hideTimer?.cancel();
    progressReportTimer?.cancel();

    // Synchronously cancel listeners and stop the player BEFORE super.dispose(),
    // ensuring ExoPlayer/MediaCodec resources are released even though
    // disposePlayer() is async. On resource-constrained devices (Android 6.0),
    // un-released resources cause the app to freeze on re-entry.
    cancelPlayerListeners();
    videoController?.pause();

    // Fire-and-forget: async cleanup (progress save, cache, full dispose)
    disposePlayer();
    playerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completionAction = SettingsService.playbackCompletionAction;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onPopInvoked,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: playerFocusNode,
          autofocus: true,
          onKeyEvent: handleGlobalKeyEvent,
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!mounted || isLoading || videoController == null) return;

                // 优先级 1：若有右侧子面板打开，单击空白区先关闭一层，不触发暂停。
                if (showSettingsPanel ||
                    showEpisodePanel ||
                    showUpPanel ||
                    showRelatedPanel ||
                    showCommentPanel ||
                    showActionButtons) {
                  setState(() {
                    showSettingsPanel = false;
                    showEpisodePanel = false;
                    showUpPanel = false;
                    showRelatedPanel = false;
                    showCommentPanel = false;
                    showActionButtons = false;
                    showControls = true;
                  });
                  startHideTimer();
                  return;
                }

                // 优先级 2：无子面板时，维持现有行为：
                // 控制栏隐藏 -> 呼出控制栏；控制栏显示 -> 播放/暂停。
                if (!showControls) {
                  setState(() => showControls = true);
                } else {
                  togglePlayPause();
                }
                startHideTimer();
              },
              child: Stack(
              children: [
              // 视频层
              VideoLayer(
                controller: videoController,
                isLoading: isLoading,
                errorMessage: errorMessage,
              ),

              // 弹幕层 (当原生弹幕渲染未生效时使用 Flutter Canvas 弹幕)
              if (!isLoading &&
                  videoController != null &&
                  danmakuEnabled &&
                  !useNativeDanmakuRender)
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

              // 字幕层
              if (!isLoading &&
                  videoController != null &&
                  subtitleEnabled &&
                  currentSubtitleText.isNotEmpty)
                SubtitleLayer(
                  text: currentSubtitleText,
                  showControls: showControls,
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
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppFonts.sizeXXL,
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
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '按确定跳转',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: AppFonts.sizeSM,
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppFonts.sizeXXL,
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
                      focusedIndex:
                          focusedButtonIndex.clamp(
                            0,
                            visibleControlButtonIndices.isNotEmpty
                                ? visibleControlButtonIndices.length - 1
                                : 0,
                          ).toInt(),
                      visibleControlIndices: visibleControlButtonIndices,
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
                      onClose: exitPlayer,
                      onControlTap: (index) {
                        if (!mounted) return;
                        final visibleIndex = visibleControlButtonIndices.indexOf(
                          index,
                        );
                        setState(() {
                          showControls = true;
                          focusedButtonIndex = visibleIndex >= 0 ? visibleIndex : 0;
                        });
                        activateControlButton(index);
                        startHideTimer();
                      },
                      onProgressSeek: (ratio) {
                        if (!mounted || videoController == null) return;
                        final duration = videoController!.value.duration;
                        if (duration <= Duration.zero) return;

                        final targetMs =
                            (duration.inMilliseconds * ratio)
                                .round()
                                .clamp(0, duration.inMilliseconds);
                        final target = Duration(milliseconds: targetMs);

                        // 从末尾回拖时重置完成状态，避免 UI 卡在“已播完”。
                        if (target.inMilliseconds <
                            duration.inMilliseconds - 1000) {
                          hasHandledVideoComplete = false;
                        }

                        videoController!.seekTo(target);
                        resetDanmakuIndex(target);
                        resetSubtitleIndex(target);
                        setState(() {
                          showControls = true;
                          isProgressBarFocused = false;
                          previewPosition = null;
                        });
                        startHideTimer();
                      },
                    ),
                  ),

              // 常驻时间显示
              if (SettingsService.alwaysShowPlayerTime)
                const Positioned(top: 10, right: 14, child: TimeDisplay()),

              // 左上角播放进度时间显示（当前时间:总时长）
              if (!isLoading &&
                  videoController != null &&
                  SettingsService.showPlayerProgressTime)
                Positioned(
                  top: 14,
                  left: 14,
                  child: _PlayerProgressTimeText(
                    controller: videoController!,
                    getDisplayPosition: getDisplayPosition,
                    formatTime: _formatSeekTime,
                  ),
                ),

              // 播放完成行为提示（仅“播放下一集”且多集视频时显示）
              if (completionAction == PlaybackCompletionAction.playNextEpisode &&
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
                      '播放完成后：下一集',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: AppFonts.sizeSM,
                      ),
                    ),
                  ),
                ),

              // 视频数据实时监测（类似 YouTube Stats for Nerds）
              if (!isLoading &&
                  videoController != null &&
                  showStatsForNerds &&
                  !showSettingsPanel &&
                  !showEpisodePanel &&
                  !showUpPanel &&
                  !showRelatedPanel &&
                  !showCommentPanel &&
                  !showActionButtons)
                Positioned(top: 20, left: 30, child: _buildStatsForNerds()),

              // SponsorBlock 开发者信息
              if (!isLoading && videoController != null)
                Builder(builder: (_) {
                  final sb = PluginManager()
                      .getPlugin<SponsorBlockPlugin>('sponsor_block');
                  if (sb == null || !sb.showDevOverlay) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    bottom: 16,
                    right: 30,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sb.devInfoText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }),

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
                  isUgcSeason: !isPanelShowingPages,
                  currentBvid: widget.video.bvid,
                  onUgcEpisodeSelect: (bvid) {
                    switchEpisode(0, targetBvid: bvid);
                  },
                  hasBothTabs: hasBothEpisodeTypes,
                  showingPagesTab: episodePanelShowingPages,
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
                  subtitleEnabled: subtitleEnabled,
                  subtitleTrackDesc: currentSubtitleTrackDesc,
                  subtitleTrackLabels: subtitleTrackLabels,
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
                  onSpeedSelect: selectPlaybackSpeedByIndex,
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
      ),
    );
  }

  Widget _buildStatsForNerds() {
    final decoderSize = videoController!.value.size;
    final decoderW = decoderSize.width.round();
    final decoderH = decoderSize.height.round();
    final streamW = videoWidth > 0 ? videoWidth : decoderW;
    final streamH = videoHeight > 0 ? videoHeight : decoderH;
    final fps = videoFrameRate > 0 ? videoFrameRate : 0.0;
    final codec = (currentCodec.startsWith('dvhe') || currentCodec.startsWith('dvh1') || currentCodec.startsWith('dvav'))
        ? '杜比视界'
        : currentCodec.startsWith('av01')
        ? 'AV1'
        : (currentCodec.startsWith('hev') || currentCodec.startsWith('hvc'))
        ? 'H.265'
        : (currentCodec.startsWith('avc') ? 'H.264' : '未知');

    final resolutionText = (decoderW > 0 && decoderH > 0 && (decoderW != streamW || decoderH != streamH))
        ? '$decoderW x $decoderH@${fps.toStringAsFixed(3)}（流: $streamW x $streamH）'
        : '$streamW x $streamH@${fps.toStringAsFixed(3)}';
    final dataRateText =
        '${videoDataRateKbps <= 0 ? 0 : videoDataRateKbps} Kbps';
    final speedText =
        '${videoSpeedKbps <= 0 ? '0.0' : videoSpeedKbps.toStringAsFixed(1)} Kbps';
    final networkText =
        '${networkActivityKb <= 0 ? '0.00' : networkActivityKb.toStringAsFixed(2)} KB';
    final renderPath = _buildRenderPathText();

    TextStyle labelStyle = TextStyle(
      color: AppColors.textTertiary,
      fontSize: AppFonts.sizeLG,
      fontWeight: AppFonts.medium,
    );
    TextStyle valueStyle = TextStyle(
      color: Colors.white,
      fontSize: AppFonts.sizeLG,
      fontWeight: AppFonts.semibold,
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
          Text(
            '视频数据实时监测',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppFonts.sizeLG,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          row('分辨率', resolutionText),
          row('渲染链路', renderPath),
          row('流(编码)', '$codec ($currentCodec)'),
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
      top: MediaQuery.of(context).size.height * 2 / 3,
      left: MediaQuery.of(context).size.width * 0.05,
      right: 0,
      child: Center(
        child: _SkipButton(
          action: action,
          onSkip: () => _executeSkip(action),
        ),
      ),
    );
  }

  void _executeSkip(dynamic action) {
    final skipToMs = action?.skipToMs;
    if (skipToMs is! int) return;
    final curMs = videoController!.value.position.inMilliseconds;
    final skippedSec = ((skipToMs - curMs) / 1000).round();
    final label = action?.label?.toString() ?? '跳过';
    videoController!.seekTo(Duration(milliseconds: skipToMs));
    resetDanmakuIndex(Duration(milliseconds: skipToMs));
    resetSubtitleIndex(Duration(milliseconds: skipToMs));
    setState(() {
      currentSkipAction = null;
    });
    ToastUtils.show(
      context,
      '已$label (${skippedSec}s)',
      duration: const Duration(milliseconds: 2000),
    );
  }
}

class _SkipButton extends StatefulWidget {
  final dynamic action;
  final VoidCallback onSkip;
  const _SkipButton({required this.action, required this.onSkip});
  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            widget.onSkip();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final hasFocus = Focus.of(ctx).hasFocus;
            return GestureDetector(
              onTap: widget.onSkip,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: SettingsService.themeColor.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: hasFocus
                      ? Border.all(color: Colors.white, width: 1.5)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                        Icons.fast_forward, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      widget.action.label.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppFonts.sizeMD,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
    );
  }
}

class _PlayerProgressTimeText extends StatefulWidget {
  final VideoPlayerController controller;
  final Duration Function() getDisplayPosition;
  final String Function(Duration) formatTime;

  const _PlayerProgressTimeText({
    required this.controller,
    required this.getDisplayPosition,
    required this.formatTime,
  });

  @override
  State<_PlayerProgressTimeText> createState() => _PlayerProgressTimeTextState();
}

class _PlayerProgressTimeTextState extends State<_PlayerProgressTimeText> {
  int _lastPositionSecond = -1;
  int _lastDurationSecond = -1;
  String _text = '00:00/00:00';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerTick);
    _refreshText(force: true);
  }

  @override
  void didUpdateWidget(covariant _PlayerProgressTimeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerTick);
      widget.controller.addListener(_onControllerTick);
      _lastPositionSecond = -1;
      _lastDurationSecond = -1;
      _refreshText(force: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    super.dispose();
  }

  void _onControllerTick() {
    _refreshText();
  }

  void _refreshText({bool force = false}) {
    final position = widget.getDisplayPosition();
    final duration = widget.controller.value.duration;
    final posSecond = position.inSeconds;
    final durSecond = duration.inSeconds;

    if (!force &&
        posSecond == _lastPositionSecond &&
        durSecond == _lastDurationSecond) {
      return;
    }

    _lastPositionSecond = posSecond;
    _lastDurationSecond = durSecond;

    final nextText = '${widget.formatTime(position)}/${widget.formatTime(duration)}';
    if (!force && nextText == _text) return;

    if (mounted) {
      setState(() {
        _text = nextText;
      });
    } else {
      _text = nextText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: AppFonts.sizeLG,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            blurRadius: 4,
            color: Colors.black,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
