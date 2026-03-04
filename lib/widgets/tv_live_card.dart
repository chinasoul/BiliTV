import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/settings_service.dart';
import '../utils/image_url_utils.dart';
import 'base_tv_card.dart';
import 'conditional_marquee.dart';
import 'package:bili_tv_app/config/app_style.dart';

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

  /// 当前卡片在列表中的索引
  final int index;

  /// 网格列数
  final int gridColumns;

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
    this.index = 0,
    this.gridColumns = 4,
  });

  Widget _buildFocusedTitle(String title) {
    final focusedStyle = TextStyle(
      color: AppColors.primaryText,
      fontSize: AppFonts.sizeMD,
      fontWeight: FontWeight.bold,
    );
    final mode = SettingsService.focusedTitleDisplayMode;
    switch (mode) {
      case FocusedTitleDisplayMode.normal:
        return Text(
          title,
          style: focusedStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      case FocusedTitleDisplayMode.singleScroll:
        return ConditionalMarquee(
          text: title,
          style: focusedStyle,
          blankSpace: 30.0,
          velocity: 30.0,
          repeatBehavior: MarqueeRepeatBehavior.once,
        );
      case FocusedTitleDisplayMode.loopScroll:
        return ConditionalMarquee(
          text: title,
          style: focusedStyle,
          blankSpace: 30.0,
          velocity: 30.0,
        );
    }
  }

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
      index: index,
      gridColumns: gridColumns,
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
                color: SettingsService.themeColor,
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
                      fontSize: AppFonts.sizeXS,
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
                    AppColors.videoCardOverlay,
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
                Icon(Icons.person, size: 12, color: AppColors.inactiveText),
                const SizedBox(width: 4),
                Text(
                  onlineText,
                  style: TextStyle(color: Colors.white, fontSize: AppFonts.sizeXS),
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
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    SettingsService.focusedTitleDisplayMode ==
                        FocusedTitleDisplayMode.normal
                    ? 40
                    : 20,
              ),
              child: isFocused
                  ? _buildFocusedTitle(title)
                  : Text(
                      title,
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: AppFonts.sizeMD,
                        fontWeight: AppFonts.semibold,
                      ),
                      maxLines:
                          SettingsService.focusedTitleDisplayMode ==
                              FocusedTitleDisplayMode.normal
                          ? 2
                          : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(height: 4),
            // UP主
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 12,
                  color: AppColors.inactiveText,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    uname,
                    style: TextStyle(
                      color: AppColors.inactiveText,
                      fontSize: AppFonts.sizeSM,
                    ),
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
        child: Icon(Icons.broken_image, size: 20, color: Colors.white24),
      ),
    );
  }
}
