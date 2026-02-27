# 视频播放流程与控制逻辑备忘

本文档覆盖播放器的主流程、控制面板全部按键、展开面板、进度条交互、快进快退策略。

## 1. 主流程（从进入播放器到开始播放）

- 入口：`lib/screens/player/player_screen.dart`
  - `PlayerScreen` + `_PlayerScreenState`
  - 使用 `PlayerStateMixin` / `PlayerActionMixin` / `PlayerEventMixin`
- 初始化主线在 `lib/screens/player/mixins/player_action_mixin.dart` 的 `initializePlayer()`
  1. 拉取视频信息、确定 `cid`（含历史与缓存回退）
  2. 并行加载 videoshot（用于预览快进模式）
  3. 编码与清晰度回退组合尝试（含 VIP 场景）
  4. 创建并初始化 `VideoPlayerController`
  5. 绑定监听与定时器（状态同步、弹幕同步、在线人数等）
  6. 恢复播放进度（API/本地）并开始播放

## 2. 控制面板结构与按键功能

- 面板 UI：`lib/screens/player/widgets/controls_overlay.dart`
- 共 10 个主按钮（`focusedButtonIndex`，0~9）：
  1. 播放/暂停
  2. 评论面板
  3. 选集面板
  4. UP 主面板
  5. 更多视频面板
  6. 设置面板
  7. Stats for Nerds 开关
  8. 点赞/投币/收藏区域开关
  9. 循环播放开关
  10. 关闭播放器
- 按键动作分发：`lib/screens/player/mixins/player_event_mixin.dart` 的 `_activateControlButton()`

## 3. “按键后展开”的栏目（面板）

- 评论：`showCommentPanel`
- 选集：`showEpisodePanel`（打开时 `ensureEpisodesLoaded()` 按需加载）
- UP 主：`showUpPanel`
- 更多视频：`showRelatedPanel`
- 设置：`showSettingsPanel`
- 点赞/投币/收藏：`showActionButtons`

核心状态在：`lib/screens/player/mixins/player_state_mixin.dart`  
关闭优先级与返回行为在：`lib/screens/player/mixins/player_event_mixin.dart` 的 `onPopInvoked()` / `handleGlobalKeyEvent()`

### 3.1 设置面板子栏目

- 面板组件：`lib/screens/player/widgets/settings_panel.dart`
- 菜单类型：`SettingsMenuType.main / danmaku / subtitle / speed`
- 主菜单项：画质、弹幕设置、字幕设置、倍速
- 弹幕子菜单：开关、透明度、字号、区域、速度、隐藏顶部、隐藏底部
- 字幕子菜单：开关、轨道选择（若当前视频提供多语言字幕）
- 倍速子菜单：0.5x~2.0x
- 导航处理：`handleSettingsKeyEvent()`

## 4. 进度条逻辑

- 控件：`lib/screens/player/widgets/tv_progress_bar.dart`
- 入口：控制栏显示时按上键 -> `enterProgressBarMode()`
- 状态：
  - `isProgressBarFocused`
  - `previewPosition`（预览目标位置）
- 方向键：
  - 左/右：`startAdjustProgress(-/+5)`，内部调用 `adjustProgress()`
  - 下：退出进度条模式但不跳转（`_exitProgressBarModeNoSeek()`）
  - 确认：`exitProgressBarMode(commit: true)` 立即提交
  - 返回：退出并隐藏控制栏
- KeyUp 行为：
  - 非预览模式下，左右松手后会走 500ms 延迟 seek（便于看清预览）

## 5. 快进/快退逻辑

- 入口函数：`seekForward()` / `seekBackward()`
- 两种模式：

### 5.1 预览模式（有 videoshot）

- 条件：`SettingsService.seekPreviewMode && videoshotData != null`
- 行为：
  - 暂停视频，仅更新 `previewPosition`
  - 步长 10s，并对齐到快照时间戳
  - 确认：`confirmPreviewSeek()` -> seek + 恢复播放
  - 取消：`cancelPreviewSeek()` -> 恢复播放并退出预览

### 5.2 默认批量 seek 模式

- 函数：`_batchSeek(forward: bool)` + `commitSeek()`
- 行为：
  - 首次 seek 先暂停，后续累积目标位置
  - 连续触发渐进加速（5s/10s/20s/40s/60s）
  - 停止操作 400ms 后自动提交
  - 提交后更新弹幕索引、隐藏旧缓冲条并显示 seek 指示

## 6. 控制栏/按键导航规则（播放器内）

- 全局按键入口：`handleGlobalKeyEvent()`
- 控制栏显示：
  - 左右在 10 个按钮间移动（`PlayerFocusHandler.handleControlsNavigation`）
  - 上进入进度条
  - 下隐藏控制栏
  - 确认触发当前按钮
- 控制栏隐藏：
  - 上/下唤起控制栏
  - 左/右触发快退/快进（支持 `KeyRepeatEvent`）
  - 确认播放/暂停

## 7. 关键定时器（理解时序必看）

- `hideTimer`：控制栏自动隐藏
- `danmakuSyncTimer`：弹幕同步
- `seekCommitTimer`：批量 seek 延迟提交（400ms）
- `progressBarSeekTimer`：进度条延迟跳转（500ms）
- `seekIndicatorTimer`：seek 指示自动隐藏
- `bufferHideTimer`：seek 后缓冲条延时恢复
- `statsTimer`：Stats for Nerds 指标刷新

## 8. 维护建议

1. 改按钮行为：先改 `_activateControlButton()`，再核对 UI 图标与 `focusedButtonIndex` 顺序
2. 改进度条行为：统一在 `enter/adjust/commit/exitProgressBarMode` 一组函数内改
3. 改快进体验：优先看 `seekForward/seekBackward/_batchSeek/commitSeek`
4. 改返回键行为：只在 `onPopInvoked()` 与 `handleGlobalKeyEvent()` 收口
