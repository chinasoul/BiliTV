import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════
//  全局 UI 样式常量
//  修改此文件即可统一调整整个 App 的视觉风格
// ════════════════════════════════════════════════════════════════════

/// 全局颜色
abstract final class AppColors {
  // ── 背景色 ────────────────────────────────────────────────
  /// 主背景色（App 主体、Tab 页面）
  static const Color background = Color(0xFF121212);

  /// 卡片/面板背景色
  static const Color cardBackground = Color(0xFF2D2D2D);

  /// 对话框 / 弹窗 / 设置面板背景色
  static const Color panelBackground = Color(0xFF1F1F1F);

  /// 按钮/选项区域背景色
  static const Color surfaceBackground = Color(0xFF2A2A2A);

  // ── 文字色 ────────────────────────────────────────────────
  /// 主文字色（标题、重要内容）
  static const Color textPrimary = Colors.white;

  /// 二级文字色（描述、正文）
  static const Color textSecondary = Colors.white70;

  /// 三级文字色（辅助信息：作者、时间、副标题）
  static const Color textTertiary = Colors.white54;

  /// 四级文字色（提示、占位文字、弱信息）
  static const Color textHint = Colors.white38;

  /// 非活跃/未选中文字色
  static const Color textInactive = Colors.grey;

  // ── 分割线 & 边框 ────────────────────────────────────────
  /// 列表项悬浮 / 未选中背景
  static const Color hoverBackground = Colors.white10;

  /// 白色弱分割线
  static const Color dividerLight = Colors.white10;

  // ── 遮罩 & 叠加色 ────────────────────────────────────────
  /// Toast / 弹窗遮罩背景
  static Color toastBackground = Colors.black.withValues(alpha: 0.7);

  /// 卡片文字区域遮罩背景
  static Color cardOverlay = Colors.black.withValues(alpha: 0.9);

  /// 轻遮罩（选项悬浮等）
  static Color overlayLight = Colors.white.withValues(alpha: 0.1);

  /// 中等遮罩（聚焦提示等）
  static Color overlayMedium = Colors.white.withValues(alpha: 0.7);

  // ── 主题色相关 ────────────────────────────────────────────
  /// 聚焦背景 alpha 值
  static const double focusAlpha = 0.6;

  /// 开关 active track alpha 值
  static const double switchActiveAlpha = 0.5;
}

/// 全局文字样式
abstract final class AppFonts {
  // ── 字号 ──────────────────────────────────────────────────
  /// 极小字号（徽章、角标）
  static const double sizeXS = 10;

  /// 小字号（副标题、辅助信息、进度条标签）
  static const double sizeSM = 12;

  /// 正文字号（描述、列表项内容）
  static const double sizeMD = 14;

  /// 中大字号（按钮、Tab 标签、设置项标题）
  static const double sizeLG = 16;

  /// 大字号（空状态提示、面板标题）
  static const double sizeXL = 20;

  /// 超大字号（页面标题、强调文字）
  static const double sizeXXL = 24;

  // ── 字重 ──────────────────────────────────────────────────
  /// 半粗（卡片辅助信息加粗）
  static const FontWeight medium = FontWeight.w500;

  /// 粗体（标题、选中项）
  static const FontWeight bold = FontWeight.bold;
}

/// 全局圆角
abstract final class AppRadius {
  /// 小圆角（进度条、标签、小按钮）
  static const double sm = 4;

  /// 中圆角（卡片、按钮、设置项、输入框）
  static const double md = 8;

  /// 中大圆角（面板、弹窗、侧边栏项）
  static const double lg = 12;

  /// 大圆角（药丸按钮、搜索栏）
  static const double xl = 20;

  /// 全圆（头像）
  static const double full = 999;
}

/// 全局间距
abstract final class AppSpacing {
  /// 设置内容区域水平 padding（16 + settingRowPadding 14 = 30，与 Tab 文字对齐）
  static const EdgeInsets settingContentPadding =
      EdgeInsets.symmetric(horizontal: 16);

  /// 设置项行内水平 padding
  static const EdgeInsets settingRowPadding =
      EdgeInsets.symmetric(horizontal: 14);

  /// 设置项 section 标题左侧 padding（与 settingRowPadding 对齐）
  static const EdgeInsets settingSectionTitlePadding =
      EdgeInsets.only(left: 14, bottom: 8);

  /// 设置项之间的间距
  static const double settingItemGap = 6;

  /// 设置项最小高度（统一所有 toggle / action / dropdown 行高）
  static const double settingItemMinHeight = 44;

  /// 设置项右侧组件统一高度（Switch / button / dropdown 对齐）
  static const double settingItemRightHeight = 32;

  /// 设置项内部垂直 padding
  static const double settingItemVerticalPadding = 6;

  /// 空状态区域 padding
  static const EdgeInsets emptyStatePadding = EdgeInsets.all(20);
}

/// 全局动画
abstract final class AppAnimation {
  /// 快速动画（按钮反馈、微小变化）
  static const Duration fast = Duration(milliseconds: 150);

  /// 默认动画（面板展开收起、焦点切换）
  static const Duration normal = Duration(milliseconds: 200);

  /// 滚动动画
  static const Duration scroll = Duration(milliseconds: 500);

  /// 慢速动画（页面切换、大面积过渡）
  static const Duration slow = Duration(milliseconds: 300);
}

/// 视频网格布局
abstract final class GridStyle {
  /// 默认视频卡片宽高比
  static const double videoAspectRatio = 320 / 280;

  /// 网格列间距
  static const double crossAxisSpacing = 20;

  /// 网格行间距
  static const double mainAxisSpacing = 10;
}

/// Tab 页面布局（首页、动态、关注、历史、直播、设置共享）
abstract final class TabStyle {
  // ── Header 区域 ──────────────────────────────────────────

  /// Header 固定背景色
  static const Color headerBackgroundColor = AppColors.background;

  /// Header 外层 padding（适用于 Positioned / Container）
  static const EdgeInsets headerPadding =
      EdgeInsets.only(left: 20, right: 20, top: 12);

  /// Header 固定高度（单行 tab 场景）
  static const double headerHeight = 56;

  // ── Tab 标签 ─────────────────────────────────────────────

  /// Tab 标签内边距
  static const EdgeInsets tabPadding = EdgeInsets.fromLTRB(10, 3, 10, 3);

  /// Tab 标签圆角
  static const double tabBorderRadius = 8;

  /// Tab 文字大小
  static const double tabFontSize = 16;

  /// Tab 文字行高
  static const double tabLineHeight = 1.2;

  /// Tab 文字与下划线之间的间距
  static const double tabUnderlineGap = 4;

  /// Tab 下划线高度
  static const double tabUnderlineHeight = 3;

  /// Tab 下划线宽度
  static const double tabUnderlineWidth = 20;

  /// Tab 下划线圆角
  static const double tabUnderlineRadius = 1.5;

  // ── 内容区域 ─────────────────────────────────────────────

  /// 内容网格默认 padding（首行与 header 不重叠）
  static const EdgeInsets contentPadding =
      EdgeInsets.fromLTRB(24, 60, 24, 80);

  // ── 时间显示 ─────────────────────────────────────────────

  /// 右上角 TimeDisplay 的 top 偏移
  static const double timeDisplayTop = 10;

  /// 右上角 TimeDisplay 的 right 偏移
  static const double timeDisplayRight = 14;
}
