# 条件滚动文字（Marquee）重写方案备忘

本文档记录“视频卡片聚焦时标题滚动”的新实现链路与性能设计，后续改动优先阅读本文件恢复上下文。

## 1. 目标与背景

- 旧方案：依赖传统 marquee 动画实现，通常绑定 vsync / rebuild 频繁。
- 新方案：改为 `ConditionalMarquee`，只在需要滚动时绘制位移，减少无效渲染。
- 目标：
  - 聚焦时滚动，非聚焦时单行省略
  - 文本不溢出时不启动动画
  - 在 TV 列表高密度场景下尽量降低 CPU 开销

## 2. 代码位置

- 核心组件：`lib/widgets/conditional_marquee.dart`
- 主要调用点：
  - `lib/widgets/tv_video_card.dart`
  - `lib/widgets/tv_live_card.dart`
  - `lib/widgets/history_video_card.dart`
  - `lib/screens/player/widgets/controls_overlay.dart`

## 3. 调用链（卡片聚焦）

1. 卡片 `isFocused == true` 时，标题用 `ConditionalMarquee`。
2. `isFocused == false` 时，直接 `Text(..., overflow: TextOverflow.ellipsis)`。
3. `ConditionalMarquee` 内部通过 `LayoutBuilder` 获取容器宽度。
4. 若 `textWidth <= containerWidth` 且 `alwaysScroll == false`，不滚动。
5. 仅在“需要滚动”时进入定时器驱动的 paint 位移流程。

## 4. 新实现关键机制

### 4.1 条件启动

- 通过 `_measureTextWidth()` 测量文本实际宽度。
- `shouldScroll = alwaysScroll || textWidth > containerWidth`。
- 只有 `shouldScroll == true` 才启动动画。

### 4.2 三阶段时序

- `delay`：先等待 `startDelay`（默认 500ms，避免焦点一到就抖动）。
- `scrolling`：`Timer.periodic(_frameInterval)` 驱动偏移更新。
- `pause`：每轮滚动结束后暂停 3s，再进入下一轮。

### 4.3 帧率控制（开发者设置联动）

- `_frameInterval` 读取 `SettingsService.marqueeFps`：
  - `30fps -> 33ms`
  - `60fps -> 16ms`
- 设置入口：开发者选项「滚动文字60帧」。

### 4.4 仅重绘，不重建

- 偏移量变化后调用 `markNeedsPaint()`，不触发 widget rebuild。
- 自定义 `_RenderMarquee` 在 `paint` 阶段完成：
  - clip 当前区域
  - 绘制第一份文本（左移）
  - 需要时绘制第二份文本（循环衔接）

### 4.5 重绘隔离

- 外层 `RepaintBoundary` 包裹滚动文本。
- 滚动时重绘限制在文字区域，不扩散到卡片图片等大区域。

## 5. 性能取舍

- 使用 `Timer.periodic` 而不是持续 vsync 动画：
  - 间隔期间引擎可休眠
  - 仅在 tick 到来时请求一帧重绘
- 文本宽度缓存：
  - 仅在 `text/style/constraints` 变化时重新测量
- 生命周期安全：
  - `dispose` 时取消定时器
  - 异步阶段检查 `_disposed` / `_needsScroll`

## 6. 常见修改点

1. 调整滚动速度：改调用方 `velocity`（卡片常用 30，播放器标题常用 40）。
2. 调整延迟：改 `startDelay`（默认 500ms）。
3. 调整间隔空白：改 `blankSpace`。
4. 调整性能：改 `SettingsService.marqueeFps` 或默认值逻辑。
5. 调整视觉：改调用方文字 `TextStyle`。

## 7. 维护检查单

修改此功能时建议按顺序检查：

1. `conditional_marquee.dart` 的阶段状态机是否仍正确（delay/scroll/pause）
2. `didUpdateWidget` 对 text/style 变化是否正确重置
3. 调用点是否只在聚焦时启用滚动（避免列表全量滚动）
4. 开发者设置中的 `marquee_fps` 联动是否保持生效
5. 更新本文档

## 8. 文档化节省 token 评估

- 主要节省输入 token（避免反复读多个实现文件和调用点）：
  - 小改动：约 30% ~ 60%
  - 中改动：约 20% ~ 40%
- 输出 token 通常也会下降（少重复解释）：约 10% ~ 30%

结论：此类“机制型实现”写入 md 文档，长期收益明显。
