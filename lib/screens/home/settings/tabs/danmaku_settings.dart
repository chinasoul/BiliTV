import 'package:flutter/material.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
import '../widgets/setting_action_row.dart';
import '../widgets/setting_toggle_row.dart';
import '../widgets/setting_dropdown_row.dart';

class DanmakuSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const DanmakuSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<DanmakuSettings> createState() => _DanmakuSettingsState();
}

class _DanmakuSettingsState extends State<DanmakuSettings> {
  // 透明度选项: 0.1 ~ 1.0
  static const List<double> _opacityOptions = [
    0.1,
    0.2,
    0.3,
    0.4,
    0.5,
    0.6,
    0.7,
    0.8,
    0.9,
    1.0,
  ];

  // 字体大小选项
  static const List<double> _fontSizeOptions = [
    10,
    12,
    14,
    16,
    17,
    18,
    20,
    24,
    28,
    32,
    40,
    50,
  ];

  // 速度选项: 4 ~ 20
  static const List<double> _speedOptions = [4, 6, 8, 10, 12, 14, 16, 18, 20];

  /// 找到列表中最接近的值
  T _closestValue<T extends num>(List<T> options, T value) {
    return options.reduce(
      (a, b) => (a - value).abs() < (b - value).abs() ? a : b,
    );
  }

  ButtonStyle _dialogActionStyle({required bool primary}) {
    return TextButton.styleFrom(
      foregroundColor: SettingsDialogStyle.actionForeground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha);
        }
        return Colors.transparent;
      }),
    );
  }

  Future<bool> _confirmResetDanmakuSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: SettingsDialogStyle.barrierColor,
      builder: (ctx) => AlertDialog(
        backgroundColor: SettingsDialogStyle.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('重置弹幕设置'),
        content: const Text('将恢复弹幕设置页的所有偏好为默认值，是否继续？'),
        actions: [
          TextButton(
            style: _dialogActionStyle(primary: false),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            autofocus: true,
            style: _dialogActionStyle(primary: true),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _resetDanmakuSettings() async {
    final confirmed = await _confirmResetDanmakuSettings();
    if (!confirmed) return;
    await SettingsService.resetDanmakuPreferences();
    if (!mounted) return;
    setState(() {});
    ToastUtils.show(context, '弹幕设置已重置');
  }

  @override
  Widget build(BuildContext context) {
    final baseSubtitleStyle = TextStyle(
      color: AppColors.inactiveText,
      fontSize: AppFonts.sizeSM,
      height: 1.45,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingToggleRow(
          label: '原生弹幕渲染优化',
          subtitleWidget: Text.rich(
            TextSpan(
              style: baseSubtitleStyle,
              children: [
                const TextSpan(text: '关闭为flutter模式，开启为原生模式，'),
                TextSpan(
                  text: '若卡顿可开启',
                  style: TextStyle(
                    color: Colors.amber.shade300,
                    fontSize: AppFonts.sizeSM,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          value: SettingsService.preferNativeDanmaku,
          autofocus: true,
          isFirst: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setPreferNativeDanmaku(value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 弹幕开关
        SettingToggleRow(
          label: '弹幕开关',
          subtitle: '全局默认值，视频内可单独调整',
          value: SettingsService.danmakuEnabled,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setDanmakuEnabled(value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 弹幕透明度
        SettingDropdownRow<double>(
          label: '弹幕透明度',
          subtitle: '按确定键弹出选择菜单',
          value: _closestValue(_opacityOptions, SettingsService.danmakuOpacity),
          items: _opacityOptions,
          itemLabel: (v) => '${(v * 100).toInt()}%',
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value != null) {
              await SettingsService.setDanmakuOpacity(value);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 弹幕字体大小
        SettingDropdownRow<double>(
          label: '弹幕字体大小',
          subtitle: '按确定键弹出选择菜单',
          value: _closestValue(
            _fontSizeOptions,
            SettingsService.danmakuFontSize,
          ),
          items: _fontSizeOptions,
          itemLabel: (v) => '${v.toInt()}',
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value != null) {
              await SettingsService.setDanmakuFontSize(value);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 弹幕占屏比
        SettingDropdownRow<double>(
          label: '弹幕占屏比',
          subtitle: '弹幕显示区域占屏幕的比例',
          value: SettingsService.danmakuArea,
          items: SettingsService.danmakuAreaOptions,
          itemLabel: (v) => SettingsService.danmakuAreaLabel(v),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value != null) {
              await SettingsService.setDanmakuArea(value);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 弹幕速度
        SettingDropdownRow<double>(
          label: '弹幕速度',
          subtitle: '数值越大弹幕滚动越慢',
          value: _closestValue(_speedOptions, SettingsService.danmakuSpeed),
          items: _speedOptions,
          itemLabel: (v) => '${v.toInt()}',
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value != null) {
              await SettingsService.setDanmakuSpeed(value);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 允许顶部悬停弹幕
        SettingToggleRow(
          label: '允许顶部悬停弹幕',
          subtitle: '关闭后不显示固定在顶部的弹幕',
          value: !SettingsService.hideTopDanmaku,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setHideTopDanmaku(!value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 允许底部悬停弹幕
        SettingToggleRow(
          label: '允许底部悬停弹幕',
          subtitle: '关闭后不显示固定在底部的弹幕',
          value: !SettingsService.hideBottomDanmaku,
          isLast: false,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setHideBottomDanmaku(!value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingActionRow(
          label: '重置本页设置',
          value: '恢复弹幕设置页的默认偏好',
          buttonLabel: '重置',
          onTap: _resetDanmakuSettings,
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
        ),
      ],
    );
  }
}
