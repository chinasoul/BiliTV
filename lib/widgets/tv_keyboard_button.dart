import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/services/settings_service.dart';

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
        if (_isKeyDownOrRepeat(event)) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              widget.onMoveLeft != null) {
            widget.onMoveLeft!();
            return KeyEventResult.handled;
          }
          // 上键
          if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
              widget.onMoveUp != null) {
            widget.onMoveUp!();
            return KeyEventResult.handled;
          }
          // 返回键
          if ((event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack ||
                  event.logicalKey == LogicalKeyboardKey.browserBack) &&
              widget.onBack != null) {
            widget.onBack!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            widget.onTap();
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
                color: _isFocused ? SettingsService.themeColor : Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.white : Colors.white70,
                  fontSize: 18,
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
        if (_isKeyDownOrRepeat(event)) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              widget.onMoveLeft != null) {
            widget.onMoveLeft!();
            return KeyEventResult.handled;
          }
          // 上键
          if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
              widget.onMoveUp != null) {
            widget.onMoveUp!();
            return KeyEventResult.handled;
          }
          // 返回键
          if ((event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack ||
                  event.logicalKey == LogicalKeyboardKey.browserBack) &&
              widget.onBack != null) {
            widget.onBack!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            widget.onTap();
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
                color: _isFocused ? widget.color : Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused ? Colors.white : Colors.white70,
                  fontSize: 18,
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
