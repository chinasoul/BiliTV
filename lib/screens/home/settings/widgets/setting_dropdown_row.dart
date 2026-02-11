import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 设置页下拉选择行组件
///
/// 使用统一的焦点管理系统，支持左右键切换选项
class SettingDropdownRow<T> extends StatelessWidget {
  final String label;
  final String? subtitle;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final bool isFirst;
  final bool isLast;

  const SettingDropdownRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.isFirst = false,
    this.isLast = false,
  });

  void _nextValue() {
    final currentIndex = items.indexOf(value);
    final nextIndex = (currentIndex + 1) % items.length;
    onChanged(items[nextIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        // 处理左右键导航和值切换
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            sidebarFocusNode?.requestFocus();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowUp:
            if (isFirst && onMoveUp != null) {
              onMoveUp!();
              return KeyEventResult.handled;
            }
            return isFirst ? KeyEventResult.handled : KeyEventResult.ignored;

          case LogicalKeyboardKey.arrowDown:
            if (isLast && onMoveDown != null) {
              onMoveDown!();
              return KeyEventResult.handled;
            }
            return isLast ? KeyEventResult.handled : KeyEventResult.ignored;

          case LogicalKeyboardKey.arrowRight:
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
            _nextValue();
            return KeyEventResult.handled;

          default:
            return KeyEventResult.ignored;
        }
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isFocused
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isFocused
                  ? Border.all(color: const Color(0xFFfb7299), width: 2)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isFocused ? Colors.white : Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isFocused
                        ? const Color(0xFFfb7299)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        itemLabel(value),
                        style: TextStyle(
                          color: isFocused ? Colors.white : Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: isFocused ? Colors.white : Colors.white54,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
