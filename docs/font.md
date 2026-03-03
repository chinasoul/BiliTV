# 字体体系

本项目采用 **设计源头 + 用户缩放** 双层模型管理全局字体。

## 1. 架构

```
AppFonts (设计基准)          用户偏好 (缩放倍率)
lib/config/app_style.dart    lib/main.dart → textScaler
        ↓                            ↓
  固定 6 档字号              0.8x ~ 1.4x 全局缩放
        ↓                            ↓
        └──── 最终渲染字号 = 设计字号 × 缩放倍率 ────┘
```

- **设计基准**：`AppFonts` 定义 6 个固定字号常量，决定 UI 各层级的视觉比例。
- **用户偏好**：`main.dart` 通过 `MediaQuery.textScaler` 乘以用户选择的缩放系数（`SettingsService.fontScale`），统一放大或缩小所有文字。
- 两层互不耦合：改设计基准不影响用户偏好；改用户缩放不影响层级比例。

## 2. 字号档位

6 档，每档间距 ≥ 2px，在 TV 观看距离（2-3 米）下层级清晰可辨。

| 常量 | 值 | 语义 | 典型场景 |
|------|------|------|----------|
| `AppFonts.sizeXS` | 10 | 角标 / 弱提示 | 徽章数字、时长标签、极小辅助文字 |
| `AppFonts.sizeSM` | 12 | 辅助信息 | 副标题、进度条标签、设置项说明 |
| `AppFonts.sizeMD` | 14 | 正文 | 列表项内容、卡片描述、评论正文 |
| `AppFonts.sizeLG` | 16 | 按钮 / Tab | 设置项标题、Tab 标签、操作按钮 |
| `AppFonts.sizeXL` | 20 | 面板标题 | 播放器面板标题、空状态提示、键盘按键 |
| `AppFonts.sizeXXL` | 24 | 页面大标题 | 搜索页标题、登录标题、强调文字 |

## 3. 用户缩放

用户在 **设置 → 界面 → 字体大小** 中选择缩放档位：

| 档位 | 缩放系数 | 效果 |
|------|----------|------|
| -20% | 0.8 | 字号整体缩小 |
| -10% | 0.9 | |
| 默认 | 1.0 | 设计基准原始大小 |
| +10% | 1.1 | |
| +20% | 1.2 | |
| +30% | 1.3 | |
| +40% | 1.4 | 字号整体放大 |

生效方式：`main.dart` 的 `BtApp` 通过 `ValueListenableBuilder` 监听 `fontScaleListenable`，实时更新 `MediaQuery.textScaler`。

## 4. 开发规范

### 新增 UI 文字时

- 从 `AppFonts` 的 6 个常量中选择最合适的档位，不要硬编码数字。
- 如果 6 档都不合适，先考虑是否真的需要新档位——TV 上用户感知不到 1-2px 差异。

### 动态字号例外

以下场景允许不使用 `AppFonts` 常量：

| 场景 | 说明 |
|------|------|
| 弹幕字号 | 用户可调，由 `SettingsService.danmakuFontSize` 控制 |
| 字幕字号 | 从 API 数据解析 |
| 动态计算 | 如 `badgeSize * 0.7`，按组件尺寸等比缩放 |
| `TabStyle.tabFontSize` | 走 `TabStyle` 常量体系（值为 16，等同 `sizeLG`） |

### 基准倍率

`main.dart` 中的 `_baseFontScaleMultiplier`（当前为 `1.0`）可用于整体微调设计基准。例如设为 `1.1` 则所有字号在用户"默认"档下自动放大 10%。

## 5. 相关文件

| 文件 | 职责 |
|------|------|
| `lib/config/app_style.dart` | `AppFonts` 字号常量定义 |
| `lib/main.dart` | 全局 `textScaler` 注入 |
| `lib/services/settings_service.dart` | `fontScale` 持久化 + `fontScaleOptions` 档位列表 |
| `lib/screens/home/settings/tabs/interface_settings.dart` | "字体大小" 设置 UI |
