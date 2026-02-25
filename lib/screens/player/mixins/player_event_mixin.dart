import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../../services/settings_service.dart';
import '../widgets/settings_panel.dart';
import '../focus/player_focus_handler.dart';
import 'player_action_mixin.dart';

/// 播放器按键事件 Mixin
mixin PlayerEventMixin on PlayerActionMixin {
  void onPopInvoked(bool didPop, dynamic result) {
    if (didPop) return;

    // 检查是否返回键已经被 handleGlobalKeyEvent 处理过
    if (backKeyJustHandled) {
      backKeyJustHandled = false;
      return;
    }

    if (showSettingsPanel) {
      if (settingsMenuType != SettingsMenuType.main) {
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 0;
        });
        return;
      }
      setState(() {
        showSettingsPanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    if (showEpisodePanel) {
      setState(() {
        showEpisodePanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    // 关闭 UP主面板
    if (showUpPanel) {
      setState(() {
        showUpPanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    // 关闭更多视频面板
    if (showRelatedPanel) {
      setState(() {
        showRelatedPanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    // 关闭评论面板
    if (showCommentPanel) {
      setState(() {
        showCommentPanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    if (showActionButtons) {
      setState(() => showActionButtons = false);
      startHideTimer();
      return;
    }

    // 预览模式下按返回键取消预览
    if (isSeekPreviewMode) {
      cancelPreviewSeek();
      return;
    }

    // 控制栏显示时按返回键隐藏控制栏
    if (showControls) {
      setState(() => showControls = false);
      return;
    }

    final now = DateTime.now();
    if (lastBackPressed == null ||
        now.difference(lastBackPressed!) > const Duration(seconds: 2)) {
      lastBackPressed = now;
      ToastUtils.show(context, '再按一次返回键退出播放');
    } else {
      // 先移除监听再暂停，避免 pause 触发 UI 闪现暂停指示
      cancelPlayerListeners();
      videoController?.pause();
      Navigator.of(context).pop();
    }
  }

  KeyEventResult handleGlobalKeyEvent(FocusNode node, KeyEvent event) {
    // 处理 KeyUpEvent - 松开左右键时提交进度条调整
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        // 进度条模式：松手立即提交
        if (isProgressBarFocused && previewPosition != null) {
          commitProgress();
          return KeyEventResult.handled;
        }
        // 批量快进模式：不在 KeyUp 时提交，依赖定时器
        // 这样连续点击时不会每次都 seek，只有停止点击后才提交
        if (seekRepeatCount > 0) {
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    // 只处理 KeyDownEvent 和 KeyRepeatEvent
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // 设置面板
    if (showSettingsPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        if (settingsMenuType != SettingsMenuType.main) {
          setState(() {
            settingsMenuType = SettingsMenuType.main;
            focusedSettingIndex = 0;
          });
        } else {
          setState(() {
            showSettingsPanel = false;
            showControls = true;
          });
          startHideTimer();
        }
        return KeyEventResult.handled;
      }
      final result = handleSettingsKeyEvent(event);
      if (result == KeyEventResult.handled) {
        if (!showControls) setState(() => showControls = true);
        return KeyEventResult.handled;
      }
    }

    // 选集面板 - 使用 PlayerFocusHandler
    if (showEpisodePanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        _closeEpisodePanel();
        return KeyEventResult.handled;
      }
      final result = handleEpisodeKeyEvent(event);
      if (result == KeyEventResult.handled) {
        if (!showControls) setState(() => showControls = true);
        return KeyEventResult.handled;
      }
    }

    // UP主面板返回处理
    if (showUpPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        setState(() {
          showUpPanel = false;
          showControls = true;
        });
        startHideTimer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 相关视频面板返回处理
    if (showRelatedPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        setState(() {
          showRelatedPanel = false;
          showControls = true;
        });
        startHideTimer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 评论面板返回处理
    if (showCommentPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        setState(() {
          showCommentPanel = false;
          showControls = true;
        });
        startHideTimer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 点赞/投币/收藏按钮返回处理
    if (showActionButtons) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        setState(() => showActionButtons = false);
        startHideTimer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 控制栏显示时
    if (showControls) {
      return _handleControlsVisibleKeyEvent(event);
    } else {
      // 控制栏隐藏时
      return _handleControlsHiddenKeyEvent(event);
    }
  }

  /// 进度条模式的按键处理
  KeyEventResult _handleProgressBarKeyEvent(KeyEvent event) {
    final isPreviewMode =
        SettingsService.seekPreviewMode && videoshotData != null;

    // 普通模式：松开左右键时启动延迟跳转
    if (!isPreviewMode && event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (previewPosition != null && videoController != null) {
          // 取消之前的定时器，重新计时（500ms 让用户看清预览图）
          progressBarSeekTimer?.cancel();
          progressBarSeekTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted &&
                previewPosition != null &&
                videoController != null &&
                isProgressBarFocused) {
              videoController!.seekTo(previewPosition!);
              resetDanmakuIndex(previewPosition!);
              // 跳转后保持预览图显示一小段时间再消失
              Timer(const Duration(milliseconds: 200), () {
                if (mounted && isProgressBarFocused) {
                  setState(() => previewPosition = null);
                }
              });
            }
          });
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        // 左键快退 - 取消延迟跳转定时器
        progressBarSeekTimer?.cancel();
        startAdjustProgress(-5);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        // 右键快进 - 取消延迟跳转定时器
        progressBarSeekTimer?.cancel();
        startAdjustProgress(5);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        // 下键退出进度条模式，回到控制按钮
        progressBarSeekTimer?.cancel();
        _exitProgressBarModeNoSeek();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        // 确认键：立即跳转并退出
        progressBarSeekTimer?.cancel();
        exitProgressBarMode(commit: true);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.browserBack:
      case LogicalKeyboardKey.escape:
        // 返回键退出进度条模式并收起控制面板
        progressBarSeekTimer?.cancel();
        backKeyJustHandled = true;
        setState(() {
          isProgressBarFocused = false;
          previewPosition = null;
          showControls = false;
        });
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  /// 退出进度条模式但不跳转（下键用）
  void _exitProgressBarModeNoSeek() {
    setState(() {
      isProgressBarFocused = false;
      previewPosition = null;
    });
    startHideTimer();
  }

  /// 控制栏显示时的按键处理
  KeyEventResult _handleControlsVisibleKeyEvent(KeyEvent event) {
    // 进度条模式下的按键处理
    if (isProgressBarFocused) {
      return _handleProgressBarKeyEvent(event);
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // 控制栏显示时：空格键等同确认键，触发当前聚焦按钮
    if (event.logicalKey == LogicalKeyboardKey.space) {
      activateControlButton(focusedButtonIndex);
      return KeyEventResult.handled;
    }

    // 使用 PlayerFocusHandler 处理控制栏导航
    final nav = PlayerFocusHandler.handleControlsNavigation(
      event,
      currentIndex: focusedButtonIndex,
      maxIndex: 9,
      onSelect: activateControlButton,
      onProgressBar: enterProgressBarMode,
      onHide: () => setState(() => showControls = false),
    );

    if (nav.result == KeyEventResult.handled) {
      if (nav.newIndex != focusedButtonIndex) {
        setState(() => focusedButtonIndex = nav.newIndex);
        startHideTimer();
      }
      return KeyEventResult.handled;
    }

    // 返回键隐藏控制栏
    if (PlayerFocusHandler.isBackKey(event)) {
      if (event.logicalKey != LogicalKeyboardKey.escape) {
        backKeyJustHandled = true;
      }
      setState(() => showControls = false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 激活控制栏按钮
  void activateControlButton(int index) {
    switch (index) {
      case 0: // 播放/暂停
        togglePlayPause();
        break;
      case 1: // 评论
        setState(() {
          showSettingsPanel = false;
          showEpisodePanel = false;
          showUpPanel = false;
          showRelatedPanel = false;
          showCommentPanel = true;
          showActionButtons = false;
          hideTimer?.cancel();
        });
        break;
      case 2: // 选集
        ensureEpisodesLoaded(); // 按需加载完整集数列表
        setState(() {
          showSettingsPanel = false;
          showEpisodePanel = true;
          showUpPanel = false;
          showRelatedPanel = false;
          showCommentPanel = false;
          showActionButtons = false;
          hideTimer?.cancel();
        });
        break;
      case 3: // UP主
        setState(() {
          showSettingsPanel = false;
          showEpisodePanel = false;
          showUpPanel = true;
          showRelatedPanel = false;
          showCommentPanel = false;
          showActionButtons = false;
          hideTimer?.cancel();
        });
        break;
      case 4: // 更多视频
        setState(() {
          showSettingsPanel = false;
          showEpisodePanel = false;
          showUpPanel = false;
          showRelatedPanel = true;
          showCommentPanel = false;
          showActionButtons = false;
          hideTimer?.cancel();
        });
        break;
      case 5: // 设置
        setState(() {
          showSettingsPanel = true;
          showEpisodePanel = false;
          showUpPanel = false;
          showRelatedPanel = false;
          showCommentPanel = false;
          showActionButtons = false;
          hideTimer?.cancel();
        });
        break;
      case 6: // 视频数据实时监测
        setState(() {
          // 打开监测面板时，优先关闭侧栏/浮层，避免显示条件冲突。
          showSettingsPanel = false;
          showEpisodePanel = false;
          showUpPanel = false;
          showRelatedPanel = false;
          showCommentPanel = false;
          showActionButtons = false;
        });
        toggleStatsForNerds();
        startHideTimer(); // 重置隐藏定时器
        break;
      case 7: // 点赞/投币/收藏
        setState(() {
          showActionButtons = !showActionButtons;
        });
        startHideTimer(); // 重置隐藏定时器
        break;
      case 8: // 循环播放
        toggleLoopMode();
        startHideTimer(); // 重置隐藏定时器
        break;
      case 9: // 关闭视频
        Navigator.of(context).pop();
        break;
    }
  }

  /// 控制栏隐藏时的按键处理
  KeyEventResult _handleControlsHiddenKeyEvent(KeyEvent event) {
    // 如果处于预览模式，使用 PlayerFocusHandler 处理
    if (isSeekPreviewMode && previewPosition != null) {
      final result = PlayerFocusHandler.handleSeekPreviewNavigation(
        event,
        onSeekBackward: seekPreviewBackward,
        onSeekForward: seekPreviewForward,
        onConfirm: confirmPreviewSeek,
        onCancel: () {
          if (event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack) {
            backKeyJustHandled = true;
          }
          cancelPreviewSeek();
        },
      );
      if (result == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // 外接键盘：空格键切换播放/暂停
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      togglePlayPause();
      return KeyEventResult.handled;
    }

    // 上下键显示控制栏
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      toggleControls();
      return KeyEventResult.handled;
    }

    // 确认键播放/暂停
    if (PlayerFocusHandler.isSelectKey(event) && event is KeyDownEvent) {
      togglePlayPause();
      return KeyEventResult.handled;
    }

    // 左右键快退/快进 (支持按住重复触发)
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      seekBackward();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      seekForward();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 关闭选集面板
  void _closeEpisodePanel() {
    setState(() {
      showEpisodePanel = false;
      showControls = true;
    });
    startHideTimer();
  }

  /// 选集面板按键处理 - 使用 PlayerFocusHandler
  KeyEventResult handleEpisodeKeyEvent(KeyEvent event) {
    // 支持长按连续移动 (KeyRepeatEvent)
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final nav = PlayerFocusHandler.handleEpisodePanelNavigation(
      event,
      currentIndex: focusedEpisodeIndex,
      maxIndex: episodes.length - 1,
      onSelect: () {
        if (episodes.isNotEmpty) {
          final ep = episodes[focusedEpisodeIndex];
          if (isUgcSeason) {
            // 合集：通过 bvid 切换（会导航到新播放器）
            switchEpisode(0, targetBvid: ep['bvid']);
          } else {
            // 分P：通过 cid 切换
            switchEpisode(ep['cid']);
          }
        }
      },
      onClose: _closeEpisodePanel,
    );

    if (nav.result == KeyEventResult.handled) {
      if (nav.newIndex != focusedEpisodeIndex) {
        setState(() => focusedEpisodeIndex = nav.newIndex);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 设置面板按键处理 - 保持原有逻辑（有子菜单特殊处理）
  KeyEventResult handleSettingsKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    int maxIndex = _getSettingsMaxIndex();

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        focusedSettingIndex = (focusedSettingIndex - 1).clamp(0, maxIndex);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        focusedSettingIndex = (focusedSettingIndex + 1).clamp(0, maxIndex);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (settingsMenuType == SettingsMenuType.main) {
        setState(() {
          showSettingsPanel = false;
          showControls = true;
        });
        startHideTimer();
      } else if (settingsMenuType == SettingsMenuType.danmaku) {
        adjustDanmakuSetting(-1);
      } else if (settingsMenuType == SettingsMenuType.speed) {
        setState(() => settingsMenuType = SettingsMenuType.main);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (settingsMenuType == SettingsMenuType.main) {
        if (focusedSettingIndex == 1) {
          setState(() {
            settingsMenuType = SettingsMenuType.danmaku;
            focusedSettingIndex = 0;
          });
        } else if (focusedSettingIndex == 2) {
          setState(() {
            settingsMenuType = SettingsMenuType.speed;
            focusedSettingIndex = 0;
          });
        }
      } else if (settingsMenuType == SettingsMenuType.danmaku) {
        adjustDanmakuSetting(1);
      }
      return KeyEventResult.handled;
    }

    if (PlayerFocusHandler.isSelectKey(event)) {
      activateSetting();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (settingsMenuType == SettingsMenuType.main) {
        setState(() {
          showSettingsPanel = false;
          showControls = true;
        });
        startHideTimer();
      } else {
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 0;
        });
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 获取当前设置菜单的最大索引
  int _getSettingsMaxIndex() {
    switch (settingsMenuType) {
      case SettingsMenuType.main:
        return 2;
      case SettingsMenuType.danmaku:
        return 6;
      case SettingsMenuType.speed:
        return availableSpeeds.length - 1;
      default:
        return 0;
    }
  }
}
