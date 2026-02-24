import 'package:flutter/material.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingToggleRow(
          label: '原生弹幕渲染优化',
          subtitleWidget: Text(
            '若弹幕卡顿可尝试开启',
            style: TextStyle(color: Colors.amber.shade300, fontSize: 12),
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
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setHideBottomDanmaku(!value);
            setState(() {});
          },
        ),
      ],
    );
  }
}
