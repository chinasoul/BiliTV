import 'package:flutter/material.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../../../services/update_service.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
import '../widgets/setting_action_row.dart';
import '../widgets/setting_dropdown_row.dart';

class AboutSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const AboutSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  bool _isCheckingUpdate = false;
  String _currentVersion = '';
  final FocusNode _buttonFocusNode = FocusNode();

  // 自动检查间隔
  int _autoCheckInterval = 0;
  int _downloadSourcePreference = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final version = await UpdateService.getCurrentVersion();
    await UpdateService.init();
    if (mounted) {
      setState(() {
        _currentVersion = version;
        _autoCheckInterval = UpdateService.autoCheckInterval;
        _downloadSourcePreference = UpdateService.downloadSourcePreference;
      });
    }
  }

  String _buildVersionSubtitle() {
    final lastCheck = UpdateService.lastCheckTime;
    if (lastCheck == 0) return '当前版本: $_currentVersion';
    final timeAgo = SettingsService.formatTimestamp(lastCheck);
    return '当前版本: $_currentVersion  ｜ $timeAgo';
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isCheckingUpdate = true);

    final result = await UpdateService.checkForUpdate();

    if (!mounted) return;
    setState(
      () => _isCheckingUpdate = false,
    ); // checkForUpdate 内部已记录时间，刷新 UI 即显示

    if (result.error != null) {
      ToastUtils.show(
        context,
        result.error!,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    if (result.hasUpdate && result.updateInfo != null) {
      UpdateService.showUpdateDialog(
        context,
        result.updateInfo!,
        onUpdate: () {
          UpdateService.showDownloadProgress(context, result.updateInfo!);
        },
      );
    } else {
      ToastUtils.show(context, '已是最新版本');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingActionRow(
          label: '检查更新',
          value: _buildVersionSubtitle(),
          buttonLabel: _isCheckingUpdate ? '检查中...' : '检查',
          autofocus: true,
          focusNode: _buttonFocusNode,
          isFirst: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: _isCheckingUpdate ? null : _checkForUpdate,
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingDropdownRow<int>(
          label: '自动检查更新',
          subtitle: _autoCheckInterval > 0
              ? '每 $_autoCheckInterval 天检查一次，有新版本时弹窗提醒'
              : '已关闭',
          value: _autoCheckInterval,
          items: UpdateService.autoCheckOptions,
          itemLabel: (v) {
            final idx = UpdateService.autoCheckOptions.indexOf(v);
            return idx >= 0 ? UpdateService.autoCheckLabels[idx] : '$v天';
          },
          onChanged: (v) {
            if (v == null) return;
            setState(() => _autoCheckInterval = v);
            UpdateService.setAutoCheckInterval(v);
          },
          sidebarFocusNode: widget.sidebarFocusNode,
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingDropdownRow<int>(
          label: '下载源',
          subtitle: _downloadSourcePreference == 1
              ? '优先使用 ghfast/ghproxy 等国内代理，再回退直连'
              : '优先 GitHub 直连，若下载速度慢请切国内代理',
          value: _downloadSourcePreference,
          items: UpdateService.downloadSourceOptions,
          itemLabel: (v) {
            final idx = UpdateService.downloadSourceOptions.indexOf(v);
            return idx >= 0 ? UpdateService.downloadSourceLabels[idx] : '$v';
          },
          onChanged: (v) {
            if (v == null) return;
            setState(() => _downloadSourcePreference = v);
            UpdateService.setDownloadSourcePreference(v);
          },
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
        ),
      ],
    );
  }
}
