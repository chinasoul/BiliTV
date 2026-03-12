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

## 3. "按键后展开"的栏目（面板）

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

## 8. 隧道播放模式与倍速兼容

### 8.1 背景

ExoPlayer 的隧道播放（Tunnel Mode）将解码帧直通显示硬件，绕过 Flutter PlatformView 合成层，是 TV 上保证流畅播放的关键。但隧道模式下 `setPlaybackSpeed()` 能否生效取决于设备 SoC 的 AudioTrack HAL 实现——部分设备会静默忽略非 1x 的速率设置。

### 8.2 运行时探测机制

由于 Android 没有 API 直接查询"隧道模式是否支持倍速"，采用**运行时探测 + 持久化缓存**策略：

1. 用户首次在隧道模式下切到非 1x 倍速时触发探测
2. `_probeTunnelSpeedSupport(speed)`：
   - 设好倍速后等待 ~1.2 秒
   - 对比 `position 推进量 / 墙钟时间` 计算实际播放速率
   - 与目标速率对比（±30% 容差）
3. 结果持久化到 `SharedPreferences`（`tunnel_speed_supported`），后续直接读缓存

### 8.3 自动切换流程

```
用户选择非 1x 倍速
  ├─ 隧道模式关闭 → 直接设速度，不做额外操作
  └─ 隧道模式开启
       ├─ 缓存 = true（设备支持）→ 直接设速度，保持隧道
       ├─ 缓存 = null（未知）→ 运行探测
       │    ├─ 探测通过 → 缓存 true，保持隧道
       │    └─ 探测失败 → 缓存 false，走下方降级
       └─ 缓存 = false（不支持）
            → 临时关闭隧道，重建播放器（保留进度），Toast 提示

用户切回 1x 倍速
  └─ 若隧道是因倍速被临时关闭的 → 恢复隧道，重建播放器
```

### 8.4 关键函数

| 函数 | 位置 | 职责 |
|------|------|------|
| `_probeTunnelSpeedSupport(speed)` | `player_action_mixin.dart` | 运行时探测隧道模式下倍速是否生效 |
| `_syncTunnelModeWithPlaybackSpeed(speed)` | `player_action_mixin.dart` | 根据探测/缓存结果决定是否关闭/恢复隧道 |
| `_rebuildCurrentPlaybackForTunnelModeChange()` | `player_action_mixin.dart` | 保留进度重建播放器（隧道开关变更后） |
| `selectPlaybackSpeedByIndex(index)` | `player_action_mixin.dart` | 倍速选择入口，触发上述流程 |
| `tunnelSpeedSupported` | `settings_service.dart` | 探测结果持久化缓存（`bool?`） |

### 8.5 状态变量

| 变量 | 位置 | 说明 |
|------|------|------|
| `tunnelModeTemporarilyDisabledForSpeed` | `player_state_mixin.dart` | 标记隧道是否因倍速被临时关闭 |
| `isSwitchingTunnelModeForSpeed` | `player_state_mixin.dart` | 防止重入的锁 |

## 9. 播放启动静音策略（防电流声）

### 9.1 背景

部分 Android TV 设备在隧道模式下 `ExoPlayer.prepare()` 期间，AudioTrack HAL 初始化时会输出一小段电流声 / 静电噪音。根因是隧道模式将解码器输出直连音频硬件，某些 SoC 在音频管线就绪前会向喇叭输出未初始化的音频数据。

### 9.2 修复方案

在 `VideoPlayer.java`（ExoPlayer 基类）中，采用 **init 阶段静音 + 首帧上屏恢复** 策略：

1. 构造函数中 `prepare()` 之前调用 `exoPlayer.setVolume(0f)`
2. 构造函数中注册一次性 `Player.Listener`，监听 `onRenderedFirstFrame` 回调
3. `play()` 首次调用时：
   - 若首帧已渲染（非隧道模式，`prepare()` 期间已上屏）→ 立即恢复音量
   - 若首帧未渲染（隧道模式，需等实际播放才渲染）→ 等待 `onRenderedFirstFrame` 回调恢复，同时启动 2s 兜底定时器
4. `onRenderedFirstFrame` 触发时取消兜底定时器并恢复音量
5. `setVolume()` 在静音期间仅更新 `targetVolume`，不写入 ExoPlayer
6. `dispose()` 时清除未执行的 Handler 回调，防止 use-after-release

#### 9.2.1 为什么不用固定延迟

原方案用固定 150ms 延迟恢复音量，但视频首帧在隧道模式下通常需要 200~400ms 才能上屏（取决于 SoC），导致"先出声音、后出画面"的音画不同步。改为 `onRenderedFirstFrame` 回调后，音量恢复时机自适应硬件速度，高端/低端设备均能音画同步。

#### 9.2.2 兜底定时器

2s 兜底覆盖 `onRenderedFirstFrame` 永不触发的边界情况（如纯音频流无视频轨）。正常视频播放中回调远早于 2s，兜底不会生效。

### 9.3 关键字段

| 字段 | 说明 |
|------|------|
| `targetVolume` | 用户/系统设定的目标音量（默认 1.0），静音期间暂存 |
| `initialMuted` | 是否处于初始静音期，首次 `play()` 后置 false |
| `firstFrameRendered` | 首帧是否已渲染上屏，由 `onRenderedFirstFrame` 回调置 true |
| `volumeFallbackRunnable` | 兜底恢复音量的定时任务，首帧回调触发后取消 |
| `disposed` | 防止 dispose 后 Handler 回调访问已释放的 ExoPlayer |

## 10. 维护建议

1. 改按钮行为：先改 `_activateControlButton()`，再核对 UI 图标与 `focusedButtonIndex` 顺序
2. 改进度条行为：统一在 `enter/adjust/commit/exitProgressBarMode` 一组函数内改
3. 改快进体验：优先看 `seekForward/seekBackward/_batchSeek/commitSeek`
4. 改返回键行为：只在 `onPopInvoked()` 与 `handleGlobalKeyEvent()` 收口
5. 隧道+倍速兼容：若需重置探测缓存（如用户换了设备固件），调用 `SettingsService.clearTunnelSpeedSupported()`

## 11. 近期修复（2026-03）

### 11.1 选集面板焦点"屏外不可见"修复

- 文件：`lib/screens/player/widgets/episode_panel.dart`
- 问题现象：
  - 某些长列表视频在打开分P/合集后，焦点项不在可视区内；
  - 继续上下移动时，焦点索引变化但屏幕内看不到焦点项。
- 根因：
  - `ListView.builder` 懒加载导致屏外 item 未构建，基于 `GlobalKey.currentContext` 的 `ensureVisible` 在目标未构建时失效；
  - 回退路径使用估算行高，且与全局文本缩放（`textScaler`）存在偏差，长列表下误差累积。
- 修复策略：
  1. 为列表设置 `itemExtent`，让滚动位置与索引一一对应；
  2. 使用 `index * itemExtent` 的确定性滚动计算，保证任意索引都能定位到可视区；
  3. 将 item 内部改为垂直居中布局，避免固定高度下文本偏移。

### 11.2 同类面板滚动策略统一

- `settings_panel.dart`、`live_settings_panel.dart`、`quality_picker_sheet.dart`、`value_picker_popup.dart` 的焦点滚动统一改为"按真实布局保证可见"策略，减少估算高度带来的偏移回归。
- `up_panel.dart` 与 `related_panel.dart` 保持既有基于真实 `RenderBox` 尺寸的可视区保护逻辑。

### 11.3 浅色模式适配（播放器相关）

- 目标：在 `ThemeMode.light` 下，播放器侧边面板与弹窗仍保持可读性与焦点可识别性，不出现"背景过深/文字过黑"。
- 颜色策略：
  1. 面板背景统一走 `SidePanelStyle.background`（内部根据主题返回自适应色）；
  2. 弹窗背景统一走 `AppColors.popupBackgroundAdaptive`；
  3. 文本统一优先使用语义色：`AppColors.primaryText / secondaryText / inactiveText / disabledText`；
  4. 焦点背景使用 `AppColors.navItemSelectedBackground`，避免浅色模式下过深遮罩。
- 已覆盖模块：
  - 评论面板/评论弹窗
  - 分P/合集面板、UP 主面板、更多视频面板、播放器设置面板
  - UP 空间弹窗（`up_space_popup`）
  - 画质选择弹窗、直播设置面板、设置值选择弹窗
- 特殊约定（重要）：
  - 对"固定深色背景"覆盖层（如监控面板、部分 HUD 文本），不能盲目套用浅色主题文本色；应使用固定浅色 token（如 `AppColors.textTertiary`）保证对比度。

### 11.4 画质选择与编码器回退逻辑重构

- 文件：`lib/screens/player/mixins/player_action_mixin.dart`、`lib/services/api/playback_api.dart`
- 问题现象：
  - 用户设定 1080P，播放某些视频时提示"未达到 1080P"自动降到 720P；
  - 但在播放器设置面板手动可以选到 1080P 并成功播放。
- 根因：
  - `initializePlayer()` 的双层重试循环**嵌套方向错误**：外层是编码器、内层是画质。当某编码器（如 AV1）硬解初始化失败时，`continue qualityLoop` 跳到了**同编码器的下一个更低画质**，而非同画质的下一个编码器，导致不必要的分辨率降级；
  - `isCodecInitError` 判断条件过宽，`ExoPlaybackException` 匹配了所有 ExoPlayer 异常，包括 `Source error`（网络/CDN 问题）。这类错误换编码器无意义，应走正常的重试→降画质路径；
  - "未达到 xxx"的 toast 在每次 API 返回时就弹出（播放器初始化前），重试过程中用户会看到多条重复提示；
  - `switchQuality()` 成功后未同步更新 `qualities` 列表，导致画质选择面板显示过时数据；
  - `playback_api.dart` 中 `candidateVideos` 的 fallback 排序方向反了，取到的是离目标最远而非最近的画质。
- 修复策略：

  1. **反转循环嵌套**——画质为外层、编码器为内层：
     ```
     for (qn in [120, 116, 112, 80, 64, 32, 16])  // 外层：全档位逐级降级
       for (codec in [auto, avc, hevc, av1])        // 内层：编码器回退
     ```
     同一画质先试完所有编码器，全部失败才降一档画质。

  2. **画质降级改为全档位逐级递减**——基于 `VideoQuality` 枚举过滤 `<= baseQn` 的所有档位，从高到低排列。强制将 `baseQn` 插入列表（用 `Set` 去重），防止 `baseQn` 不在枚举中（如 API 返回非标准 qn=74）时被跳过：
     ```dart
     final qualityFallbackList = <int>{
       baseQn,
       ...VideoQuality.values.map((q) => q.qn).where((qn) => qn <= baseQn),
     }.toList()
       ..sort((a, b) => b.compareTo(a));
     ```
     修复前 4K(120) 降级路径 `120→64→32→16` 会跳过 1080P；修复后为 `120→116→112→80→64→32→16`。

  3. **收窄 `isCodecInitError` 匹配**——排除 `Source error`：
     ```dart
     final isCodecInitError =
         err.contains('MediaCodecVideoRenderer') ||
         err.contains('Decoder init failed') ||
         err.contains('VideoCodec') ||
         (err.contains('ExoPlaybackException') &&
             !err.contains('Source error'));
     ```
     `Source error`（CDN 超时/403）走正常重试（2 次）→ 降画质路径；真正的解码器错误才 `continue codecLoop` 换编码器。

  4. **toast 延迟到播放成功后**——`isLoading = false` 之后才弹一次"未达到 xxx"，避免重试中途的重复提示。

  5. **`switchQuality()` 同步更新 `qualities`**——与 `switchEpisode()` 保持一致，切画质后刷新可用画质列表。

  6. **`candidateVideos` fallback 排序修正**——`(a - targetQn).abs().compareTo(...)` 升序排列，确保选取离目标最近的画质。

- 首包探测与降级路径裁剪（所有用户通用）：
  - 进入重试循环前，先用第一个编码器请求一次 API（探测请求），获取 `accept_quality` 列表；
  - 用 `accept_quality` 过滤 `qualityFallbackList`，只保留视频实际支持的档位（`acceptQnSet ∩ <= requestedQn`，降序），跳过视频根本没有的画质；
  - 若过滤结果为空，兜底保留原列表不变；
  - 探测响应直接复用给首个编码器+首个画质的组合，不额外多一次请求；
  - VIP 智能升级也集成在探测中：若视频最高画质 > 当前返回画质，自动重新请求升级。
  - 收益示例：用户默认 8K（qn=127），视频最高 1080P（accept_quality=[80,64,32,16]），裁剪后降级列表从 `127→120→116→112→80→64→32→16`（8 档）缩减为 `127→80→64→32→16`（5 档，其中 127 首次探测已复用），省去 120/116/112 各 4 编码器共 12 轮无谓尝试。

- 重试流程示意（baseQn=127，视频支持 [80,64,32,16]）：
  ```
  首包探测: qn=127, auto → API 返回 accept_quality=[80,64,32,16], currentQuality=80
  裁剪降级列表: [127, 80, 64, 32, 16] → 首包响应复用给 127+auto

  qn=127 (复用探测):
    auto+127 → 实际拿到 80 的流 → 成功 → 播放 1080P ✅

  若 qn=127 所有编码器失败:
    qn=80:
      auto+80 → 成功 → 播放 1080P ✅

  若所有 qn + 所有编码器都失败:
    CompatFallback → durl/mp4 qn=32
    toast: "加载不顺，已降至 480P，可稍后再试或在设置页调整解码器"
  ```

- 超时与降级保护：
  - 降级路径跳过 HDR/杜比视界/8K 等特殊档位（除非是 `baseQn` 本身），减少无效尝试。
  - 10 秒总超时硬上限：超过后直接跳出循环走 CompatFallback，避免大量组合让用户等太久。
  - CompatFallback 成功时 toast 提示用户当前状态和可选操作。
  - 设置页画质偏好副标题对 `qn>=112` 提示"画质越高起播可能越慢"，给高画质用户合理预期。

### 11.5 播放器画质选择面板显示大会员标签

- 文件：`lib/services/api/playback_api.dart`、`lib/screens/player/widgets/quality_picker_sheet.dart`
- 功能：在播放器内画质选择面板中，为需要大会员的画质档位显示"大会员"标签（与 B 站 Web 端一致）。
- 数据来源：
  - B 站 `playurl` API 返回的 `support_formats` 数组中，每个画质条目包含 `limit_watch_reason` 字段：
    - `0` = 无限制
    - `1` = 需大会员
  - 注意：该 API 的 `need_vip` / `need_login` 字段不可靠（各账号状态下均返回 `null`），不可使用。
- 实现：
  1. **API 层**（`playback_api.dart`）：解析 `support_formats`，按 `quality` 建 `Map<qn, limitReason>`，合并到 qualities map 的 `limitReason` 字段。DASH 和 Compat 两条路径均处理。
  2. **UI 层**（`quality_picker_sheet.dart`）：`_qualityTag()` 方法读取 `limitReason`，`== 1` 时返回 `"大会员"`，否则返回 `null`。标签以主题色小圆角背景渲染在画质名称右侧。
  3. 不禁用点击——用户仍可选择任意画质，切换失败时由播放器 toast 提示，避免误伤可播档位。
