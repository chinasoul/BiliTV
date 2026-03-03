import 'package:flutter/material.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
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
  String _buildCompletionActionDescription(PlaybackCompletionAction action) {
    switch (action) {
      case PlaybackCompletionAction.pause:
        return '暂停视频，停留在当前播放页';
      case PlaybackCompletionAction.exit:
        return '退出播放器并返回来源页面';
      case PlaybackCompletionAction.playNextEpisode:
        return '播放分P或合集的下一集，最后一集时暂停';
      case PlaybackCompletionAction.playRecommended:
        return '自动播放推荐视频';
    }
  }

  Widget _buildPerformanceModeDescription(PlaybackPerformanceMode mode) {
    final baseStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.55),
      fontSize: AppFonts.sizeSM,
      height: 1.45,
    );
    switch (mode) {
      case PlaybackPerformanceMode.high:
        return Text(
          '流畅优先：缓冲 50s，回看 30s，图片缓存 60 张，内存占用最高',
          style: baseStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case PlaybackPerformanceMode.medium:
        return Text(
          '均衡：缓冲 30s，回看 15s，图片缓存 40 张，流畅与内存平衡',
          style: baseStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case PlaybackPerformanceMode.low:
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              const TextSpan(
                text: '省内存：缓冲 15s，回看 0s，图片缓存 20 张，',
              ),
              TextSpan(
                text: '低内存设备推荐',
                style: TextStyle(
                  color: Colors.amber.shade300,
                  fontSize: AppFonts.sizeSM,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  String _buildQualitySubtitle(VideoQuality quality) {
    if (quality.qn >= 120) return '需要大会员，非大会员将自动降级';
    if (quality.qn >= 112) return '需要大会员或登录，未达条件将自动降级';
    return '每次打开视频时默认请求此画质';
  }

  @override
  Widget build(BuildContext context) {
    final performanceMode = SettingsService.playbackPerformanceMode;
    final completionAction = SettingsService.playbackCompletionAction;
    final preferredQuality = SettingsService.preferredQuality;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingDropdownRow<PlaybackPerformanceMode>(
          label: '播放性能模式',
          subtitleWidget: _buildPerformanceModeDescription(performanceMode),
          value: performanceMode,
          items: PlaybackPerformanceMode.values.toList(),
          itemLabel: (mode) => mode.label,
          autofocus: true,
          isFirst: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (mode) async {
            if (mode != null) {
              await SettingsService.setPlaybackPerformanceMode(mode);
              PaintingBinding.instance.imageCache.maximumSize =
                  SettingsService.imageCacheMaxSize;
              PaintingBinding.instance.imageCache.maximumSizeBytes =
                  SettingsService.imageCacheMaxBytes;
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingDropdownRow<PlaybackCompletionAction>(
          label: '播放完成后',
          subtitle: _buildCompletionActionDescription(completionAction),
          value: completionAction,
          items: PlaybackCompletionAction.values.toList(),
          itemLabel: (action) => action.label,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (action) async {
            if (action != null) {
              await SettingsService.setPlaybackCompletionAction(action);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
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
        const SizedBox(height: AppSpacing.settingItemGap),
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
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingToggleRow(
          label: '快进预览模式',
          subtitle: '快进快退时显示预览缩略图，按确定跳转（暂不可用）',
          value: SettingsService.seekPreviewMode,
          enabled: false,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            ToastUtils.show(context, '该功能暂不可用');
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingDropdownRow<VideoCodec>(
          label: '视频解码器',
          subtitle: 'H.264/HEVC/AV1 都可试；卡顿时换一种试试',
          value: SettingsService.preferredCodec,
          items: VideoCodec.values.toList(),
          itemLabel: (codec) => codec.label,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (codec) async {
            if (codec != null) {
              await SettingsService.setPreferredCodec(codec);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingToggleRow(
          label: '隧道播放模式',
          subtitle: '解码帧直通显示硬件，画面黑屏时请关闭（重启播放生效）',
          value: SettingsService.tunnelModeEnabled,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setTunnelModeEnabled(value);
            if (value) {
              await SettingsService.setTunnelModeHintShown(false);
            }
            setState(() {});
            ToastUtils.show(context, value ? '隧道播放已开启，下次播放生效' : '隧道播放已关闭，下次播放生效');
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingDropdownRow<VideoQuality>(
          label: '默认画质',
          subtitle: _buildQualitySubtitle(preferredQuality),
          value: preferredQuality,
          items: VideoQuality.values.toList(),
          itemLabel: (q) => q.label,
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (quality) async {
            if (quality != null) {
              await SettingsService.setPreferredQuality(quality);
              setState(() {});
            }
          },
        ),
      ],
    );
  }
}
