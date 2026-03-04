import 'package:flutter/material.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
import '../widgets/setting_action_row.dart';

class StorageSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const StorageSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  static const Map<FocusedTitleDisplayMode, String> _modeSubtitles = {
    FocusedTitleDisplayMode.normal: '标题文字静态显示，超出部分省略',
    FocusedTitleDisplayMode.singleScroll: '标题文字滚动一次',
    FocusedTitleDisplayMode.loopScroll: '标题文字持续滚动',
  };

  double _cacheSizeMB = 0;
  bool _isClearing = false;
  FocusedTitleDisplayMode _focusedTitleDisplayMode =
      SettingsService.focusedTitleDisplayMode;
  final FocusNode _buttonFocusNode = FocusNode();
  final FocusNode _resetGlobalFocusNode = FocusNode();

  String get _focusedTitleModeSubtitle =>
      _modeSubtitles[_focusedTitleDisplayMode] ?? '';

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    _resetGlobalFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCacheSize() async {
    final size = await SettingsService.getImageCacheSizeMB();
    if (mounted) setState(() => _cacheSizeMB = size);
  }

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    await SettingsService.clearImageCache();
    await _loadCacheSize();
    if (mounted) {
      setState(() => _isClearing = false);
      ToastUtils.show(context, '缓存已清除');
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String content,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: SettingsDialogStyle.barrierColor,
      builder: (ctx) => AlertDialog(
        backgroundColor: SettingsDialogStyle.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: SettingsDialogStyle.actionForeground,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha);
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
              foregroundColor: SettingsDialogStyle.actionForeground,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha);
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

  Future<void> _resetAllPreferences() async {
    final confirmed = await _confirmAction(
      title: '全局重置偏好',
      content: '将重置全部偏好设置（不清理缓存与用户内容），是否继续？',
    );
    if (!confirmed) return;
    await SettingsService.resetAllPreferences();
    if (!mounted) return;
    setState(() {
      _focusedTitleDisplayMode = SettingsService.focusedTitleDisplayMode;
    });
    ToastUtils.show(context, '已重置全部偏好设置');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingActionRow(
          label: '视频卡片选中时标题显示方式',
          value: _focusedTitleModeSubtitle,
          buttonLabel: _focusedTitleDisplayMode.label,
          autofocus: true,
          isFirst: true,
          isLast: false,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          optionLabels: FocusedTitleDisplayMode.values
              .map((mode) => mode.label)
              .toList(),
          selectedOption: _focusedTitleDisplayMode.label,
          onTap: null,
          onOptionSelected: (selectedLabel) async {
            final selectedMode = FocusedTitleDisplayMode.values.firstWhere(
              (mode) => mode.label == selectedLabel,
              orElse: () => FocusedTitleDisplayMode.loopScroll,
            );
            await SettingsService.setFocusedTitleDisplayMode(selectedMode);
            if (!mounted) return;
            setState(() => _focusedTitleDisplayMode = selectedMode);
          },
        ),
        const SizedBox(height: 8),
        SettingActionRow(
          label: '清除图片缓存',
          value: '${_cacheSizeMB.toStringAsFixed(1)} MB',
          buttonLabel: _isClearing ? '清除中...' : '清除',
          autofocus: false,
          focusNode: _buttonFocusNode,
          isFirst: false,
          isLast: false,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: _isClearing ? null : _clearCache,
        ),
        const SizedBox(height: 8),
        SettingActionRow(
          label: '全局重置偏好',
          value: '重置全部偏好设置（不清理缓存与用户内容）',
          buttonLabel: '重置',
          autofocus: false,
          focusNode: _resetGlobalFocusNode,
          isFirst: false,
          isLast: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: _resetAllPreferences,
        ),
      ],
    );
  }
}
