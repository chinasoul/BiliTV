import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../services/device_info_service.dart';
import '../widgets/setting_action_row.dart';

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
    _infoFocusNodes = List.generate(15, (_) => FocusNode());
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
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: focused
                  ? Border.all(color: const Color(0xFF81C784), width: 2)
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
        const SizedBox(height: 16),
        _buildInfoItem(0, '平台', _valueOf('platform')),
        _buildInfoItem(
          1,
          '安卓版本',
          '${_valueOf('androidVersion')} (SDK ${_valueOf('sdkInt')})',
        ),
        _buildInfoItem(2, '系统架构', _valueOf('arch')),
        _buildInfoItem(3, 'CPU ABI', _valueOf('cpuAbi')),
        _buildInfoItem(4, '支持 ABI 列表', _valueOf('supportedAbis')),
        _buildInfoItem(5, 'GPU', _valueOf('gpu')),
        _buildInfoItem(6, 'OpenGL ES', _valueOf('glEsVersion')),
        _buildInfoItem(7, '设备型号', _valueOf('model')),
        _buildInfoItem(8, '厂商', _valueOf('manufacturer')),
        _buildInfoItem(9, '品牌', _valueOf('brand')),
        _buildInfoItem(10, '设备代号', _valueOf('device')),
        _buildInfoItem(11, '主板', _valueOf('board')),
        _buildInfoItem(12, '硬件标识', _valueOf('hardware')),
        _buildInfoItem(13, '产品名', _valueOf('product')),
        _buildInfoItem(14, '内核版本', _valueOf('kernel')),
      ],
    );
  }
}
