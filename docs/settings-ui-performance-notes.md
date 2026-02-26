# Settings UI 对齐与性能档位实现备忘

本文档用于记录本次 Settings 页面 UI 对齐、焦点策略统一、以及播放性能三档实现细节，避免后续重复排查。

## 1. Settings 行高对齐规则

目标：所有设置项视觉高度与交互区域保持一致（参考“界面设置 -> 默认启动页面”）。

- 统一使用组件内的“行内说明”能力，不在设置行外额外追加 `Text`。
- 行内说明必须单行：
  - `maxLines: 1`
  - `overflow: TextOverflow.ellipsis`
- 组件最小高度统一由 `AppSpacing.settingItemMinHeight` 控制。

结论：如果在设置行外再放说明文字，会导致该项总高度大于其他项，出现“看起来不对齐”。

## 2. Dropdown 组件能力统一

文件：`lib/screens/home/settings/widgets/setting_dropdown_row.dart`

本次统一后，`SettingDropdownRow` 与 `SettingToggleRow` / `SettingActionRow` 一致支持：

- `autofocus`
- `focusNode`
- `subtitle`（字符串）
- `subtitleWidget`（富文本，优先级高于 `subtitle`）

焦点导航使用 `TvFocusScope`，规则与其他设置行一致。

## 3. 两个关键设置项的正确实现方式

### 3.1 播放设置 -> 播放性能模式

文件：`lib/screens/home/settings/tabs/playback_settings.dart`

- “播放性能模式”放在第一项。
- 使用 `autofocus: true` 作为进入页面首焦点。
- 档位说明采用行内 `subtitle` 动态展示（随当前选项变化）。
- 不再在行外单独渲染说明文字。

### 3.2 界面设置 -> 标签页切换策略

文件：`lib/screens/home/settings/tabs/interface_settings.dart`

- 说明采用 `subtitleWidget` 动态展示（随当前选项变化）。
- `省内存` 档位保留黄字加粗“低内存设备推荐”。
- 整体仍保持单行省略，避免撑高。

## 4. 焦点参数常见误区

- `isFirst: true` 不是自动聚焦。
  - 含义：该项是列表第一项，按上键时触发 `onMoveUp`（导航边界行为）。
- `autofocus: true` 才是进入页面时首焦点行为。

## 5. 播放性能三档（已实现）

配置入口：`SettingsService.playbackPerformanceMode`

- High：缓冲更大，优先流畅。
- Medium：平衡。
- Low：优先省内存（更容易在弱网看到缓冲）。

关联实现：

- Flutter 侧
  - 弹幕同步间隔：`danmakuSyncInterval`
  - Stats 间隔：`statsInterval`（仅开启 Stats 时启动）
  - videoshot 预加载与预缓存策略
- Android ExoPlayer 侧
  - 根据 `flutter.playback_performance_mode` 动态配置 buffer/backBuffer
  - 注意读取 SharedPreferences 时用 `getLong` 再转 `int`

## 6. 已踩坑与修复结论

### 6.1 Dropdown 编译错误

报错：`No named parameter with the name 'autofocus'`

原因：`SettingDropdownRow` 当时未定义 `autofocus` 参数，但调用处传了该参数。

修复：为 `SettingDropdownRow` 增加 `autofocus` / `focusNode` 支持并统一到 `TvFocusScope`。

### 6.2 Android 偏好读取类型

风险：`shared_preferences` 的 int 在 Android 实际是 Long 存储。

修复：原生侧读取 `playback_performance_mode` 时改为：

- `(int) prefs.getLong("flutter.playback_performance_mode", 1L)`

避免始终回落默认值导致档位不生效。

## 7. 内存优化改动总清单（本次）

本节汇总本轮内存优化的实际代码改动，按“配置入口 -> 生效点 -> 影响范围”梳理，便于后续维护。

### 7.1 统一配置入口

核心入口：`设置 -> 播放设置 -> 播放性能模式（高/中/低）`

对应设置项：

- `SettingsService.playbackPerformanceMode`
- 存储 key：`playback_performance_mode`
- 默认值：`high`

### 7.2 播放器缓冲策略（三档联动）

生效文件：

- `packages/video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/platformview/PlatformViewVideoPlayer.java`
- `packages/video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/texture/TextureVideoPlayer.java`

关键点：

- 原生侧从 `FlutterSharedPreferences` 读取 `flutter.playback_performance_mode`
- 使用 `getLong` 读取并转 `int`，避免类型不匹配导致总是默认档
- 按三档设置 `minBufferMs / maxBufferMs / bufferForPlaybackMs / bufferForPlaybackAfterRebufferMs`
- Texture 模式额外联动 `backBufferDurationMs`（低档为 `0`）

### 7.3 Flutter 侧播放链路联动（三档）

生效文件：

- `lib/services/settings_service.dart`
- `lib/screens/player/mixins/player_action_mixin.dart`

联动项：

- `danmakuSyncInterval`：高/中/低分别为 `80ms / 120ms / 180ms`
- `statsInterval`：高/中/低分别为 `250ms / 500ms / 1000ms`
- `preloadVideoshotOnPlayerInit`：低档关闭初始化预加载
- `videoshotPreloadThreshold`：高/中/低分别为 `0.8 / 0.7 / 0.55`

实现要点：

- `danmakuSyncTimer` 改为读取 `SettingsService.danmakuSyncInterval`
- Stats 定时器改为仅在开启 Stats 面板时启动，并按 `statsInterval` 刷新
- `loadVideoshot` 增加参数，按档位控制“初始化阶段是否预加载”

### 7.4 图片解码缓存动态化（Phase 2）

生效文件：

- `lib/services/settings_service.dart`
- `lib/main.dart`
- `lib/screens/home/settings/tabs/playback_settings.dart`

改动内容：

- `imageCacheMaxSize` 从固定常量改为动态 getter  
  - 高：`60`
  - 中：`40`
  - 低：`20`
- `imageCacheMaxBytes` 从固定常量改为动态 getter  
  - 高：`30MB`
  - 中：`20MB`
  - 低：`10MB`

生效时机：

- 启动时：`main.dart` 先 `SettingsService.init()`，再应用 image cache 上限
- 运行时：在“播放性能模式”切换回调里即时刷新
  - `PaintingBinding.instance.imageCache.maximumSize`
  - `PaintingBinding.instance.imageCache.maximumSizeBytes`

### 7.5 BiliCacheManager 保守动态化（Phase 2）

生效文件：

- `lib/services/settings_service.dart`

改动内容：

- `BiliCacheManager` 的 `maxNrOfCacheObjects` 改为读取 `SettingsService.cacheMaxObjects`
  - 高：`200`
  - 中：`150`
  - 低：`80`

策略说明：

- 仅在 `BiliCacheManager` 首次创建时生效（启动生效）
- 本阶段不做运行时 reset/recreate，避免实例引用与资源句柄风险

### 7.6 弹幕数据结构优化（Phase 2）

生效文件：

- `lib/models/danmaku_item.dart`（新增）
- `lib/services/api/playback_api.dart`
- `lib/services/bilibili_api.dart`
- `lib/screens/player/mixins/player_state_mixin.dart`
- `lib/screens/player/mixins/player_action_mixin.dart`

改动内容：

- 弹幕从 `List<Map<String, dynamic>>` 改为 `List<BiliDanmakuItem>`
- 解析阶段直接构造 typed object
- 播放阶段改为属性访问（`dm.time / dm.content / dm.color`）

收益：

- 减少 Map/Hash 结构对象开销
- 降低 GC 压力，访问也更安全（类型更明确）

### 7.7 标签页内存策略（配套项）

生效文件：

- `lib/services/settings_service.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/home/settings/tabs/interface_settings.dart`

策略：

- `TabSwitchPolicy` 三档：`smooth / balanced / memorySaver`
- `memorySaver` 下 `keepTabPagesAlive = false`
- 切页时移除旧 tab 的 `_visitedTabs`，释放离页 widget 树

说明：

- 本轮未引入 `clearLiveImages()` 这类全局强清理，避免当前页闪白与重解码抖动
- 以内存上限 + LRU 自然淘汰为主

### 7.8 播放器侧边面板 & UP主弹窗图片优化

**问题现象**：播放时内存 ~450MB，打开 UP主面板后飙升至 ~600MB（+150MB），打开更多视频面板后 ~500+MB。

**根因分析**：

三个页面的封面图使用 `Image.network(video.pic)` 直接加载，存在两个致命问题：

1. **无 CDN 缩图**：`video.pic` 是原始 URL，B站 CDN 返回原图（通常 1280×720 或 1920×1080）
2. **无解码尺寸限制**：没有 `memCacheWidth/memCacheHeight`，全分辨率解码进内存

单张图内存占用对比：

| 分辨率 | 单张 RGBA 解码 | 30张 |
|---|---|---|
| 1280×720（原图） | 3.7MB | 111MB |
| 1920×1080（原图） | 8.3MB | 249MB |
| 200×112（修后） | 90KB | 2.7MB |

加上 UP主面板的 `_cachedVideos` 会同时缓存「最新」和「最热」两种排序的视频列表，最坏情况下有 60 张原图解码，足以解释 +150MB 的飙升。

**修复内容**：

生效文件：

- `lib/screens/player/widgets/up_panel.dart`
- `lib/screens/player/widgets/related_panel.dart`
- `lib/screens/home/up_space_popup.dart`

改动点（三个文件统一处理）：

| 组件 | 修前 | 修后 |
|---|---|---|
| UP面板头像 | `NetworkImage(url)` | `CachedNetworkImage` + `getResizedUrl(80×80)` + `memCacheWidth/Height` |
| UP面板封面 | `Image.network(url)` | `CachedNetworkImage` + `getResizedUrl(200×112)` + `memCacheWidth/Height` |
| 更多视频封面 | `Image.network(url)` | `CachedNetworkImage` + `getResizedUrl(200×112)` + `memCacheWidth/Height` |
| UP弹窗头像 | `CachedNetworkImage(url)` 无缩图 | 补 `getResizedUrl(96×96)` + `memCacheWidth/Height` |
| UP弹窗封面 | `CachedNetworkImage` + `getResizedUrl(480)` 无解码限制 | 补 `memCacheWidth: 480` / `memCacheHeight: 270` |

两层压缩机制：

1. **服务端缩图**（`ImageUrlUtils.getResizedUrl`）：让 CDN 只返回小尺寸图片，减少网络传输
2. **客户端解码限制**（`memCacheWidth/memCacheHeight`）：即使拿到大图也只按指定尺寸解码进内存

**修后效果**：打开 UP主面板 / 更多视频面板后内存几乎不增长。

**与三档缓存的关系**：

`imageCacheMaxSize`（高60/中40/低20）控制的是全局图片缓存池容量，所有页面共享：

```
总图片内存 = 单张解码大小 × 缓存池上限
```

修前三档差距巨大（低档 74MB vs 高档 222MB），修后单张仅 90KB，60 张也才 5.4MB，三档之间差距不到 4MB。图片缓存不再是内存瓶颈，三档差异主要体现在播放器缓冲区大小（15s / 30s / 50s）。

### 7.9 当前状态小结

- 已完成：播放三档联动（原生缓冲 + Flutter 定时与预加载策略）
- 已完成：image cache 动态化与运行时即时生效
- 已完成：BiliCacheManager 启动生效档位化
- 已完成：弹幕 typed class 改造
- 已完成：标签页切换策略与省内存模式对齐
- 已完成：播放器侧边面板 & UP主弹窗图片解码优化（消除 +150MB 峰值）
