import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    _infoFocusNodes = List.generate(16, (_) => FocusNode());
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
    setState(() => _isLoading = true);
    final info = await DeviceInfoService.getDeviceInfo();
    if (!mounted) return;
    setState(() {
      _info = info;
      _isLoading = false;
    });
  }

  String _buildRamValue() {
    final totalMb = _info['totalRamMb'];
    final availMb = _info['availRamMb'];
    if (totalMb == null) return '未知';
    final totalGb = (totalMb as int) / 1024;
    final availGb = (availMb as int) / 1024;
    return '总共 ${totalGb.toStringAsFixed(1)} GB，可用 ${availGb.toStringAsFixed(1)} GB';
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
            constraints: const BoxConstraints(minHeight: AppSpacing.settingItemMinHeight),
            margin: const EdgeInsets.only(bottom: AppSpacing.settingItemGap),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.settingItemVerticalPadding),
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
        _buildInfoItem(0, '平台', _valueOf('platform')),
        _buildInfoItem(
          1,
          '安卓版本',
          '${_valueOf('androidVersion')} (SDK ${_valueOf('sdkInt')})',
        ),
        _buildInfoItem(2, '运行内存', _buildRamValue()),
        _buildInfoItem(3, '系统架构', _valueOf('arch')),
        _buildInfoItem(4, 'CPU ABI', _valueOf('cpuAbi')),
        _buildInfoItem(5, '支持 ABI 列表', _valueOf('supportedAbis')),
        _buildInfoItem(6, 'GPU', _valueOf('gpu')),
        _buildInfoItem(7, 'OpenGL ES', _valueOf('glEsVersion')),
        _buildInfoItem(8, '设备型号', _valueOf('model')),
        _buildInfoItem(9, '厂商', _valueOf('manufacturer')),
        _buildInfoItem(10, '品牌', _valueOf('brand')),
        _buildInfoItem(11, '设备代号', _valueOf('device')),
        _buildInfoItem(12, '主板', _valueOf('board')),
        _buildInfoItem(13, '硬件标识', _valueOf('hardware')),
        _buildInfoItem(14, '产品名', _valueOf('product')),
        _buildInfoItem(15, '内核版本', _valueOf('kernel')),
      ],
    );
  }
}
