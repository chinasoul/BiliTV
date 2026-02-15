import 'package:flutter/material.dart';
import '../../../../core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 设置页操作按钮行组件
///
/// 使用统一的焦点管理系统
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
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.vertical,
      focusNode: focusNode,
      autofocus: autofocus,
      exitLeft: sidebarFocusNode,
      onExitUp: isFirst ? onMoveUp : null,
      onExitDown: isLast ? onMoveDown : null,
      isFirst: isFirst,
      isLast: isLast,
      onSelect: onTap,
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          Widget? optionChips;
          if (optionLabels != null && optionLabels!.isNotEmpty) {
            optionChips = Row(
              mainAxisSize: MainAxisSize.min,
              children: optionLabels!.map((opt) {
                final isSelected = opt == selectedOption;
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? SettingsService.themeColor.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? SettingsService.themeColor
                          : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Text(
                    opt,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            );
          }
          return Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.settingItemMinHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.settingItemVerticalPadding),
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
                          ),
                        ),
                    ],
                  ),
                ),
                if (optionChips != null) ...[optionChips],
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
                    child: Text(
                      buttonLabel,
                      style: TextStyle(
                        color: isFocused ? Colors.white : Colors.white70,
                        fontSize: 13,
                      ),
                    ),
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
