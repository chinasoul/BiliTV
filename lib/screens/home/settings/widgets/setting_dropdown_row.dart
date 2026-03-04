import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';
import 'value_picker_popup.dart';

/// 设置页下拉选择行组件
///
/// 使用统一的焦点管理系统，按确认键或右键弹出选择窗口
class SettingDropdownRow<T> extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? subtitleWidget; // 优先于 subtitle，支持富文本
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final Widget Function(T item, bool isFocused, bool isSelected)?
  pickerItemBuilder;
  final ValueChanged<T?> onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final bool isFirst;
  final bool isLast;

  const SettingDropdownRow({
    super.key,
    required this.label,
    this.subtitle,
    this.subtitleWidget,
    required this.value,
    required this.items,
    required this.itemLabel,
    this.pickerItemBuilder,
    required this.onChanged,
    this.autofocus = false,
    this.focusNode,
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
      itemBuilder: pickerItemBuilder,
      onSelected: (selectedValue) {
        onChanged(selectedValue);
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
                      ? AppColors.navItemSelectedBackground
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
                              color: isFocused
                                  ? AppColors.primaryText
                                  : AppColors.secondaryText,
                              fontSize: AppFonts.sizeMD,
                              fontWeight: AppFonts.medium,
                            ),
                          ),
                          if (subtitleWidget != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: subtitleWidget!,
                            )
                          else if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
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
                    ),
                    SizedBox(
                      height: AppSpacing.settingItemRightHeight,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isFocused
                              ? SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha)
                              : AppColors.navItemSelectedBackground,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              itemLabel(value),
                              style: TextStyle(
                                color: isFocused
                                    ? AppColors.primaryText
                                    : AppColors.secondaryText,
                                fontSize: AppFonts.sizeMD,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.unfold_more,
                              size: 16,
                              color: isFocused
                                  ? AppColors.primaryText
                                  : AppColors.inactiveText,
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
