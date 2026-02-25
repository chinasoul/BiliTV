import 'package:flutter/material.dart';
import '../../../../core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 设置页开关行组件
///
/// 使用统一的焦点管理系统
class SettingToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? subtitleWidget; // 优先于 subtitle，支持富文本
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final bool isFirst;
  final bool isLast;
  final bool enabled;

  const SettingToggleRow({
    super.key,
    required this.label,
    this.subtitle,
    this.subtitleWidget,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
    this.focusNode,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.isFirst = false,
    this.isLast = false,
    this.enabled = true,
  });

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
      onSelect: enabled ? () => onChanged(!value) : () => onChanged(value),
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (enabled) onChanged(!value);
              },
              child: Opacity(
                opacity: enabled ? 1.0 : 0.5,
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ExcludeFocus(
                            child: Switch(
                              value: value,
                              onChanged: enabled ? onChanged : null,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              activeTrackColor: SettingsService.themeColor
                                  .withValues(alpha: 0.5),
                              thumbColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                if (states.contains(WidgetState.selected)) {
                                  return SettingsService.themeColor;
                                }
                                return Colors.grey;
                              }),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
