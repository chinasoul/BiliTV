import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';
import 'value_picker_popup.dart';

/// 设置页下拉选择行组件
///
/// 使用统一的焦点管理系统，按确认键或右键弹出选择窗口
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

  void _showPicker(BuildContext context) {
    ValuePickerOverlay.show<T>(
      context: context,
      title: label,
      items: items,
      currentValue: value,
      itemLabel: itemLabel,
      onSelected: (selectedValue) {
        onChanged(selectedValue);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        // 处理左右键导航和值切换
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            sidebarFocusNode?.requestFocus();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowUp:
            if (isFirst && onMoveUp != null) {
              onMoveUp!();
              return KeyEventResult.handled;
            }
            if (isFirst) return KeyEventResult.handled;
            FocusTraversalGroup.of(node.context!).inDirection(
              node,
              TraversalDirection.up,
            );
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowDown:
            if (isLast && onMoveDown != null) {
              onMoveDown!();
              return KeyEventResult.handled;
            }
            if (isLast) return KeyEventResult.handled;
            FocusTraversalGroup.of(node.context!).inDirection(
              node,
              TraversalDirection.down,
            );
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowRight:
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
            // 防止长按确认反复弹窗
            if (event is KeyDownEvent) {
              _showPicker(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;

          default:
            return KeyEventResult.ignored;
        }
      },
      child: Builder(
        builder: (context) {
          final focusScope = Focus.of(context);
          final isFocused = focusScope.hasFocus;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showPicker(context),
              child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                minHeight: AppSpacing.settingItemMinHeight,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: AppSpacing.settingItemVerticalPadding,
              ),
              decoration: BoxDecoration(
                color: isFocused
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: isFocused ? Colors.white : Colors.white70,
                            fontSize: AppFonts.sizeMD,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: AppSpacing.settingItemRightHeight,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isFocused
                            ? SettingsService.themeColor
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
                            Icons.unfold_more,
                            size: 16,
                            color: isFocused ? Colors.white : Colors.white54,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  }
}
