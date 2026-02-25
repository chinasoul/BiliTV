# 首页/关注/历史卡片移动与对齐逻辑

本文档聚焦三个页面的卡片四向移动、边界处理、滚动对齐策略。

## 1. 通用底座：`BaseTvCard`

- 文件：`lib/widgets/base_tv_card.dart`
- 核心职责：
  - 基于 `TvFocusScope(FocusPattern.grid)` 接管四向导航
  - 聚焦时触发滚动对齐 `_scrollToRevealPreviousRow()`
  - 启用 `enableKeyRepeat: true`，支持长按方向键连续移动
- 对齐算法（`_scrollToRevealPreviousRow`）：
  - 读取卡片在 viewport 的 `top/bottom`
  - 计算安全区：
    - `topBoundary = topOffset + cardHeight * TabStyle.scrollRevealRatio`
    - `bottomBoundary = viewportHeight - cardHeight * TabStyle.scrollRevealRatio`
  - 第一行：优先贴近顶部边界（保持首行稳定）
  - 中间行：超底则上滚、超顶则下滚
  - 快速连续焦点切换（<150ms）用 `jumpTo`，否则 `animateTo`

## 2. 首页（Home）

- 文件：`lib/screens/home/home_tab.dart`
- 网格列数：`SettingsService.videoGridColumns`
- 每张卡片导航回调：
  - 左：首列 -> 侧边栏；否则 index-1
  - 右：有下一个 -> index+1；否则不处理
  - 上：非首行 -> index-gridColumns；首行 -> 分类标签
  - 下：有下一行 -> index+gridColumns；最后一行 -> “加载更多”（若存在）或阻止
- 特殊点：
  - 每分类维护独立 FocusNode 与滚动偏移缓存（切分类可回位）
  - `LoadMore` 自定义键控：上回最后一行、下阻止、左回侧边栏

## 3. 关注页（Following）

- 文件：`lib/screens/home/following_tab.dart`
- 分两类网格：

### 3.1 UP 主卡片网格

- 固定 4 列
- 方向规则与首页一致（首列左回侧边栏，首行上回顶部 tab）
- 使用自定义滚动函数 `_scrollToCard()` 做可视区对齐

### 3.2 视频卡片网格（收藏/稍后再看）

- 列数走 `SettingsService.videoGridColumns`
- 卡片组件仍基于 `BaseTvCard`（通用滚动对齐）
- 首行上移目的地按场景切换：
  - 有收藏夹 tab 时回收藏夹条
  - 否则回顶部 tab

## 4. 历史页（History）

- 文件：`lib/screens/home/history_tab.dart`
- 网格列数：`SettingsService.videoGridColumns`
- 方向规则：
  - 左：首列 -> 侧边栏；否则 index-1
  - 右：有下一个 -> index+1；否则阻止
  - 上：非首行 -> index-gridColumns；首行阻止（不离开当前内容区）
  - 下：有下一行 -> index+gridColumns；最后一行可跳“加载更多”（若存在）
- `LoadMore` 处理与首页类似：上回最后一行、下阻止

## 5. “移动对齐”真正来源

- 视觉对齐不是页面手工逐个算，而是主要由 `BaseTvCard` 的安全边界滚动算法统一控制
- 页面只决定“焦点要去哪里”（邻居或跨区），而不是“滚动多少”
- 好处：不同页面复用一致体验，局部页面只改回调目标即可

## 6. 修改建议

1. 调整滚动手感：优先改 `BaseTvCard._scrollToRevealPreviousRow()`
2. 调整页面边界行为（如首行上移到哪里）：改各页面 `onMoveUp/onMoveDown`
3. 调整列数行为：确认 `SettingsService.videoGridColumns` 下索引换算是否全覆盖
4. 新增卡片类型时，尽量复用 `BaseTvCard` 避免分叉逻辑
