import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import '../../../../services/device_info_service.dart';
import '../../../../config/app_style.dart';
import '../widgets/setting_action_row.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';

class DeviceInfoSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const DeviceInfoSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<DeviceInfoSettings> createState() => _DeviceInfoSettingsState();
}

class _DeviceInfoSettingsState extends State<DeviceInfoSettings> {
  final FocusNode _refreshFocusNode = FocusNode();
  late final List<FocusNode> _infoFocusNodes;
  bool _isLoading = true;
  Map<String, dynamic> _info = {};
  String _publicIp = '获取中...';

  // 彩蛋：连续点击系统版本行 7 次开启开发者选项
  int _tapCount = 0;
  DateTime _lastTapTime = DateTime(0);
  static const _tapThreshold = Duration(seconds: 2);
  static const _tapTarget = 7;

  @override
  void initState() {
    super.initState();
    _infoFocusNodes = List.generate(8, (_) => FocusNode()); // 8项（增加公网IP）
    _loadDeviceInfo();
  }

  @override
  void dispose() {
    _refreshFocusNode.dispose();
    for (final node in _infoFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    setState(() {
      _isLoading = true;
      _publicIp = '获取中...';
    });
    final info = await DeviceInfoService.getDeviceInfo();
    if (!mounted) return;
    setState(() => _info = info);
    await _fetchPublicIp();
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _fetchPublicIp() async {
    // 尝试多个 API，提高成功率
    final apis = [
      'https://api.ipify.org',
      'https://ifconfig.me/ip',
      'https://icanhazip.com',
    ];

    for (final api in apis) {
      try {
        final response = await http
            .get(Uri.parse(api))
            .timeout(const Duration(seconds: 5));
        if (!mounted) return;
        if (response.statusCode == 200) {
          final ip = response.body.trim();
          if (ip.isNotEmpty && RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) {
            setState(() => _publicIp = ip);
            return;
          }
        }
      } catch (e) {
        // 尝试下一个 API
      }
    }

    if (!mounted) return;
    setState(() => _publicIp = '获取失败');
  }

  String _valueOf(String key, {String fallback = '未知'}) {
    final v = _info[key];
    if (v == null) return fallback;
    if (v is List) return v.join(', ');
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime) > _tapThreshold) {
      _tapCount = 0;
    }
    _lastTapTime = now;
    _tapCount++;

    if (SettingsService.developerMode) {
      if (_tapCount == 1) {
        ToastUtils.show(context, '已处于开发者模式');
      }
      return;
    }

    final remaining = _tapTarget - _tapCount;
    if (remaining <= 0) {
      SettingsService.setDeveloperMode(true);
      ToastUtils.show(context, '已开启开发者选项');
      _tapCount = 0;
    } else if (remaining <= 3) {
      ToastUtils.show(context, '再点 $remaining 次开启开发者选项');
    }
  }

  Widget _buildInfoItem(
    int index,
    String label,
    String value, {
    VoidCallback? onSelect,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return TvFocusScope(
      pattern: FocusPattern.vertical,
      enableKeyRepeat: true,
      focusNode: _infoFocusNodes[index],
      exitLeft: widget.sidebarFocusNode,
      onExitUp: isFirst ? () => _refreshFocusNode.requestFocus() : null,
      isFirst: isFirst,
      isLast: isLast,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (!focused || !mounted) return;
        final ctx = _infoFocusNodes[index].context;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.2,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _infoFocusNodes[index].requestFocus();
                onSelect?.call();
              },
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.settingItemMinHeight,
                ),
                margin: EdgeInsets.only(
                  bottom: isLast ? 0 : AppSpacing.settingItemGap,
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
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isFocused
                              ? AppColors.primaryText
                              : AppColors.secondaryText,
                          fontSize: AppFonts.sizeMD,
                          fontWeight: AppFonts.medium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: AppFonts.sizeSM,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingActionRow(
          label: '本机信息',
          value: '查看当前设备的硬件与系统信息',
          buttonLabel: _isLoading ? '刷新中...' : '刷新',
          autofocus: true,
          focusNode: _refreshFocusNode,
          isFirst: true,
          isLast: false,
          onMoveUp: widget.onMoveUp,
          onMoveDown: () => _infoFocusNodes.first.requestFocus(),
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: _isLoading ? null : _loadDeviceInfo,
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        _buildInfoItem(
          0,
          '系统版本',
          'Android ${_valueOf('androidVersion')} (SDK ${_valueOf('sdkInt')})',
          onSelect: _onVersionTap,
          isFirst: true,
        ),
        _buildInfoItem(1, '设备名', _valueOf('model')),
        _buildInfoItem(2, '支持 ABI 列表', _valueOf('supportedAbis')),
        _buildInfoItem(3, 'CPU', _valueOf('arch')),
        _buildInfoItem(4, 'GPU', _valueOf('gpu')),
        _buildInfoItem(5, '网络', _valueOf('networkName')),
        _buildInfoItem(6, '内网 IP', _valueOf('ipAddress')),
        _buildInfoItem(7, '公网 IP', _publicIp, isLast: true),
      ],
    );
  }
}
