# TV 鼠标/键盘改造纪要（2026-02）

## 目标与范围
- 目标：在不引入新依赖前提下，为 TV 端补齐鼠标/键盘主路径可用性。
- 覆盖：侧边栏、首页/设置页分类标签、设置项行、设置弹窗、播放器控制层与进度条。
- 非目标：不做右键菜单体系，不做触屏专项交互，不引入全局输入抽象层。

## 最终交互策略（已落地）
- 鼠标策略：`点击触发焦点/动作`，不做悬停高亮（避免高频移动引发无意义状态更新）。
- 播放页鼠标策略：
  - 不做“底部热区移动唤起控制栏”（已验证在 `platformView` 路径下不稳定，已移除）。
  - 通过单击画面和单击控制按钮完成主要交互。
- 键盘策略：
  - 保持现有方向键/确认键/返回键逻辑。
  - 播放页 `Space`：
    - 控制栏显示时：触发当前聚焦按钮（等同确认键）。
    - 控制栏隐藏时：播放/暂停。
- 播放页鼠标单击：
  - 若右侧子面板已打开（评论/分P/UP主/更多/设置/动作区）：单击先关闭子面板，不触发暂停。
  - 无子面板时：控制栏隐藏 -> 单击呼出控制栏；控制栏显示 -> 单击播放/暂停。

## 核心问题与修复点
- 侧边栏点击后主题色残留在首页：
  - 原因：点击仅触发 `onTap`，未同步请求焦点。
  - 修复：点击时先 `requestFocus()` 再执行 `onTap()`。
- 设置页 Dropdown/Action 点击闪一下 themeColor：
  - 原因：点击前强制聚焦 (`onTapDown/requestFocus`) 后立刻弹窗。
  - 修复：去掉点击前聚焦，改为点击直接弹窗/执行。
- 播放页鼠标不可操作控制栏：
  - 原因：控制按钮仅有视觉状态，无鼠标点击通路。
  - 修复：控制按钮加入点击事件回调；播放器根层加入单击行为路由。
- 播放页进度条无法鼠标操作：
  - 修复：进度条支持点击跳转与水平拖动 seek，并同步弹幕索引。
- 播放器右侧面板切换后偶发不同步：
  - 原因：面板状态叠加，切换时未做互斥清理。
  - 修复：点击评论/分P/UP主/更多/设置时，先关闭其他侧面板，再打开目标面板。
- 视频数据实时监测在分P/设置打开时无法显示：
  - 原因：显示条件硬编码屏蔽 `showSettingsPanel/showEpisodePanel`，且按钮点击未先清理面板状态。
  - 修复：点击监测按钮时先关闭所有侧栏/浮层，再切换监测；显示条件统一要求“无侧栏/浮层”。

## 主要改动文件（Dart）
- `lib/widgets/base_tv_card.dart`
- `lib/widgets/tv_focusable_item.dart`
- `lib/widgets/tv_keyboard_button.dart`
- `lib/screens/home/home_tab.dart`
- `lib/screens/home/settings/settings_view.dart`
- `lib/screens/home/settings/widgets/setting_toggle_row.dart`
- `lib/screens/home/settings/widgets/setting_action_row.dart`
- `lib/screens/home/settings/widgets/setting_dropdown_row.dart`
- `lib/screens/home/settings/widgets/value_picker_popup.dart`
- `lib/screens/player/player_screen.dart`
- `lib/screens/player/widgets/controls_overlay.dart`
- `lib/screens/player/widgets/tv_progress_bar.dart`
- `lib/screens/player/mixins/player_event_mixin.dart`

## 后续修改注意事项（避免回归）
- 不要把鼠标悬停直接绑定高亮状态（当前策略是点击驱动高亮）。
- 不要再次加入“底部热区移动唤起控制栏”逻辑（`platformView` 下事件链路不稳定，收益低于维护成本）。
- 如果设置行点击后要立即弹窗，避免先做 `requestFocus()`，否则会出现闪烁。
- 播放器控制按钮新增按钮时，记得同步：
  - `focusedIndex` 边界；
  - 键盘确认触发逻辑；
  - 鼠标点击回调分发。
- 右侧面板入口（评论/分P/UP主/更多/设置）必须保持“互斥打开”，避免状态叠加。
- 进度条 seek 后必须同步 `resetDanmakuIndex()`，否则弹幕会错位。
- 如果从“已播放完”状态回拖进度，需重置 `hasHandledVideoComplete`。

## 建议回归清单（最小集）
- 侧边栏鼠标点击各 tab，主题色跟随当前项，不残留。
- 首页/设置页分类标签：点击可切换，无悬停高亮。
- 设置页 `Dropdown/Action`：点击直接弹窗，无 themeColor 闪烁。
- 播放页：
  - 子面板打开时，单击先关闭子面板；无子面板时再按“呼出/暂停”规则；
  - 控制栏入口切换（评论/分P/UP主/更多/设置）始终互斥显示；
  - 控制栏显示时空格触发当前按钮；
  - 进度条可点击和拖动跳转。
