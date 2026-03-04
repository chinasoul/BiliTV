import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 判断是否为按键按下或重复事件
bool _isKeyDownOrRepeat(KeyEvent event) =>
    event is KeyDownEvent || event is KeyRepeatEvent;

/// 虚拟键盘按钮
class TvKeyboardButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveUp; // 按上键回调
  final VoidCallback? onBack; // 返回键回调
  final FocusNode? focusNode; // 可选的外部 FocusNode

  const TvKeyboardButton({
    super.key,
    required this.label,
    required this.onTap,
    this.onMoveLeft,
    this.onMoveUp,
    this.onBack,
    this.focusNode,
  });

  @override
  State<TvKeyboardButton> createState() => _TvKeyboardButtonState();
}

class _TvKeyboardButtonState extends State<TvKeyboardButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        final result = TvKeyHandler.handleNavigationWithRepeat(
          event,
          onLeft: widget.onMoveLeft,
          onUp: widget.onMoveUp,
          onSelect: widget.onTap,
        );
        if (result == KeyEventResult.handled) return result;
        if (_isKeyDownOrRepeat(event)) {
          if ((event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack ||
                  event.logicalKey == LogicalKeyboardKey.browserBack) &&
              widget.onBack != null) {
            widget.onBack!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: _isFocused ? SettingsService.themeColor : AppColors.navItemSelectedBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.white : AppColors.inactiveText,
                  fontSize: AppFonts.sizeXL,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 操作按钮 (搜索按钮) - 未选中灰色，选中时主题色
class TvActionButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveUp; // 按上键回调
  final VoidCallback? onBack; // 返回键回调

  const TvActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.onMoveLeft,
    this.onMoveUp,
    this.onBack,
  });

  @override
  State<TvActionButton> createState() => _TvActionButtonState();
}

class _TvActionButtonState extends State<TvActionButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        final result = TvKeyHandler.handleNavigationWithRepeat(
          event,
          onLeft: widget.onMoveLeft,
          onUp: widget.onMoveUp,
          onSelect: widget.onTap,
        );
        if (result == KeyEventResult.handled) return result;
        if (_isKeyDownOrRepeat(event)) {
          if ((event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack ||
                  event.logicalKey == LogicalKeyboardKey.browserBack) &&
              widget.onBack != null) {
            widget.onBack!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: _isFocused ? widget.color : AppColors.navItemSelectedBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.white : AppColors.inactiveText,
                  fontSize: AppFonts.sizeXL,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
