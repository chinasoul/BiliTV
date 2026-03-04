import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/settings_service.dart';
import '../core/focus/focus_navigation.dart';
import 'vip_avatar_badge.dart';
import 'package:bili_tv_app/config/app_style.dart';

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
  Widget build(BuildContext context) => Focus(
    focusNode: focusNode,
    autofocus: autofocus,
    onFocusChange: (f) => f ? onFocus() : null,
    onKeyEvent: (node, event) {
      // 按约定：侧边栏到首/尾后，长按应停住，单击才允许循环到另一端。
      if (event is KeyRepeatEvent) {
        if ((isFirst && event.logicalKey == LogicalKeyboardKey.arrowUp) ||
            (isLast && event.logicalKey == LogicalKeyboardKey.arrowDown)) {
          return KeyEventResult.handled;
        }
      }
      return TvKeyHandler.handleNavigationWithRepeat(
        event,
        onUp: onMoveUp,
        onDown: onMoveDown,
        onLeft: onMoveLeft,
        onRight: onMoveRight,
        onSelect: onTap,
        // 无目标时吞键，防止默认方向搜索串到内容区
        blockUp: onMoveUp == null,
        blockDown: onMoveDown == null,
        blockLeft: onMoveLeft == null,
        // 个人中心（登录/资料）依赖默认右向搜索进入内容区，保留该行为。
        blockRight: false,
      );
    },
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
                    ? SettingsService.themeColor.withValues(
                        alpha: AppColors.focusAlpha,
                      )
                    : (isSelected
                          ? AppColors.navItemSelectedBackground
                          : Colors.transparent),
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
              child: Icon(Icons.person, size: 20, color: AppColors.inactiveText),
            ),
            errorWidget: (_, _, _) => Container(
              width: 36,
              height: 36,
              color: Colors.grey[700],
              child: Icon(Icons.person, size: 20, color: AppColors.inactiveText),
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
          focused
              ? AppColors.primaryText
              : (isSelected ? AppColors.primaryText : AppColors.inactiveText),
          BlendMode.srcIn,
        ),
      );
    }

    // 默认图标
    return Icon(
      Icons.circle,
      size: 32,
      color: focused
          ? AppColors.primaryText
          : (isSelected ? AppColors.primaryText : AppColors.inactiveText),
    );
  }
}
