import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:marquee/marquee.dart';
import '../models/video.dart';
import '../services/settings_service.dart';
import 'base_tv_card.dart';
import '../utils/image_url_utils.dart';
import '../screens/live/live_player_screen.dart';

/// 历史记录专用视频卡片
/// 特点：
/// 1. 不显示播放数（接口返回0）
/// 2. 显示进度条和 xx:xx/yy:yy 格式的进度
/// 3. 播放完成显示"已播完"
class HistoryVideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onBack;
  final bool autofocus;
  final FocusNode? focusNode;

  const HistoryVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onBack,
    this.autofocus = false,
    this.focusNode,
  });

  /// 是否已播完（B站API返回 progress == -1 表示已看完）
  /// 或者进度非常接近总时长（允许1秒误差，解决 19:33/19:33 显示问题且不影响短视频）
  bool get _isCompleted {
    if (video.progress == -1) return true;
    if (video.duration > 0 && video.progress >= video.duration - 1) return true;
    return false;
  }

  /// 观看进度比例 (0.0 ~ 1.0)
  double get _progressRatio {
    if (_isCompleted) return 1.0;
    if (video.duration <= 0 || video.progress <= 0) return 0.0;
    return (video.progress / video.duration).clamp(0.0, 1.0);
  }

  /// 格式化进度时间
  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return BaseTvCard(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: () {
        // 只有当是直播且没有 BVID 时（表示是直播间而非回放视频）才跳转直播播放器
        // "直播回放"通常有 BVID，应作为普通视频播放
        if (video.isLive && video.bvid.isEmpty) {
          if (video.badge == '未开播') {
            SettingsService.toast(context, '当前未开播');
            return;
          }

          // Navigate to LivePlayerScreen
          // For live history, cid is mapped from oid which is the room id
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LivePlayerScreen(
                roomId: video.cid,
                title: video.title,
                cover: video.pic,
                uname: video.ownerName,
                face: video.ownerFace,
                online: 0, // History doesn't have real-time online count
              ),
            ),
          );
          return;
        }
        onTap();
      },
      onFocus: onFocus,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onBack: onBack,
      imageContent: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(),
          // 角标 (付费/充电专属)
          if (video.badge.isNotEmpty)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFfb7299),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  video.badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // 渐变遮罩
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
          ),
          // 底部信息 - 历史记录显示进度
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 时间信息
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 左侧：分P信息（多P视频显示，单P视频隐藏）
                      // historyVideos > 1 表示多P视频，显示"已看至 Px"
                      if (video.historyVideos > 1)
                        Text(
                          '已看至 P${video.historyPage}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (video.historyVideos <= 1) const SizedBox(), // 占位
                      // 右侧：时间/进度 (直播/未开播不显示)
                      if (!video.isLive)
                        Text(
                          _isCompleted
                              ? '已看完'
                              : '${_formatTime(video.progress > 0 ? video.progress : 0)} / ${_formatTime(video.duration)}',
                          style: TextStyle(
                            color: _isCompleted
                                ? const Color(0xFFfb7299)
                                : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // 进度条 - 贴底，全宽，无圆角
                SizedBox(
                  height: 3,
                  child: Stack(
                    children: [
                      // 背景条
                      Container(color: Colors.white.withValues(alpha: 0.3)),
                      // 进度条
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progressRatio,
                        child: Container(color: const Color(0xFFfb7299)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      infoContentBuilder: (context, isFocused) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题区域
            SizedBox(
              height: 20,
              child: isFocused
                  ? Marquee(
                      text: video.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      scrollAxis: Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      blankSpace: 30.0,
                      velocity: 50.0,
                      pauseAfterRound: const Duration(seconds: 1),
                      startPadding: 0.0,
                      accelerationDuration: const Duration(milliseconds: 500),
                      accelerationCurve: Curves.linear,
                      decelerationDuration: const Duration(milliseconds: 300),
                      decelerationCurve: Curves.easeOut,
                    )
                  : Text(
                      video.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            // UP主信息 + 观看时间
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 12,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                // UP主名字 - 可省略
                Expanded(
                  child: Text(
                    video.ownerName,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 最后观看时间 - 固定位置，不省略
                if (video.viewAtFormatted.isNotEmpty)
                  Text(
                    video.viewAtFormatted,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildImage() {
    const int targetWidth = 360;
    const int targetHeight = 200;

    return CachedNetworkImage(
      imageUrl: ImageUrlUtils.getResizedUrl(video.pic, width: 640, height: 360),
      fit: BoxFit.cover,
      memCacheWidth: targetWidth,
      memCacheHeight: targetHeight,
      cacheManager: BiliCacheManager.instance,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => Container(color: const Color(0xFF2d2d2d)),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[900],
        child: const Icon(Icons.broken_image, size: 20, color: Colors.white24),
      ),
    );
  }
}
