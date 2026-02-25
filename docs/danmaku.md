# 弹幕系统架构备忘

本文档记录弹幕从「获取 → 同步 → 渲染 → 控制」的完整链路，修改时直接读取本文件即可恢复上下文。

---

## 0. 双渲染模式概览

| 模式 | 条件 | 渲染层 | 优点 | 缺点 |
|------|------|--------|------|------|
| Flutter 弹幕（默认） | `preferNativeDanmaku == false` 或非 Android | `canvas_danmaku` 库的 `DanmakuLayer` Widget | 跨平台；字体/样式控制灵活 | Android TV 上与 PlatformView 合成时可能卡顿 |
| 原生弹幕（实验） | `preferNativeDanmaku == true` 且 Android | `DanmakuOverlayView`（Java 自定义 View） | 渲染与视频在同一 PlatformView，无 Flutter 合成开销 | 仅 Android；功能比 Flutter 方案少 |

切换入口：设置 → 弹幕设置 → 第一项「原生弹幕渲染优化(实验)」
存储 key：`prefer_native_danmaku`（默认 false）

判断逻辑：`player_action_mixin.dart` 第 51 行

```dart
bool get _useNativeDanmakuRender =>
    defaultTargetPlatform == TargetPlatform.android && preferNativeDanmaku;
```

---

## 1. 文件清单

### Dart 侧

| 文件 | 职责 |
|------|------|
| `lib/screens/player/mixins/player_action_mixin.dart` | 弹幕同步定时器、syncDanmaku、暂停/恢复/开关、选项构建与下发 |
| `lib/screens/player/mixins/player_state_mixin.dart` | 弹幕相关状态变量（danmakuEnabled, danmakuOpacity, preferNativeDanmaku 等） |
| `lib/screens/player/player_screen.dart` | 条件渲染 `DanmakuLayer`（Flutter 模式时）或跳过（原生模式时） |
| `lib/services/native_player_danmaku_service.dart` | MethodChannel 封装：addDanmaku / addDanmakuBatch / updateOption / clear / pause / resume |
| `lib/services/settings_service.dart` | 弹幕设置持久化（opacity / fontSize / speed / area / hideTop / hideBottom / preferNativeDanmaku） |
| `lib/screens/home/settings/tabs/danmaku_settings.dart` | 全局弹幕设置 UI |

### Android 原生侧

| 文件 | 职责 |
|------|------|
| `packages/video_player_android/.../platformview/DanmakuOverlayView.java` | 自定义 View，Canvas 绘制滚动弹幕，轨道调度，暂停补偿 |
| `packages/video_player_android/.../platformview/PlatformVideoView.java` | FrameLayout 容器 = SurfaceView（视频）+ DanmakuOverlayView（弹幕） |
| `packages/video_player_android/.../platformview/PlatformVideoViewFactory.java` | PlatformView 工厂，创建后通过 `PlatformViewCreatedListener` 回调注册 |
| `packages/video_player_android/.../VideoPlayerPlugin.java` | 主插件，注册 MethodChannel `plugins.flutter.dev/video_player_android_danmaku`，路由弹幕指令 |

---

## 2. 数据流：弹幕获取 → 渲染

```
API 获取弹幕列表
    ↓
danmakuList（按时间排序的 List<Map>，含 time/content/color）
    ↓
_startDanmakuSyncTimer() — 80ms 周期定时器
    ↓
syncDanmaku(currentTime)
    ├── 遍历 danmakuList，取出 time ≤ currentTime 且 差值 < 1s 的条目
    ├── 插件管道过滤/样式化（DanmakuPlugin.filterDanmaku / styleDanmaku）
    ├── 构造 DanmakuContentItem(text, color)
    │
    ├─ [Flutter 模式] → danmakuController!.addDanmaku(item)  // 逐条
    └─ [原生模式]   → 攒入 nativeBatch List
                     → NativePlayerDanmakuService.addDanmakuBatch(controller, batch)  // 批量
                         ↓
                     MethodChannel('plugins.flutter.dev/video_player_android_danmaku')
                         ↓
                     VideoPlayerPlugin.handleDanmakuMethodCall
                         ↓
                     PlatformVideoView.addDanmaku(text, color)
                         ↓
                     DanmakuOverlayView.addDanmaku(text, color)
```

---

## 3. MethodChannel 协议

通道名：`plugins.flutter.dev/video_player_android_danmaku`

| 方法 | 参数 | 说明 |
|------|------|------|
| `addDanmaku` | `{playerId, text, color}` | 添加单条弹幕 |
| `addDanmakuBatch` | `{playerId, items: [{text, color}, ...]}` | 批量添加（推荐） |
| `updateOption` | `{playerId, opacity, fontSize, area, duration, hideScroll, strokeWidth, lineHeight}` | 更新渲染参数 |
| `clear` | `{playerId}` | 清空所有在屏弹幕 |
| `pause` | `{playerId}` | 暂停弹幕滚动 |
| `resume` | `{playerId}` | 恢复弹幕滚动（含暂停补偿） |

---

## 4. DanmakuOverlayView 核心机制

### 4.1 运动模型

- 弹幕从屏幕右侧出发，向左匀速运动
- `totalDistance = screenWidth + textWidth`
- `speed = totalDistance / durationMs`
- `x = screenWidth - elapsed * speed`
- elapsed 由 `SystemClock.elapsedRealtime() - bornAtMs` 计算

### 4.2 轨道调度（pickTrackByPosition）

每个轨道记录最后一条弹幕的 `TrackTail{textWidth, bornAtMs, speed}`：

1. 轨道空（tail == null）→ 直接使用
2. 尾部右边缘未离开屏幕右侧 minGapPx → 跳过
3. 新弹幕更快时 → 追赶检测：计算新弹幕在尾部弹幕退出时的 x 位置，确认不会重叠
4. 新弹幕不快于尾部 → 安全，直接使用
5. 所有轨道都不可用 → 返回 -1，弹幕被丢弃（`droppedByTrackBusy++`）

关键参数：
- `minGapPx = max(textSizePx * 1.0, 42px)` — 同轨道前后弹幕的最小间距
- 轨道数 = `ceil(screenHeight * areaRatio / rowHeight)`

### 4.3 暂停补偿

- `pauseDanmaku()`：记录 `pauseStartMs = elapsedRealtime()`
- `resumeDanmaku()`：计算 `pauseDuration = now - pauseStartMs`，所有在屏 `DanmakuItem.bornAtMs` 和 `TrackTail.bornAtMs` 向后偏移 `pauseDuration`
- 效果：弹幕从暂停位置继续滚动，不跳帧

### 4.4 透明度

- `opacityScale = clamp(0.05 + 0.95 * opacity, 0, 1)` — 近线性曲线
- 填充色 alpha = `sourceAlpha * opacityScale`
- 描边 alpha = `fillAlpha * 0.45`（opacityScale < 0.25 时隐藏描边）

### 4.5 绘制循环

`onDraw()` 在 `synchronized(items)` 内遍历所有弹幕：
- 计算 x 位置，移出屏幕左侧则 `remove()`
- 先画 strokePaint（黑色描边），再画 textPaint（填充色）
- 有存活弹幕 && running → `postInvalidateOnAnimation()` 驱动下一帧

---

## 5. 选项下发与重试

`_applyDanmakuOptionWithRetry()` 在以下时机调用：
- 播放器初始化（`_setupPlayerListeners`）
- 弹幕开关打开（`toggleDanmaku`）
- 设置变更（`updateDanmakuOption`）

由于 PlatformView 创建有延迟，首次发送可能无法生效，因此采用 180ms 间隔重试 10 次的策略。

选项参数构建：`_buildDanmakuOption()`

```dart
DanmakuOption(
  opacity: danmakuOpacity,
  fontSize: danmakuFontSize,
  duration: danmakuSpeed / playbackSpeed,  // 随倍速同步调整
  area: danmakuArea,
  hideTop: hideTopDanmaku,
  hideBottom: hideBottomDanmaku,
)
```

---

## 6. 播放器生命周期中的弹幕控制

| 事件 | Flutter 模式 | 原生模式 |
|------|-------------|---------|
| 播放 → 暂停 | `danmakuController.pause()` | `NativePlayerDanmakuService.pause()` |
| 暂停 → 播放 | `danmakuController.resume()` | `NativePlayerDanmakuService.resume()` |
| Seek | `danmakuController.clear()` + `resetDanmakuIndex` | `NativePlayerDanmakuService.clear()` + `resetDanmakuIndex` |
| 弹幕开关关 | `danmakuController.clear()` | `NativePlayerDanmakuService.clear()` |
| 弹幕开关开 | 自动恢复（syncTimer 继续） | `_applyDanmakuOptionWithRetry()` + syncTimer 继续 |
| 播放器 dispose | `danmakuController` 随 widget 销毁 | `PlatformVideoView.dispose()` → `clearDanmaku()` |

---

## 7. 已知限制与待改进

- 原生模式仅支持滚动弹幕，不支持顶部/底部固定弹幕
- `hideTop` / `hideBottom` 参数传给原生层但原生层当前未实现固定弹幕
- 高密度弹幕时 `droppedByTrackBusy` 可能丢弃较多弹幕
- 弹幕重叠仍可能在极端情况下出现（大量同时到达 + 轨道数少）

---

## 8. 维护建议

修改弹幕功能时，按以下检查单操作：

1. **新增弹幕设置项**：`SettingsService` 新增 key/getter/setter → `danmaku_settings.dart` 加 UI → `_buildDanmakuOption()` 加字段 → `NativePlayerDanmakuService.updateOption()` 加参数 → `DanmakuOverlayView.updateOption()` 加字段
2. **修改渲染逻辑**：改 `DanmakuOverlayView.onDraw()` 或 `addDanmaku()`
3. **修改同步逻辑**：改 `syncDanmaku()` 或 `_startDanmakuSyncTimer()`
4. **修改生命周期**：改 `player_action_mixin.dart` 中对应的 toggle/pause/resume 方法
5. **更新本文档**
