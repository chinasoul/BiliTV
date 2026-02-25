import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 焦点导航模式
enum FocusPattern {
  /// 垂直列表：↑↓ 移动，←→ 是退出/动作
  vertical,

  /// 水平列表：←→ 移动，↑↓ 是退出
  horizontal,

  /// 网格：四方向移动
  grid,
}

/// 统一的 TV 按键处理工具类
class TvKeyHandler {
  /// 处理方向键和确认键事件
  ///
  /// [event] - 键盘事件
  /// [onUp/Down/Left/Right] - 方向键回调
  /// [onSelect] - 确认键回调 (Enter/Select)
  /// [blockUp/Down/Left/Right] - 是否阻止该方向的默认行为
  ///
  /// 返回 [KeyEventResult.handled] 如果按键被处理
  static KeyEventResult handleNavigation(
    KeyEvent event, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onSelect,
    bool blockUp = false,
    bool blockDown = false,
    bool blockLeft = false,
    bool blockRight = false,
  }) {
    // 只处理 KeyDownEvent，避免重复触发
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        return blockUp ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowDown:
        if (onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        return blockDown ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowLeft:
        if (onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        return blockLeft ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowRight:
        if (onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        return blockRight ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        if (onSelect != null) {
          onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      default:
        return KeyEventResult.ignored;
    }
  }

  /// 处理支持 KeyRepeat 的方向键（如在网格中按住快速移动）
  static KeyEventResult handleNavigationWithRepeat(
    KeyEvent event, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onSelect,
    bool blockUp = false,
    bool blockDown = false,
    bool blockLeft = false,
    bool blockRight = false,
  }) {
    // 处理 KeyDownEvent 和 KeyRepeatEvent
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        return blockUp ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowDown:
        if (onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        return blockDown ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowLeft:
        if (onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        return blockLeft ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowRight:
        if (onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        return blockRight ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        // 确认键不支持重复
        if (event is KeyDownEvent && onSelect != null) {
          onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      default:
        return KeyEventResult.ignored;
    }
  }
}

/// 通用的 TV 焦点容器
///
/// 自动处理边界导航逻辑，减少重复代码
class TvFocusScope extends StatelessWidget {
  /// 焦点模式
  final FocusPattern pattern;

  /// 子组件
  final Widget child;

  /// 焦点节点
  final FocusNode? focusNode;

  /// 是否自动获取焦点
  final bool autofocus;

  /// 焦点变化回调
  final ValueChanged<bool>? onFocusChange;

  /// 确认键回调
  final VoidCallback? onSelect;

  /// 退出方向的目标焦点节点
  final FocusNode? exitUp;
  final FocusNode? exitDown;
  final FocusNode? exitLeft;
  final FocusNode? exitRight;

  /// 退出方向的回调（优先级高于 exitXxx FocusNode）
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;
  final VoidCallback? onExitLeft;
  final VoidCallback? onExitRight;

  /// 是否是列表中的第一项（垂直模式阻止向上，水平模式阻止向左）
  final bool isFirst;

  /// 是否是列表中的最后一项（垂直模式阻止向下，水平模式阻止向右）
  final bool isLast;

  /// 是否支持按键重复（适用于快速滚动场景）
  final bool enableKeyRepeat;

  const TvFocusScope({
    super.key,
    required this.pattern,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.onSelect,
    this.exitUp,
    this.exitDown,
    this.exitLeft,
    this.exitRight,
    this.onExitUp,
    this.onExitDown,
    this.onExitLeft,
    this.onExitRight,
    this.isFirst = false,
    this.isLast = false,
    this.enableKeyRepeat = false,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final handler = enableKeyRepeat
        ? TvKeyHandler.handleNavigationWithRepeat
        : TvKeyHandler.handleNavigation;

    switch (pattern) {
      case FocusPattern.vertical:
        return handler(
          event,
          // 垂直模式使用方向性导航，避免 previous/next 跨区“串焦点”
          onUp: isFirst ? _getExitUpHandler() : () => _focusInDirection(node, TraversalDirection.up),
          onDown: isLast ? _getExitDownHandler() : () => _focusInDirection(node, TraversalDirection.down),
          onLeft: _getExitLeftHandler(),
          onRight: _getExitRightHandler(),
          onSelect: onSelect,
          blockUp: isFirst && exitUp == null && onExitUp == null,
          blockDown: isLast && exitDown == null && onExitDown == null,
        );

      case FocusPattern.horizontal:
        return handler(
          event,
          onUp: _getExitUpHandler(),
          onDown: _getExitDownHandler(),
          // 水平模式使用方向性导航，避免 previous/next 跨区“串焦点”
          onLeft: isFirst ? _getExitLeftHandler() : () => _focusInDirection(node, TraversalDirection.left),
          onRight: isLast ? _getExitRightHandler() : () => _focusInDirection(node, TraversalDirection.right),
          onSelect: onSelect,
          blockLeft: isFirst && exitLeft == null && onExitLeft == null,
          blockRight: isLast && exitRight == null && onExitRight == null,
        );

      case FocusPattern.grid:
        // 网格模式：显式回调优先；未配置回调时阻止默认焦点搜索，
        // 避免边界处焦点“漏出”当前页面/容器。
        final upHandler = _getExitUpHandler();
        final downHandler = _getExitDownHandler();
        final leftHandler = _getExitLeftHandler();
        final rightHandler = _getExitRightHandler();
        return handler(
          event,
          onUp: upHandler,
          onDown: downHandler,
          onLeft: leftHandler,
          onRight: rightHandler,
          onSelect: onSelect,
          blockUp: upHandler == null,
          blockDown: downHandler == null,
          blockLeft: leftHandler == null,
          blockRight: rightHandler == null,
        );
    }
  }

  /// 获取退出处理函数，如果没有配置则返回 null
  VoidCallback? _getExitUpHandler() {
    if (onExitUp != null) return _handleExitUp;
    if (exitUp != null) return _handleExitUp;
    return null;
  }

  VoidCallback? _getExitDownHandler() {
    if (onExitDown != null) return _handleExitDown;
    if (exitDown != null) return _handleExitDown;
    return null;
  }

  VoidCallback? _getExitLeftHandler() {
    if (onExitLeft != null) return _handleExitLeft;
    if (exitLeft != null) return _handleExitLeft;
    return null;
  }

  VoidCallback? _getExitRightHandler() {
    if (onExitRight != null) return _handleExitRight;
    if (exitRight != null) return _handleExitRight;
    return null;
  }

  void _handleExitUp() {
    if (onExitUp != null) {
      onExitUp!();
    } else {
      exitUp?.requestFocus();
    }
  }

  void _handleExitDown() {
    if (onExitDown != null) {
      onExitDown!();
    } else {
      exitDown?.requestFocus();
    }
  }

  void _handleExitLeft() {
    if (onExitLeft != null) {
      onExitLeft!();
    } else {
      exitLeft?.requestFocus();
    }
  }

  void _handleExitRight() {
    if (onExitRight != null) {
      onExitRight!();
    } else {
      exitRight?.requestFocus();
    }
  }

  void _focusInDirection(FocusNode node, TraversalDirection direction) {
    FocusTraversalGroup.of(node.context!).inDirection(node, direction);
  }
}

/// 简化版的垂直焦点列表项
///
/// 专为设置页面等垂直列表设计
class TvVerticalListItem extends StatelessWidget {
  final Widget child;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onSelect;
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool isFirst;
  final bool isLast;

  const TvVerticalListItem({
    super.key,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.onSelect,
    this.sidebarFocusNode,
    this.onMoveUp,
    this.onMoveDown,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.vertical,
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      onSelect: onSelect,
      exitLeft: sidebarFocusNode,
      onExitUp: isFirst ? onMoveUp : null,
      onExitDown: isLast ? onMoveDown : null,
      isFirst: isFirst,
      isLast: isLast,
      child: child,
    );
  }
}
