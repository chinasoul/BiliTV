# DPAD 导航与边界限制逻辑备忘

本文档聚焦页面内四方向键限制、焦点越界防护、长按方向键（KeyRepeat）行为。

## 1. 核心框架

- 公共导航工具：`lib/core/focus/focus_navigation.dart`
  - `TvKeyHandler.handleNavigation()`：仅 `KeyDownEvent`
  - `TvKeyHandler.handleNavigationWithRepeat()`：`KeyDownEvent + KeyRepeatEvent`
  - `blockUp/down/left/right`：无目标时吞键，防止焦点逃逸
- 通用焦点容器：`TvFocusScope`
  - 支持 `vertical/horizontal/grid` 三种模式
  - 可配置 `exitUp/down/left/right` 或 `onExitXxx`
  - `isFirst/isLast` + `blockXxx` 在边界阻止移动
  - `enableKeyRepeat` 控制是否允许长按连续移动

## 2. “页面内不移出”的实现策略

常见做法有 4 种：

1. **无可去目标时返回 handled**：方向键被吃掉，不交给系统默认焦点搜索
2. **边界索引 clamp**：如播放器按钮/设置项移动用 `.clamp(0, max)`
3. **仅在边界配置 exit 回调**：避免中间项跨区跳焦点
4. **局部 FocusScope 拦截**：弹窗/面板中拦截方向键，强制留在当前容器

## 3. 长按方向键（KeyRepeat）规则

- 全局上：只有实现显式支持的模块，长按才会连续移动
- 典型支持点：
  - `TvFocusScope(enableKeyRepeat: true)`（如 `BaseTvCard`）
  - 播放器隐藏控制栏时左右 seek（`handleGlobalKeyEvent` 中处理 `KeyRepeatEvent`）
  - 选集面板、预览快进模式、评论列表、搜索键盘/结果等
- 典型不支持点：
  - 需要“单次触发”的确认/返回逻辑，多限制为 `KeyDownEvent`

## 4. 播放器内 DPAD 规则

- 文件：`lib/screens/player/mixins/player_event_mixin.dart`
- 分层处理：
  1. 若某面板打开（设置/选集/评论/UP/相关推荐/动作区），优先面板内处理
  2. 否则按 `showControls` 分为“控制栏显示”与“控制栏隐藏”两套逻辑
- 控制栏显示：
  - 左右：在 10 个按钮间移动（边界 clamp）
  - 上：进入进度条
  - 下：隐藏控制栏
  - 确认：触发按钮
- 控制栏隐藏：
  - 上/下：唤起控制栏
  - 左/右：快退/快进（支持长按）
- 返回键：
  - 先关子面板，再关控制栏，最后双击退出播放器（2 秒窗口）

## 5. 主页/关注/历史的边界限制（重点）

### 5.1 首页 `home_tab.dart`

- 左边界（首列）按左 -> 侧边栏
- 顶边界（首行）按上 -> 分类 tab
- 底边界（末行）按下 -> `LoadMore`（存在时）或阻止
- `LoadMore` 本身：下阻止、上回最后一行、左回侧边栏

### 5.2 关注 `following_tab.dart`

- UP 网格与视频网格都做了首列/首行/末行边界判断
- 首列左移通常回侧边栏；首行上移回顶部 tab（或收藏夹 tab）
- 部分区块使用自定义 `onKeyEvent` + `requestFocus`，避免系统默认乱跳

### 5.3 历史 `history_tab.dart`

- 首列左移回侧边栏
- 首行上移可阻止（保持在当前内容区）
- 末行下移可转 `LoadMore`（存在时）或阻止

## 6. 长按也不能移出当前页的关键点

1. 网格卡片必须走 `TvFocusScope + enableKeyRepeat + onExitXxx`，不要混用默认 Focus 邻居搜索
2. 边界回调里若“不允许离开”，返回空动作并 `handled`，不要 `ignored`
3. 弹窗/侧面板用 `FocusScope` 拦截方向键，避免 key repeat 穿透到底层页面
4. 对关键入口（如播放器全局 handler）统一处理 `KeyRepeatEvent`，避免长按时落到系统默认行为

## 7. 设置页滚动基线

- 文件：`lib/screens/home/settings/settings_view.dart`
- 方案：页面级 `ScrollController` + 边界算法（不再依赖子组件各自 `ensureVisible`）
- 触发条件：
  - 焦点变化后，定位当前焦点对应的可测量 `RenderBox`
  - 计算 item 在当前分类内容区 viewport 的 `top/bottom`
  - 仅在越过 `topBoundary/bottomBoundary` 时滚动
- 阈值设计（避免分辨率漂移）：
  - `itemBasedReveal = itemHeight * 0.25`
  - `viewportBasedReveal = clamp(viewportHeight * 0.06, 32, 96)`
  - `revealHeight = max(itemBasedReveal, viewportBasedReveal)`
- 动画策略：
  - 快速连续焦点移动（<150ms）使用 `jumpTo`
  - 其他使用 `animateTo`

## 8. 改动检查单

1. 新页面是否明确了四方向边界行为（首行/末行/首列/末列）
2. 是否区分 `KeyDownEvent` 与 `KeyRepeatEvent`
3. 边界处是否吞键（`handled`）防止焦点逃逸
4. 面板关闭后焦点是否回到预期锚点
5. 返回键是否遵循“先收内部层，再退出页面”的顺序
