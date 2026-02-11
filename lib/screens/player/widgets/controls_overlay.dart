import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/video.dart';
import '../../../widgets/time_display.dart';
import '../../../widgets/conditional_marquee.dart';
import 'tv_progress_bar.dart';

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

        // 顶部时间显示 (仅当非全局常驻时显示)
        // 位置与 PlayerScreen 的常驻时间保持一致 (top: 20, right: 30)
        // 注意：Global Time 在 PlayerScreen 中处理，这里只处理 Controls overlay 内部的临时显示
        if (!alwaysShowPlayerTime)
          const Positioned(top: 20, right: 30, child: TimeDisplay()),

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
                        previewPosition: previewPosition,
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
                Row(
                  children: [
                    // 选集 (原 index 1 → 现 index 0)
                    _buildControlButton(
                      index: 0,
                      icon: Icons.playlist_play,
                      onTap: onEpisodes,
                    ),
                    const SizedBox(width: 24),
                    // UP主 (原 index 2 → 现 index 1)
                    _buildControlButton(
                      index: 1,
                      icon: Icons.person,
                      onTap: () {},
                    ),
                    const SizedBox(width: 24),
                    // 更多视频 (原 index 3 → 现 index 2)
                    _buildControlButton(
                      index: 2,
                      icon: Icons.expand_more,
                      onTap: () {},
                    ),
                    const SizedBox(width: 24),
                    // 设置 (原 index 4 → 现 index 3)
                    _buildControlButton(
                      index: 3,
                      icon: Icons.tune,
                      onTap: onSettings,
                    ),
                    const SizedBox(width: 24),
                    // 视频数据实时监测开关
                    _buildControlButton(
                      index: 4,
                      icon: showStatsForNerds
                          ? Icons.monitor_heart
                          : Icons.monitor_heart_outlined,
                      onTap: onToggleStatsForNerds,
                    ),
                    const SizedBox(width: 24),
                    // 点赞/投币/收藏
                    _buildControlButton(
                      index: 5,
                      icon: Icons.thumb_up_outlined,
                      onTap: () {},
                    ),
                    const Spacer(),
                    // 在线人数 (纯文字)
                    if (onlineCount != null && onlineCount!.isNotEmpty)
                      Text(
                        '在看:$onlineCount',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    if (onlineCount != null && onlineCount!.isNotEmpty)
                      const SizedBox(width: 16),
                    // 弹幕数 (纯文字)
                    Text(
                      isDanmakuEnabled && danmakuCount > 0
                          ? '弹幕:${_formatDanmakuCount(danmakuCount)}'
                          : (isDanmakuEnabled ? '弹幕' : '弹幕关'),
                      style: TextStyle(
                        color: isDanmakuEnabled
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 画质 (纯文字)
                    Text(
                      currentQuality,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
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
    required VoidCallback onTap,
  }) {
    final isFocused =
        !isProgressBarFocused && focusedIndex == index && showControls;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFFfb7299).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: isFocused ? Border.all(color: Colors.white, width: 3) : null,
      ),
      child: Icon(icon, color: Colors.white, size: 36),
    );
  }
}
