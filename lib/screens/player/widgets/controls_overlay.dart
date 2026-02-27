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
  final int focusedIndex;
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

  String _controlHintTextFor(int index) {
    switch (index) {
      case 0:
        return controller.value.isPlaying ? '暂停' : '播放';
      case 1:
        return '评论';
      case 2:
        return '选集';
      case 3:
        return 'UP主';
      case 4:
        return '更多视频';
      case 5:
        return '设置';
      case 6:
        return showStatsForNerds ? '关闭监测' : '开启监测';
      case 7:
        return '互动操作';
      case 8:
        return isLoopMode ? '单集循环' : '循环播放';
      case 9:
        return '关闭播放器';
      default:
        return '';
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
                      child: SizedBox(
                        height: 30, // 固定高度
                        child: ConditionalMarquee(
                          text: video.title.isNotEmpty ? video.title : '加载中...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22, // 固定字号
                            fontWeight: FontWeight.bold,
                          ),
                          blankSpace: 50.0,
                          velocity: 40.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _buildVideoInfoText(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 18,
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
                        fontSize: 22,
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
                    const buttonCount = 10;
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
                        // 播放/暂停 (index 0)
                        _buildControlButton(
                          index: 0,
                          icon: controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(0),
                        ),
                        SizedBox(width: spacing),
                        // 评论 (index 1)
                        _buildControlButton(
                          index: 1,
                          icon: Icons.comment_outlined,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(1),
                        ),
                        SizedBox(width: spacing),
                        // 选集 (index 2)
                        _buildControlButton(
                          index: 2,
                          icon: Icons.playlist_play,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(2),
                        ),
                        SizedBox(width: spacing),
                        // UP主 (index 3)
                        _buildControlButton(
                          index: 3,
                          icon: Icons.person,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(3),
                        ),
                        SizedBox(width: spacing),
                        // 更多视频 (index 4)
                        _buildControlButton(
                          index: 4,
                          icon: Icons.expand_more,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(4),
                        ),
                        SizedBox(width: spacing),
                        // 设置 (index 5)
                        _buildControlButton(
                          index: 5,
                          icon: Icons.tune,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(5),
                        ),
                        SizedBox(width: spacing),
                        // 视频数据实时监测开关 (index 6)
                        _buildControlButton(
                          index: 6,
                          icon: showStatsForNerds
                              ? Icons.monitor_heart
                              : Icons.monitor_heart_outlined,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(6),
                        ),
                        SizedBox(width: spacing),
                        // 点赞/投币/收藏 (index 7)
                        _buildControlButton(
                          index: 7,
                          icon: Icons.thumb_up_outlined,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(7),
                        ),
                        SizedBox(width: spacing),
                        // 循环播放 (index 8)
                        _buildControlButton(
                          index: 8,
                          icon: isLoopMode ? Icons.repeat_one : Icons.repeat,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(8),
                        ),
                        SizedBox(width: spacing),
                        // 关闭视频 (index 9)
                        _buildControlButton(
                          index: 9,
                          icon: Icons.close,
                          iconSize: iconSize,
                          padding: padding,
                          buttonExtent: buttonSize,
                          hintText: _controlHintTextFor(9),
                        ),
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
    required int index,
    required IconData icon,
    required double iconSize,
    required double padding,
    required double buttonExtent,
    required String hintText,
  }) {
    final isFocused =
        !isProgressBarFocused && focusedIndex == index && showControls;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onControlTap(index),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: isFocused
                    ? SettingsService.themeColor.withValues(alpha: 0.8)
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
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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
