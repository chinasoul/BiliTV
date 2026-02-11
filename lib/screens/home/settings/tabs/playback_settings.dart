import 'package:flutter/material.dart';
import '../../../../services/settings_service.dart';
import '../../../../services/codec_service.dart';
import '../widgets/setting_toggle_row.dart';
import '../widgets/setting_dropdown_row.dart';

class PlaybackSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const PlaybackSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<PlaybackSettings> createState() => _PlaybackSettingsState();
}

class _PlaybackSettingsState extends State<PlaybackSettings> {
  List<String> _hardwareDecoders = [];

  @override
  void initState() {
    super.initState();
    _loadHardwareDecoders();
  }

  void _loadHardwareDecoders() async {
    final decoders = await CodecService.getHardwareDecoders();
    if (mounted) {
      setState(() {
        _hardwareDecoders = decoders;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingToggleRow(
          label: '自动连播',
          subtitle: '视频播完自动播放下一集或推荐视频',
          value: SettingsService.autoPlay,
          autofocus: true,
          isFirst: true, // 第一项，向上返回分类标签
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setAutoPlay(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        SettingToggleRow(
          label: '迷你进度条',
          subtitle: '播放时在屏幕底部显示简约进度条',
          value: SettingsService.showMiniProgress,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setShowMiniProgress(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        SettingToggleRow(
          label: '默认隐藏控制栏',
          subtitle: '打开视频时不显示控制栏和进度条',
          value: SettingsService.hideControlsOnStart,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setHideControlsOnStart(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        SettingToggleRow(
          label: '快进预览模式',
          subtitle: '快进快退时显示预览缩略图，按确定跳转',
          value: SettingsService.seekPreviewMode,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setSeekPreviewMode(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        SettingDropdownRow<VideoCodec>(
          label: '视频解码器',
          subtitle: '自动=按硬件支持选最优，失败时降级到其他格式',
          value: SettingsService.preferredCodec,
          items: VideoCodec.values.where((codec) {
            // 自动选项始终显示
            if (codec == VideoCodec.auto) return true;
            // 只显示硬件支持的编码器
            return _hardwareDecoders.contains(codec.name.toLowerCase());
          }).toList(),
          itemLabel: (codec) => codec.label,
          isLast: true, // 最后一项，阻止向下导航
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (codec) async {
            if (codec != null) {
              await SettingsService.setPreferredCodec(codec);
              setState(() {});
            }
          },
        ),
      ],
    );
  }
}
