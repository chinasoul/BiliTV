import 'package:flutter/material.dart';
import '../../../../core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';
import 'value_picker_popup.dart';

/// 设置页操作按钮行组件
///
/// 使用统一的焦点管理系统，当有选项列表时弹出选择窗口
class SettingActionRow extends StatelessWidget {
  final String label;
  final String value;
  final String buttonLabel;
  final VoidCallback? onTap;
  final bool autofocus;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final FocusNode? focusNode;
  final bool isFirst;
  final bool isLast;
  final List<String>? optionLabels;
  final String? selectedOption;

  /// 当选项被选中时的回调（用于弹窗选择模式）
  final ValueChanged<String>? onOptionSelected;

  const SettingActionRow({
    super.key,
    required this.label,
    required this.value,
    required this.buttonLabel,
    required this.onTap,
    this.autofocus = false,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.focusNode,
    this.isFirst = false,
    this.isLast = false,
    this.optionLabels,
    this.selectedOption,
    this.onOptionSelected,
  });

  void _showPicker(BuildContext context) {
    if (optionLabels == null || optionLabels!.isEmpty) {
      onTap?.call();
      return;
    }

    ValuePickerOverlay.show<String>(
      context: context,
      title: label,
      items: optionLabels!,
      currentValue: selectedOption ?? optionLabels!.first,
      itemLabel: (s) => s,
      onSelected: (selectedValue) {
        if (onOptionSelected != null) {
          onOptionSelected!(selectedValue);
        } else {
          onTap?.call();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.vertical,
      enableKeyRepeat: true,
      focusNode: focusNode,
      autofocus: autofocus,
      exitLeft: sidebarFocusNode,
      onExitUp: isFirst ? onMoveUp : null,
      onExitDown: isLast ? onMoveDown : null,
      isFirst: isFirst,
      isLast: isLast,
      onSelect: () => _showPicker(context),
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
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
                        if (value.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: Colors.white38,
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
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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
                            buttonLabel,
                            style: TextStyle(
                              color: isFocused ? Colors.white : Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          if (optionLabels != null &&
                              optionLabels!.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.unfold_more,
                              size: 14,
                              color: isFocused ? Colors.white : Colors.white54,
                            ),
                          ],
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
