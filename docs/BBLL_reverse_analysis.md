# BBLL 1.5.2 逆向分析摘要（播放流畅度相关）

仅基于 DEX 内字符串与类名分析，未使用 jadx 等完整反编译。用于理解 BBLL 在电视上为何更流畅、供 BT 参考。

---

## 1. 技术栈

| 项目 | 结论 |
|------|------|
| 播放库 | **AndroidX Media3**（ExoPlayer 新一代），版本 **1.5.1**（字符串 `[AndroidXMedia3/1.5.1]`） |
| 应用包名/自定义包 | `com.xx.blbl`，播放相关在 `com.xx.blbl.ui.view.exoplayer` |
| 原生库 | 仅见 `libgdx.so`（LibGDX，可能用于 UI/动效），**视频解码仍为 Java 层 MediaCodec/ExoPlayer** |

---

## 2. 与“流畅/帧率”相关的关键点

### 2.1 帧率与显示同步（电视防抖关键）

- **Surface.setFrameRate**  
  DEX 中出现 `setFrameRate`、`subFrameRate`，以及 **`Failed to call Surface.setFrameRate`** 的日志文案。  
  → 说明 BBLL 会调用 `Surface.setFrameRate()`，让系统/电视按内容帧率刷新，减少帧率不匹配带来的卡顿感。

- **VideoFrameReleaseHelper**  
  Media3 的 **VideoFrameReleaseHelper** 类名出现。  
  → 用于按 vsync 对齐释放帧，减少掉帧和撕裂，对“感觉帧率很高”的观感帮助大。

- **FrameReleaseChoreographer**  
  线程/组件名 **`ExoPlayer:FrameReleaseChoreographer`** 出现。  
  → 与帧释放编排相关，和上面一起构成“帧率感高”的底层机制。

- **setVideoFrameRate / setVideoScalingMode**  
  存在 **setVideoFrameRate**、**setVideoScalingMode** 相关字符串。  
  → 会配置播放器与视频缩放、输出帧率相关的行为。

### 2.2 缓冲策略（LoadControl）

- 字符串 **“Players that share the same LoadControl must share the same playback thread. See ExoPlayer.Builder.setPlaybackLooper(Looper).”**  
  → 说明 BBLL 使用了 **自定义或显式配置的 LoadControl**（否则不会触发这段校验逻辑）。

- 与缓冲时长相关的字段名均出现：  
  **minBufferMs**、**maxBufferMs**、**bufferForPlaybackMs**、**bufferForPlaybackAfterRebufferMs**、**backBufferDurationMs**，以及 **minBufferTime** / **setMinBufferTime** / **getMinBufferTime**。  
  → 可以推断他们**按时间维度调了缓冲**（min/max、起播、重缓冲后起播、回退缓冲），而不只是用默认值。

---

## 3. BBLL 自定义播放 UI 类（供对照）

- `MyPlayerView`、`MyPlayerControlView`、`MyPlayerSettingView`
- `MyPlayerControlViewLayoutManager`
- `DebugTextViewHelper`（类似“数据监测”）
- `OnVideoSettingChangeListener`、`OnPlayerSettingInnerChange`、`OnPlayerSettingChange`
- `OnDmEnableChangeImpl`、`OnMenuShowImpl`

说明：播放器是**原生 View + Media3 ExoPlayer**，没有 Flutter 的 Platform View 这一层，渲染路径更短。

---

## 4. 对 BT 的可行借鉴（不抄代码，只借鉴思路）

1. **帧率与显示同步**  
   在 Android 原生层（或 fork video_player_android 后）对 ExoPlayer/Media3 做：
   - 调用 **Surface.setFrameRate**（或 Media3 中等效 API），使输出帧率与电视刷新率一致。
   - 使用/启用 **VideoFrameReleaseHelper**、**FrameReleaseChoreographer** 的默认或推荐配置，保证按 vsync 释放帧。

2. **缓冲策略**  
   使用 **LoadControl**（如 `DefaultLoadControl.Builder`）显式设置：
   - **minBufferMs** / **maxBufferMs**
   - **bufferForPlaybackMs** / **bufferForPlaybackAfterRebufferMs**
   例如适当加大 `minBufferMs`、`bufferForPlaybackMs`，减少高码率/快速运动时的卡顿。

3. **渲染路径**  
   BBLL 为原生 PlayerView，无 Flutter 嵌入；BT 当前为 Flutter + Platform View。若在 TV 上仍感觉不如 BBLL 顺滑，可考虑在 TV 构建中让视频全屏时走**原生全屏 Surface**，减少一层合成（需改插件或原生集成）。

4. **依赖版本**  
   BBLL 使用 **Media3 1.5.1**。BT 已通过 **video_player_android ^2.9.0** 使用 **androidx.media3**（ExoPlayer 1.8.0），不再使用 exoplayer2；与 BBLL 同属 Media3 体系。若需进一步接近 BBLL 的流畅度，需在原生层或 fork 插件中配置 LoadControl、帧率匹配等（见上）。

---

## 5. 分析环境与局限

- **APK**：BBLL 1.5.2（来自用户提供的安装包）。
- **方法**：仅对 `classes.dex` / `classes2.dex` 做 `strings` 提取与类名检索，**未使用 jadx 等反编译**，故无具体方法体、无精确缓冲数值、无调用链。
- **目的**：仅用于技术学习与 BT 播放体验优化参考，不涉及对 BBLL 代码的复制或再发布。

如需得到**具体缓冲毫秒数**或 **setVideoChangeFrameRateStrategy 的调用处**，需在本机用 jadx 打开同一 APK，在 `com.xx.blbl.ui.view.exoplayer` 与 `androidx.media3` 包下搜索上述关键字再阅读反编译代码。
