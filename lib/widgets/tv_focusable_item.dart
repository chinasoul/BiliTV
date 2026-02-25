import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/settings_service.dart';
import '../core/focus/focus_navigation.dart';
import 'vip_avatar_badge.dart';

/// 侧边栏焦点项组件
///
/// 使用统一的焦点管理系统
class TvFocusableItem extends StatelessWidget {
  final String? iconPath;
  final String? avatarUrl;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onFocus;
  final VoidCallback onTap;
  final bool autofocus;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool isFirst;
  final bool isLast;

  const TvFocusableItem({
    super.key,
    this.iconPath,
    this.avatarUrl,
    required this.isSelected,
    required this.focusNode,
    required this.onFocus,
    required this.onTap,
    this.autofocus = false,
    this.onMoveRight,
    this.onMoveLeft,
    this.onMoveUp,
    this.onMoveDown,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) => TvFocusScope(
    pattern: FocusPattern.grid,
    focusNode: focusNode,
    autofocus: autofocus,
    onFocusChange: (f) => f ? onFocus() : null,
    onExitUp: onMoveUp,
    onExitDown: onMoveDown,
    onExitLeft: onMoveLeft,
    onExitRight: onMoveRight,
    onSelect: onTap,
    isFirst: isFirst,
    isLast: isLast,
    child: Builder(
      builder: (c) {
        final f = Focus.of(c).hasFocus;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              decoration: BoxDecoration(
                color: f
                    ? SettingsService.themeColor.withValues(alpha: 0.6)
                    : (isSelected ? Colors.white10 : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: null,
              ),
              alignment: Alignment.center,
              child: _buildContent(f),
            ),
          ),
        );
      },
    ),
  );

  Widget _buildContent(bool focused) {
    // 如果有头像 URL，显示头像
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return VipAvatarBadge(
        size: 36,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: avatarUrl!,
            cacheManager: BiliCacheManager.instance,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            memCacheWidth: 100,
            memCacheHeight: 100,
            maxWidthDiskCache: 100,
            maxHeightDiskCache: 100,
            placeholder: (_, _) => Container(
              width: 36,
              height: 36,
              color: Colors.grey[700],
              child: const Icon(Icons.person, size: 20, color: Colors.white54),
            ),
            errorWidget: (_, _, _) => Container(
              width: 36,
              height: 36,
              color: Colors.grey[700],
              child: const Icon(Icons.person, size: 20, color: Colors.white54),
            ),
          ),
        ),
      );
    }

    // 显示 SVG 图标
    if (iconPath != null) {
      return SvgPicture.asset(
        iconPath!,
        width: 32,
        height: 32,
        colorFilter: ColorFilter.mode(
          focused ? Colors.white : (isSelected ? Colors.white : Colors.grey),
          BlendMode.srcIn,
        ),
      );
    }

    // 默认图标
    return Icon(
      Icons.circle,
      size: 32,
      color: focused ? Colors.white : (isSelected ? Colors.white : Colors.grey),
    );
  }
}
