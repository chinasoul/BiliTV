import 'package:flutter/material.dart';
import '../../../../core/focus/focus_navigation.dart';

/// 设置页开关行组件
///
/// 使用统一的焦点管理系统
class SettingToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final bool isFirst;
  final bool isLast;

  const SettingToggleRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
    this.focusNode,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.isFirst = false,
    this.isLast = false,
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
      onSelect: () => onChanged(!value),
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
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: const Color(
                    0xFFfb7299,
                  ).withValues(alpha: 0.5),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFfb7299);
                    }
                    return Colors.grey;
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
