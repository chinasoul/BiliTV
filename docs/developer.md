# Developer Mode 流程备忘

本文档记录 `开发者选项` 每一项设置的完整链路：入口 -> UI 开关 -> `SettingsService` 持久化 -> 实际生效点。

## 0. 开发者模式入口（如何显示“开发者选项”标签）

1. 入口页：`lib/screens/home/settings/tabs/device_info_settings.dart`
2. 在“系统版本”行触发 `_onVersionTap()`，2 秒内连续点击 7 次：
   - 未开启时：`SettingsService.setDeveloperMode(true)`
   - 已开启时：提示“已处于开发者模式”
3. 状态存储：`SettingsService._developerModeKey = 'developer_mode'`
4. 标签显示：`lib/screens/home/settings/settings_view.dart`
   - `_visibleCategories` 中根据 `SettingsService.developerMode` 决定是否加入 `SettingsCategory.developerOptions`
   - `SettingsService.onDeveloperModeChanged` 回调触发 `_onDeveloperModeChanged()`，动态重建 tab/focus

## 1. 开发者选项页总览

页面文件：`lib/screens/home/settings/tabs/developer_settings.dart`

- `initState()` 读取当前值：
  - `developerMode`
  - `showMemoryInfo`
  - `showAppCpu`
  - `showCoreFreq`
  - `marqueeFps == 60`
- 每个 `SettingToggleRow.onChanged` 都是：
  - 先 `setState` 更新当前页 UI
  - 再调用 `SettingsService` 写入偏好并触发对应回调

## 2. 每项设置流程

### 2.1 开发者选项（总开关）

- UI：`DeveloperSettings` 第 1 项 “开发者选项”
- 写入：`SettingsService.setDeveloperMode(bool)`
- 存储 key：`developer_mode`
- 回调：`SettingsService.onDeveloperModeChanged?.call()`
- 生效：`SettingsView` 监听后刷新 tabs，显示或隐藏“开发者选项”页签

### 2.2 显示 CPU/内存信息

- UI：`DeveloperSettings` 第 2 项 “显示CPU/内存信息”
- 写入：`SettingsService.setShowMemoryInfo(bool)`
- 存储 key：`show_memory_info`
- 回调：`SettingsService.onShowMemoryInfoChanged?.call()`
- 生效组件：`lib/widgets/global_memory_overlay.dart`
  - `initState()` 注册 `onShowMemoryInfoChanged = _syncSetting`
  - 开启时 `_startMonitor()` 创建定时器并周期采样
  - 关闭时 `_stopMonitor()` 停止定时器并清空显示文本
  - 渲染条件：`SettingsService.showMemoryInfo && _appMem.isNotEmpty`

### 2.3 显示 APP 占用率

- UI：`DeveloperSettings` 第 3 项 “显示APP占用率”
- 写入：`SettingsService.setShowAppCpu(bool)`
- 存储 key：`show_app_cpu`
- 回调：复用 `onShowMemoryInfoChanged`
- 生效组件：`global_memory_overlay.dart`
  - 采样时若 `SettingsService.showAppCpu` 为 true，显示 `PCT\tx%/N`
  - 逻辑位置：`_updateMemory()` 内 CPU 计算段

### 2.4 显示核心频率

- UI：`DeveloperSettings` 第 4 项 “显示核心频率”
- 写入：`SettingsService.setShowCoreFreq(bool)`
- 存储 key：`show_core_freq`
- 回调：复用 `onShowMemoryInfoChanged`
- 生效组件：`global_memory_overlay.dart`
  - 采样时若 `SettingsService.showCoreFreq` 为 true，读取
    `/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq`
  - 逐核显示 `C0\txxxM`（tab 对齐）

### 2.5 滚动文字60帧

- UI：`DeveloperSettings` 第 5 项 “滚动文字60帧”
- 写入：`SettingsService.setMarqueeFps(v ? 60 : 30)`
- 存储 key：`marquee_fps`
- 生效组件：`lib/widgets/conditional_marquee.dart`
  - `_frameInterval` 读取 `SettingsService.marqueeFps`
  - `30fps -> 33ms`，`60fps -> 16ms`
  - 通过 `Timer.periodic` 驱动滚动更新

## 3. 当前性能相关说明（2026-02-25）

- `global_memory_overlay.dart` 的监控定时器已从 `1s` 调整为 `500ms` 刷新一次。
- 更高频率会提升数据实时性，也会略增 CPU 与 I/O（读取 `/proc` 与 `sysfs`）开销；如需进一步可调，建议后续抽成可配置项（500ms/1000ms）。
- overlay 展示已分为两块：基础信息（`CPU/APP/AVL/TOT`）固定显示；可选信息（`PCT` 与逐核频率）单独显示，避免开启额外项后挤占基础信息。
- 所有行统一采用 `label + 固定间隔 + value`，value 按最大长度右对齐（等宽字体 + `tabularFigures`），便于数字列纵向比较。
- overlay 宽度不再限制在侧边栏 5% 内，按文本自然宽度显示；允许超出侧边栏区域，以保证信息完整显示不被挤压。
- 为提升浅色背景可读性，文本改为 `amber` 色，并增加半透明深色底与轻微阴影。

## 4. 维护建议（下次改动时）

当新增开发者设置时，按以下检查单更新：

1. `SettingsService`：新增 key + getter + setter（必要时回调）
2. `developer_settings.dart`：新增 UI 开关与本地状态字段
3. 生效组件：读取该设置并在需要时监听回调
4. `docs/developer.md`：补充“入口/写入/生效点”三段信息
