import 'package:flutter/material.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
import '../widgets/setting_action_row.dart';
import '../widgets/setting_toggle_row.dart';
import '../widgets/setting_dropdown_row.dart';

class DeveloperSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const DeveloperSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<DeveloperSettings> createState() => _DeveloperSettingsState();
}

class _DeveloperSettingsState extends State<DeveloperSettings> {
  bool _developerMode = true;
  bool _showMemoryInfo = false;
  bool _showAppCpu = false;
  bool _showCoreFreq = false;
  bool _marquee60fps = true;
  double _nativeDanmakuStrokeWidth = 1.9;
  int _nativeDanmakuStrokeAlphaMin = 165;
  double _commentFocusAlpha = 0.05;
  double _videoCardOverlayAlpha = 0.90;

  static const List<double> _nativeDanmakuStrokeWidthOptions = [
    1.2,
    1.4,
    1.6,
    1.8,
    1.9,
    2.0,
    2.2,
    2.4,
    2.6,
    2.8,
    3.0,
  ];
  static const List<int> _nativeDanmakuStrokeAlphaMinOptions = [
    120,
    130,
    140,
    150,
    160,
    165,
    170,
    180,
    190,
    200,
    210,
    220,
  ];
  static const List<double> _commentFocusAlphaOptions = [
    0.03,
    0.05,
    0.07,
    0.10,
    0.12,
    0.15,
    0.18,
    0.20,
    0.24,
    0.30,
  ];
  static const List<double> _videoCardOverlayAlphaOptions = [
    0.50,
    0.60,
    0.70,
    0.80,
    0.85,
    0.90,
    0.95,
    1.00,
  ];

  final FocusNode _devToggleFocusNode = FocusNode();
  final FocusNode _memoryToggleFocusNode = FocusNode();
  final FocusNode _appCpuToggleFocusNode = FocusNode();
  final FocusNode _coreFreqToggleFocusNode = FocusNode();
  final FocusNode _fpsToggleFocusNode = FocusNode();
  final FocusNode _nativeStrokeWidthFocusNode = FocusNode();
  final FocusNode _nativeStrokeAlphaFocusNode = FocusNode();
  final FocusNode _commentFocusAlphaFocusNode = FocusNode();
  final FocusNode _videoCardOverlayAlphaFocusNode = FocusNode();
  final FocusNode _resetFocusNode = FocusNode();

  T _closestValue<T extends num>(List<T> options, T value) {
    return options.reduce(
      (a, b) => (a - value).abs() < (b - value).abs() ? a : b,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadFromSettings();
  }

  void _loadFromSettings() {
    _developerMode = SettingsService.developerMode;
    _showMemoryInfo = SettingsService.showMemoryInfo;
    _showAppCpu = SettingsService.showAppCpu;
    _showCoreFreq = SettingsService.showCoreFreq;
    _marquee60fps = SettingsService.marqueeFps == 60;
    _nativeDanmakuStrokeWidth = _closestValue(
      _nativeDanmakuStrokeWidthOptions,
      SettingsService.nativeDanmakuStrokeWidth,
    );
    _nativeDanmakuStrokeAlphaMin = _closestValue(
      _nativeDanmakuStrokeAlphaMinOptions,
      SettingsService.nativeDanmakuStrokeAlphaMin,
    );
    _commentFocusAlpha = _closestValue(
      _commentFocusAlphaOptions,
      SettingsService.commentFocusAlpha,
    );
    _videoCardOverlayAlpha = _closestValue(
      _videoCardOverlayAlphaOptions,
      SettingsService.videoCardOverlayAlpha,
    );
  }

  @override
  void dispose() {
    _devToggleFocusNode.dispose();
    _memoryToggleFocusNode.dispose();
    _appCpuToggleFocusNode.dispose();
    _coreFreqToggleFocusNode.dispose();
    _fpsToggleFocusNode.dispose();
    _nativeStrokeWidthFocusNode.dispose();
    _nativeStrokeAlphaFocusNode.dispose();
    _commentFocusAlphaFocusNode.dispose();
    _videoCardOverlayAlphaFocusNode.dispose();
    _resetFocusNode.dispose();
    super.dispose();
  }

  Future<bool> _confirmResetDeveloperSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('重置开发者选项'),
        content: const Text('将恢复开发者选项页的所有偏好为默认值，是否继续？'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return SettingsService.themeColor.withValues(alpha: 0.3);
                }
                return Colors.transparent;
              }),
            ),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            autofocus: true,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return SettingsService.themeColor.withValues(alpha: 0.3);
                }
                return Colors.transparent;
              }),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _resetDeveloperSettings() async {
    final confirmed = await _confirmResetDeveloperSettings();
    if (!confirmed) return;
    await SettingsService.resetDeveloperPreferences();
    if (!mounted) return;
    setState(_loadFromSettings);
    ToastUtils.show(context, '开发者选项已重置');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 开发者选项总开关
        SettingToggleRow(
          label: '开发者选项',
          subtitle: '关闭后此页面将隐藏，需重新在本机信息中触发',
          value: _developerMode,
          autofocus: true,
          focusNode: _devToggleFocusNode,
          isFirst: true,
          onMoveUp: widget.onMoveUp,
          onMoveDown: () => _memoryToggleFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) {
            setState(() => _developerMode = v);
            SettingsService.setDeveloperMode(v);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 2. 显示 CPU/内存信息
        SettingToggleRow(
          label: '显示CPU/内存信息',
          subtitle: '左下角显示占用率和内存',
          value: _showMemoryInfo,
          focusNode: _memoryToggleFocusNode,
          onMoveUp: () => _devToggleFocusNode.requestFocus(),
          onMoveDown: () => _appCpuToggleFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) {
            setState(() => _showMemoryInfo = v);
            SettingsService.setShowMemoryInfo(v);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 3. 显示 APP 占用率
        SettingToggleRow(
          label: '显示APP占用率',
          subtitle: '额外显示进程CPU整机百分比',
          value: _showAppCpu,
          focusNode: _appCpuToggleFocusNode,
          onMoveUp: () => _memoryToggleFocusNode.requestFocus(),
          onMoveDown: () => _coreFreqToggleFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) {
            setState(() => _showAppCpu = v);
            SettingsService.setShowAppCpu(v);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 4. 显示核心频率
        SettingToggleRow(
          label: '显示核心频率',
          subtitle: '额外显示各CPU核心当前频率',
          value: _showCoreFreq,
          focusNode: _coreFreqToggleFocusNode,
          onMoveUp: () => _appCpuToggleFocusNode.requestFocus(),
          onMoveDown: () => _fpsToggleFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) {
            setState(() => _showCoreFreq = v);
            SettingsService.setShowCoreFreq(v);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 5. 滚动文字帧率
        SettingToggleRow(
          label: '滚动文字60帧',
          subtitle: '关闭后降至30帧，减少CPU占用',
          value: _marquee60fps,
          focusNode: _fpsToggleFocusNode,
          onMoveUp: () => _coreFreqToggleFocusNode.requestFocus(),
          onMoveDown: () => _nativeStrokeWidthFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) {
            setState(() => _marquee60fps = v);
            SettingsService.setMarqueeFps(v ? 60 : 30);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 6. 原生弹幕描边宽度
        SettingDropdownRow<double>(
          label: '原生弹幕描边宽度',
          subtitle: '仅原生弹幕模式生效，值越大描边越粗',
          value: _nativeDanmakuStrokeWidth,
          items: _nativeDanmakuStrokeWidthOptions,
          itemLabel: (v) => v.toStringAsFixed(1),
          focusNode: _nativeStrokeWidthFocusNode,
          onMoveUp: () => _fpsToggleFocusNode.requestFocus(),
          onMoveDown: () => _nativeStrokeAlphaFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _nativeDanmakuStrokeWidth = value);
            await SettingsService.setNativeDanmakuStrokeWidth(value);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),

        // 7. 原生弹幕描边最小 alpha
        SettingDropdownRow<int>(
          label: '原生弹幕描边最小Alpha',
          subtitle: '仅原生弹幕模式生效，值越大描边越深',
          value: _nativeDanmakuStrokeAlphaMin,
          items: _nativeDanmakuStrokeAlphaMinOptions,
          itemLabel: (v) => '$v',
          focusNode: _nativeStrokeAlphaFocusNode,
          isLast: false,
          onMoveUp: () => _nativeStrokeWidthFocusNode.requestFocus(),
          onMoveDown: () => _commentFocusAlphaFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _nativeDanmakuStrokeAlphaMin = value);
            await SettingsService.setNativeDanmakuStrokeAlphaMin(value);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingDropdownRow<double>(
          label: '评论聚焦背景透明度',
          subtitle: '评论项聚焦时的主题色背景强度，值越大越深',
          value: _commentFocusAlpha,
          items: _commentFocusAlphaOptions,
          itemLabel: (v) => v.toStringAsFixed(2),
          focusNode: _commentFocusAlphaFocusNode,
          isLast: false,
          onMoveUp: () => _nativeStrokeAlphaFocusNode.requestFocus(),
          onMoveDown: () => _videoCardOverlayAlphaFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _commentFocusAlpha = value);
            await SettingsService.setCommentFocusAlpha(value);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingDropdownRow<double>(
          label: '视频卡片遮罩透明度',
          subtitle: '视频/直播/历史卡片底部渐变遮罩强度，值越大越深',
          value: _videoCardOverlayAlpha,
          items: _videoCardOverlayAlphaOptions,
          itemLabel: (v) => v.toStringAsFixed(2),
          focusNode: _videoCardOverlayAlphaFocusNode,
          isLast: false,
          onMoveUp: () => _commentFocusAlphaFocusNode.requestFocus(),
          onMoveDown: () => _resetFocusNode.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value == null) return;
            setState(() => _videoCardOverlayAlpha = value);
            await SettingsService.setVideoCardOverlayAlpha(value);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingActionRow(
          label: '重置本页设置',
          value: '恢复开发者选项页的默认偏好',
          buttonLabel: '重置',
          onTap: _resetDeveloperSettings,
          focusNode: _resetFocusNode,
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
        ),
      ],
    );
  }
}
