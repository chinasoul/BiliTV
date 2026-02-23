import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../../services/device_info_service.dart';
import '../../../../config/app_style.dart';
import '../widgets/setting_action_row.dart';
import 'package:bili_tv_app/services/settings_service.dart';

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
    setState(() {
      _info = info;
      _isLoading = false;
    });
    // 异步获取公网 IP
    _fetchPublicIp();
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

  Widget _buildInfoItem(int index, String label, String value) {
    return Focus(
      focusNode: _infoFocusNodes[index],
      onFocusChange: (focused) {
        if (!focused || !mounted) return;
        final context = _infoFocusNodes[index].context;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.2,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (index == 0) {
            _refreshFocusNode.requestFocus();
          } else {
            _infoFocusNodes[index - 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (index < _infoFocusNodes.length - 1) {
            _infoFocusNodes[index + 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.sidebarFocusNode != null) {
          widget.sidebarFocusNode!.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: AppSpacing.settingItemMinHeight,
            ),
            margin: const EdgeInsets.only(bottom: AppSpacing.settingItemGap),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppSpacing.settingItemVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: focused
                  ? Border.all(color: SettingsService.themeColor, width: 2)
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: focused ? Colors.white : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
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
          value: _isLoading ? '读取中...' : '查看当前设备的硬件与系统信息',
          buttonLabel: _isLoading ? '加载中...' : '刷新',
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
        // Android 版本 (SDK xx)
        _buildInfoItem(
          0,
          '系统版本',
          'Android ${_valueOf('androidVersion')} (SDK ${_valueOf('sdkInt')})',
        ),
        // 设备名
        _buildInfoItem(1, '设备名', _valueOf('model')),
        // 支持 ABI 列表
        _buildInfoItem(2, '支持 ABI 列表', _valueOf('supportedAbis')),
        // CPU
        _buildInfoItem(3, 'CPU', _valueOf('arch')),
        // GPU
        _buildInfoItem(4, 'GPU', _valueOf('gpu')),
        // 网络名
        _buildInfoItem(5, '网络', _valueOf('networkName')),
        // 内网 IP 地址
        _buildInfoItem(6, '内网 IP', _valueOf('ipAddress')),
        // 公网 IP 地址
        _buildInfoItem(7, '公网 IP', _publicIp),
      ],
    );
  }
}
