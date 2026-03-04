import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
import '../../../../core/focus/focus_navigation.dart';
import '../widgets/setting_action_row.dart';
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
  List<int> _playerControlOrder = [];
  int _selectedControlOrderIndex = 0;
  bool _isControlDragging = false;
  List<FocusNode> _playerControlToggleFocusNodes = [];
  List<FocusNode> _playerControlOrderFocusNodes = [];

  static const Map<int, String> _playerControlLabels = {
    0: '播放',
    1: '评论',
    2: '选集',
    3: 'UP主',
    4: '更多',
    5: '设置',
    6: '监测',
    7: '互动',
    8: '循环',
    9: '详情',
    10: '关闭',
  };

  @override
  void initState() {
    super.initState();
    _loadPlayerControlSettings();
  }

  @override
  void dispose() {
    for (final node in _playerControlToggleFocusNodes) {
      node.dispose();
    }
    for (final node in _playerControlOrderFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _loadPlayerControlSettings() {
    for (final node in _playerControlToggleFocusNodes) {
      node.dispose();
    }
    for (final node in _playerControlOrderFocusNodes) {
      node.dispose();
    }
    _playerControlOrder = SettingsService.playerControlOrder;
    _selectedControlOrderIndex = 0;
    _isControlDragging = false;
    _playerControlToggleFocusNodes = List.generate(
      _playerControlOrder.length,
      (_) => FocusNode(),
    );
    _playerControlOrderFocusNodes = List.generate(
      _playerControlOrder.length,
      (_) => FocusNode(),
    );
  }

  ButtonStyle _dialogActionStyle({required bool primary}) {
    return TextButton.styleFrom(
      foregroundColor: AppColors.primaryText,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha);
        }
        return Colors.transparent;
      }),
    );
  }

  Future<bool> _confirmResetPlaybackSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: SettingsDialogStyle.barrierColor,
      builder: (ctx) => AlertDialog(
        backgroundColor: SettingsDialogStyle.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('重置播放设置'),
        content: const Text('将恢复播放设置页的所有偏好为默认值，是否继续？'),
        actions: [
          TextButton(
            style: _dialogActionStyle(primary: false),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            autofocus: true,
            style: _dialogActionStyle(primary: true),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _resetPlaybackSettings() async {
    final confirmed = await _confirmResetPlaybackSettings();
    if (!confirmed) return;
    await SettingsService.resetPlaybackPreferences();
    PaintingBinding.instance.imageCache.maximumSize =
        SettingsService.imageCacheMaxSize;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        SettingsService.imageCacheMaxBytes;
    if (!mounted) return;
    _loadPlayerControlSettings();
    setState(() {});
    ToastUtils.show(context, '播放设置已重置');
  }

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
      color: AppColors.inactiveText,
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

  Widget _buildPlayerControlSettingsSection() {
    final enabledOrder = _playerControlOrder
        .where((i) => SettingsService.isPlayerControlEnabled(i))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppSpacing.settingSectionTitlePadding,
          child: Text(
            '控制栏按钮显示 (确认键切换)',
            style: TextStyle(
              color: AppColors.inactiveText,
              fontSize: AppFonts.sizeMD,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _playerControlOrder.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final controlIndex = _playerControlOrder[index];
              final label = _playerControlLabels[controlIndex] ?? '$controlIndex';
              final isEnabled = SettingsService.isPlayerControlEnabled(
                controlIndex,
              );
              return TvFocusScope(
                pattern: FocusPattern.horizontal,
                focusNode: _playerControlToggleFocusNodes[index],
                isFirst: index == 0,
                isLast: index == _playerControlOrder.length - 1,
                exitLeft: widget.sidebarFocusNode,
                onSelect: () async {
                  final enabledNow = SettingsService.enabledPlayerControls;
                  if (isEnabled && enabledNow.length <= 1) {
                    ToastUtils.show(context, '至少保留一个按钮');
                    return;
                  }
                  await SettingsService.togglePlayerControl(
                    controlIndex,
                    !isEnabled,
                  );
                  if (!mounted) return;
                  setState(() {});
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () async {
                        final enabledNow = SettingsService.enabledPlayerControls;
                        if (isEnabled && enabledNow.length <= 1) {
                          ToastUtils.show(context, '至少保留一个按钮');
                          return;
                        }
                        await SettingsService.togglePlayerControl(
                          controlIndex,
                          !isEnabled,
                        );
                        if (!mounted) return;
                        setState(() {});
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isEnabled
                              ? SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha)
                              : AppColors.navItemSelectedBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: focused
                                ? AppColors.primaryText
                                : isEnabled
                                ? SettingsService.themeColor
                                : Colors.transparent,
                            width: focused ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isEnabled
                                ? AppColors.primaryText
                                : AppColors.inactiveText,
                            fontSize: AppFonts.sizeSM,
                            fontWeight: focused
                                ? FontWeight.bold
                                : AppFonts.regular,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: AppSpacing.settingSectionTitlePadding,
          child: Text(
            '控制栏按钮排序 (仅显示已启用)',
            style: TextStyle(
              color: AppColors.inactiveText,
              fontSize: AppFonts.sizeMD,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _isControlDragging ? '← → 移动位置，确认键固定' : '确认键选中，← → 移动',
            style: TextStyle(
              color: _isControlDragging
                  ? SettingsService.themeColor
                  : AppColors.inactiveText,
              fontSize: AppFonts.sizeSM,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: enabledOrder.isEmpty
              ? Center(
                  child: Text(
                    '请至少启用一个按钮',
                    style: TextStyle(
                      color: AppColors.inactiveText,
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: enabledOrder.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final controlIndex = enabledOrder[index];
                    final label =
                        _playerControlLabels[controlIndex] ?? '$controlIndex';
                    final isSelected = index == _selectedControlOrderIndex;

                    final focusNodeIndex = _playerControlOrder.indexOf(
                      controlIndex,
                    );
                    if (focusNodeIndex < 0 ||
                        focusNodeIndex >= _playerControlOrderFocusNodes.length) {
                      return const SizedBox.shrink();
                    }

                    return Focus(
                      focusNode: _playerControlOrderFocusNodes[focusNodeIndex],
                      onFocusChange: (focused) {
                        if (focused && !_isControlDragging) {
                          setState(() => _selectedControlOrderIndex = index);
                        }
                      },
                      onKeyEvent: (node, event) {
                        if (event is KeyUpEvent) return KeyEventResult.ignored;

                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter)) {
                          setState(() => _isControlDragging = !_isControlDragging);
                          return KeyEventResult.handled;
                        }

                        if (_isControlDragging) {
                          final fullIndex = _playerControlOrder.indexOf(
                            controlIndex,
                          );

                          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                              index > 0) {
                            final prevControl = enabledOrder[index - 1];
                            final prevFullIndex = _playerControlOrder.indexOf(
                              prevControl,
                            );
                            setState(() {
                              _playerControlOrder[fullIndex] = prevControl;
                              _playerControlOrder[prevFullIndex] = controlIndex;
                              _selectedControlOrderIndex = index - 1;
                            });
                            SettingsService.setPlayerControlOrder(
                              _playerControlOrder,
                            );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _playerControlOrderFocusNodes[prevFullIndex]
                                  .requestFocus();
                            });
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                              index < enabledOrder.length - 1) {
                            final nextControl = enabledOrder[index + 1];
                            final nextFullIndex = _playerControlOrder.indexOf(
                              nextControl,
                            );
                            setState(() {
                              _playerControlOrder[fullIndex] = nextControl;
                              _playerControlOrder[nextFullIndex] = controlIndex;
                              _selectedControlOrderIndex = index + 1;
                            });
                            SettingsService.setPlayerControlOrder(
                              _playerControlOrder,
                            );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _playerControlOrderFocusNodes[nextFullIndex]
                                  .requestFocus();
                            });
                            return KeyEventResult.handled;
                          }
                        }

                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _isControlDragging && isSelected
                                  ? SettingsService.themeColor
                                  : focused
                                  ? AppColors.navItemSelectedBackground
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: AppColors.primaryText,
                                fontWeight: focused
                                    ? FontWeight.bold
                                    : AppFonts.regular,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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
          label: '播放前显示视频详情',
          subtitle: '点击视频后先展示详情页，再手动开始播放',
          value: SettingsService.showVideoDetailBeforePlay,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setShowVideoDetailBeforePlay(value);
            setState(() {});
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
        _buildPlayerControlSettingsSection(),
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
          isLast: false,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (quality) async {
            if (quality != null) {
              await SettingsService.setPreferredQuality(quality);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingToggleRow(
          label: '左上角显示播放进度时间',
          subtitle: '显示格式：当前时间/总时长',
          value: SettingsService.showPlayerProgressTime,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setShowPlayerProgressTime(value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        SettingActionRow(
          label: '重置本页设置',
          value: '恢复播放设置页的默认偏好',
          buttonLabel: '重置',
          onTap: _resetPlaybackSettings,
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
        ),
      ],
    );
  }
}
