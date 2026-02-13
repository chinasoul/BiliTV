import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/settings_service.dart';
import '../utils/image_url_utils.dart';
import 'base_tv_card.dart';
import 'conditional_marquee.dart';

class TvLiveCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool autofocus;
  final FocusNode? focusNode;

  const TvLiveCard({
    super.key,
    required this.room,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    // API 字段可能不同，getListByAreaID 返回的数据结构:
    // title, cover, uname, online, roomid
    final title = room['title'] ?? '无标题';
    final cover =
        room['pic'] ??
        room['room_cover'] ??
        room['cover'] ??
        room['user_cover'] ??
        room['keyframe'];
    final uname = room['uname'] ?? '';
    final online = room['online'] ?? 0;

    String onlineText = '$online';
    if (online >= 10000) {
      onlineText = '${(online / 10000).toStringAsFixed(1)}万';
    }

    return BaseTvCard(
      autofocus: autofocus,
      focusNode: focusNode,
      onTap: onTap,
      onFocus: onFocus,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      imageContent: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(cover),
          // 直播中角标
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF81C784),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bar_chart, size: 10, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    '直播中',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 底部阴影
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
          // 在线人数
          Positioned(
            left: 6,
            bottom: 6,
            child: Row(
              children: [
                const Icon(Icons.person, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  onlineText,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
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
            // 标题
            SizedBox(
              height: 20,
              child: isFocused
                  ? ConditionalMarquee(
                      text: title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      blankSpace: 30.0,
                      velocity: 30.0,
                    )
                  : Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(height: 4),
            // UP主
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 12,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    uname,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildImage(String? url) {
    if (url == null || url.isEmpty) {
      return Container(color: const Color(0xFF2d2d2d));
    }

    // 直播封面通常是 16:9 或类似，这里沿用 360x200 逻辑
    return CachedNetworkImage(
      imageUrl: ImageUrlUtils.getResizedUrl(url, width: 360, height: 200),
      fit: BoxFit.cover,
      memCacheWidth: 360,
      memCacheHeight: 200,
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
