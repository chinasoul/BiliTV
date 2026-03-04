import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/video.dart';
import '../../../widgets/conditional_marquee.dart';
import '../../../config/app_style.dart';
import 'tv_progress_bar.dart';
import 'package:bili_tv_app/services/settings_service.dart';

class ControlsOverlay extends StatelessWidget {
  final Video video;
  final VideoPlayerController controller;
  final bool showControls;
  final int focusedIndex; // 可见按钮列表中的焦点索引
  final List<int> visibleControlIndices; // 可显示的控制按钮动作索引
  final VoidCallback onPlayPause;
  final VoidCallback onSettings;
  final VoidCallback onToggleStatsForNerds;
  final VoidCallback onEpisodes;
  final bool isDanmakuEnabled;
  final VoidCallback onToggleDanmaku;
  final String currentQuality;
  final VoidCallback onQualityClick;
  final bool isProgressBarFocused; // 进度条是否获得焦点
  final Duration? previewPosition; // 预览位置（快进快退时）
  final String? onlineCount; // 在线观看人数
  final int danmakuCount; // 弹幕总数
  final bool showStatsForNerds;
  final bool isLoopMode; // 循环播放模式
  final VoidCallback onToggleLoop; // 切换循环播放
  final VoidCallback onClose; // 关闭视频
  final ValueChanged<int> onControlTap; // 鼠标点击控制按钮
  final ValueChanged<double> onProgressSeek; // 鼠标控制进度条

  const ControlsOverlay({
    super.key,
    required this.video,
    required this.controller,
    required this.showControls,
    required this.focusedIndex,
    required this.visibleControlIndices,
    required this.onPlayPause,
    required this.onSettings,
    required this.onToggleStatsForNerds,
    required this.onEpisodes,
    required this.isDanmakuEnabled,
    required this.onToggleDanmaku,
    required this.currentQuality,
    required this.onQualityClick,
    this.isProgressBarFocused = false,
    this.previewPosition,
    this.alwaysShowPlayerTime = false,
    this.onlineCount,
    this.danmakuCount = 0,
    this.showStatsForNerds = false,
    this.isLoopMode = false,
    required this.onToggleLoop,
    required this.onClose,
    required this.onControlTap,
    required this.onProgressSeek,
  });

  final bool alwaysShowPlayerTime;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
    return '${twoDigits(m)}:${twoDigits(s)}';
  }

  // 构建视频信息文本
  String _buildVideoInfoText() {
    final parts = <String>[];
    parts.add(video.ownerName);
    if (video.pubdate > 0) {
      parts.add('发布于${video.pubdateFormatted}');
    }
    if (video.view > 0) {
      parts.add('${video.viewFormatted}次观看');
    }
    return parts.join(' · ');
  }

  // 格式化弹幕数
  String _formatDanmakuCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  String _controlHintTextFor(_ControlType type) {
    switch (type) {
      case _ControlType.playPause:
        return controller.value.isPlaying ? '暂停' : '播放';
      case _ControlType.comment:
        return '评论';
      case _ControlType.episodes:
        return '选集';
      case _ControlType.owner:
        return 'UP主';
      case _ControlType.moreVideos:
        return '更多视频';
      case _ControlType.settings:
        return '设置';
      case _ControlType.stats:
        return showStatsForNerds ? '关闭监测' : '开启监测';
      case _ControlType.interaction:
        return '互动操作';
      case _ControlType.loop:
        return isLoopMode ? '单集循环' : '循环播放';
      case _ControlType.videoInfo:
        return '视频详情';
      case _ControlType.closePlayer:
        return '关闭播放器';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 计算缓冲时长
    Duration buffered = Duration.zero;
    if (controller.value.buffered.isNotEmpty) {
      buffered = controller.value.buffered.last.end;
    }

    return Stack(
      children: [
        // 顶部渐变 + 标题
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            // 右侧预留空间给时间显示 (150)
            padding: const EdgeInsets.fromLTRB(40, 20, 150, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ConditionalMarquee(
                        text: video.title.isNotEmpty ? video.title : '加载中...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppFonts.sizeXL,
                          fontWeight: FontWeight.bold,
                        ),
                        blankSpace: 50.0,
                        velocity: 40.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _buildVideoInfoText(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: AppFonts.sizeXL,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 底部控制区
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 25),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TvProgressBar(
                        position: previewPosition ?? controller.value.position,
                        duration: controller.value.duration,
                        buffered: buffered,
                        isFocused: isProgressBarFocused,
                        onSeekRequested: onProgressSeek,
                      ),
                    ),
                    const SizedBox(width: 20),
                    // 放大时间码字体
                    Text(
                      '${_formatDuration(previewPosition ?? controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppFonts.sizeXL,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    // 根据屏幕宽度计算按钮尺寸
                    final screenWidth = MediaQuery.of(context).size.width;
                    final buttonAreaWidth =
                        screenWidth * PlayerControlsStyle.buttonAreaRatio;
                    final controlItems = <_ControlButtonItem>[
                      _ControlButtonItem(
                        type: _ControlType.playPause,
                        icon: controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.comment,
                        icon: Icons.comment_outlined,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.episodes,
                        icon: Icons.playlist_play,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.owner,
                        icon: Icons.person,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.moreVideos,
                        icon: Icons.expand_more,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.settings,
                        icon: Icons.tune,
                      ),
                      _ControlButtonItem(
                        type: _ControlType.stats,
                        icon: showStatsForNerds
                            ? Icons.monitor_heart
                            : Icons.monitor_heart_outlined,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.interaction,
                        icon: Icons.thumb_up_outlined,
                      ),
                      _ControlButtonItem(
                        type: _ControlType.loop,
                        icon: isLoopMode ? Icons.repeat_one : Icons.repeat,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.videoInfo,
                        icon: Icons.info_outline,
                      ),
                      const _ControlButtonItem(
                        type: _ControlType.closePlayer,
                        icon: Icons.close,
                      ),
                    ];
                    final itemByIndex = <int, _ControlButtonItem>{
                      for (final item in controlItems) item.type.index: item,
                    };
                    final visibleItems = visibleControlIndices
                        .map((index) => itemByIndex[index])
                        .whereType<_ControlButtonItem>()
                        .toList();
                    final buttonCount = visibleItems.length;
                    if (buttonCount == 0) {
                      return Row(
                        children: [
                          const Spacer(),
                          _buildInfoText(AppFonts.sizeLG, 12),
                        ],
                      );
                    }
                    // 按钮区域 = buttonCount * buttonSize + (buttonCount - 1) * spacing
                    // spacing = buttonSize * spacingRatio
                    // buttonAreaWidth = buttonCount * buttonSize + (buttonCount - 1) * buttonSize * spacingRatio
                    // buttonAreaWidth = buttonSize * (buttonCount + (buttonCount - 1) * spacingRatio)
                    final buttonSize =
                        buttonAreaWidth /
                        (buttonCount +
                            (buttonCount - 1) *
                                PlayerControlsStyle.spacingRatio);
                    final spacing =
                        buttonSize * PlayerControlsStyle.spacingRatio;
                    final iconSize = buttonSize * 0.6; // 图标占按钮60%
                    final padding = buttonSize * 0.2; // 内边距占按钮20%
                    final infoFontSize =
                        buttonSize * PlayerControlsStyle.infoFontRatio;
                    final infoSpacing =
                        buttonSize * PlayerControlsStyle.infoSpacingRatio;

                    return Row(
                      children: [
                        for (int i = 0; i < visibleItems.length; i++) ...[
                          _buildControlButton(
                            actionIndex: visibleItems[i].type.index,
                            icon: visibleItems[i].icon,
                            iconSize: iconSize,
                            padding: padding,
                            buttonExtent: buttonSize,
                            hintText: _controlHintTextFor(visibleItems[i].type),
                            isFocused:
                                !isProgressBarFocused &&
                                focusedIndex == i &&
                                showControls,
                          ),
                          if (i < visibleItems.length - 1)
                            SizedBox(width: spacing),
                        ],
                        const Spacer(),
                        // 右侧信息区
                        _buildInfoText(infoFontSize, infoSpacing),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required int actionIndex,
    required IconData icon,
    required double iconSize,
    required double padding,
    required double buttonExtent,
    required String hintText,
    required bool isFocused,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onControlTap(actionIndex),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: isFocused
                    ? SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isFocused ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: iconSize),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: -(buttonExtent * 0.9),
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    opacity: isFocused ? 1.0 : 0.0,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      scale: isFocused ? 1.0 : 0.96,
                      child: UnconstrainedBox(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            hintText,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppFonts.sizeMD,
                              fontWeight: AppFonts.semibold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoText(double fontSize, double spacing) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 在线人数
        if (onlineCount != null && onlineCount!.isNotEmpty) ...[
          Text(
            '在看:$onlineCount',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: fontSize,
            ),
          ),
          SizedBox(width: spacing),
        ],
        // 弹幕数
        Text(
          isDanmakuEnabled && danmakuCount > 0
              ? '弹幕:${_formatDanmakuCount(danmakuCount)}'
              : (isDanmakuEnabled ? '弹幕' : '弹幕关'),
          style: TextStyle(
            color: isDanmakuEnabled
                ? Colors.white.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.5),
            fontSize: fontSize,
          ),
        ),
        SizedBox(width: spacing),
        // 画质
        Text(
          currentQuality,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }
}

class _ControlButtonItem {
  final _ControlType type;
  final IconData icon;

  const _ControlButtonItem({
    required this.type,
    required this.icon,
  });
}

enum _ControlType {
  playPause,
  comment,
  episodes,
  owner,
  moreVideos,
  settings,
  stats,
  interaction,
  loop,
  videoInfo,
  closePlayer,
}
