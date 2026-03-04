import 'package:flutter/material.dart';
import '../services/settings_service.dart';

// ════════════════════════════════════════════════════════════════════
//  全局 UI 样式常量
//  修改此文件即可统一调整整个 App 的视觉风格
// ════════════════════════════════════════════════════════════════════

/// 全局颜色
abstract final class AppColors {
  /// 当前是否浅色主题
  static bool get isLight => SettingsService.themeMode == ThemeMode.light;

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
  /// 主文字色（聚焦标题、强调内容）
  static const Color textPrimary = Colors.white;

  /// 二级文字色（未聚焦卡片标题、正文）
  static const Color textSecondary = Color(0xDEFFFFFF); // 87% white

  /// 三级文字色（UP 主、时间、副标题）
  static const Color textTertiary = Colors.white70;

  /// 四级文字色（提示、占位文字、弱信息）
  static const Color textHint = Colors.white54;

  /// 五级文字色（禁用、极弱提示）
  static const Color textDisabled = Colors.white38;

  /// 非活跃/未选中文字色
  static const Color textInactive = Colors.grey;

  /// 主题自适应主文字色
  static Color get primaryText => isLight ? Colors.black : Colors.white;

  /// 主题自适应次级文字色
  static Color get secondaryText => isLight ? Colors.black87 : textSecondary;

  /// 主题自适应弱文字色
  static Color get inactiveText => isLight ? Colors.black54 : textTertiary;

  /// 主题自适应禁用文字色
  static Color get disabledText => isLight ? Colors.black38 : textDisabled;

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

  /// 视频卡片底部渐变遮罩颜色（开发者选项可调）
  static Color get videoCardOverlay =>
      Colors.black.withValues(alpha: SettingsService.videoCardOverlayAlpha);

  /// 评论弹窗遮罩背景（开发者选项可调）
  static Color get popupBarrier =>
      Colors.black.withValues(alpha: SettingsService.popupBarrierAlpha);

  /// 评论侧栏背景色（开发者选项可调）
  static Color get panelBackgroundColor =>
      Color(SettingsService.panelBackgroundColorValue);

  /// 评论侧栏背景透明度（开发者选项可调）
  static double get panelBackgroundAlpha =>
      SettingsService.panelBackgroundAlpha;

  /// 右侧面板背景（颜色 + alpha）
  static Color get sidePanelBackground => panelBackgroundColor
      .withValues(alpha: panelBackgroundAlpha);

  /// 右侧面板背景（浅色主题自动提亮，避免黑字低对比）
  static Color get sidePanelBackgroundAdaptive {
    final base = sidePanelBackground;
    if (!isLight) return base;
    final mixed = Color.lerp(base, Colors.white, 0.88) ?? Colors.white;
    final alpha = panelBackgroundAlpha < 0.92 ? 0.92 : panelBackgroundAlpha;
    return mixed.withValues(alpha: alpha);
  }

  /// 评论弹窗背景色（开发者选项可调）
  static Color get popupBackgroundColor =>
      Color(SettingsService.popupBackgroundColorValue);

  /// 评论弹窗背景透明度（开发者选项可调）
  static double get popupBackgroundAlpha =>
      SettingsService.popupBackgroundAlpha;

  /// 评论弹窗背景（颜色 + alpha）
  static Color get popupBackground => popupBackgroundColor
      .withValues(alpha: popupBackgroundAlpha);

  /// 评论弹窗背景（浅色主题自动提亮，避免黑字低对比）
  static Color get popupBackgroundAdaptive {
    final base = popupBackground;
    if (!isLight) return base;
    final mixed = Color.lerp(base, Colors.white, 0.9) ?? Colors.white;
    final alpha = popupBackgroundAlpha < 0.9 ? 0.9 : popupBackgroundAlpha;
    return mixed.withValues(alpha: alpha);
  }

  /// 顶部 tab/header 背景（主题自适应）
  static Color get headerBackground =>
      isLight ? const Color(0xFFF5F5F5) : background;

  /// 首页侧边导航背景（主题自适应）
  static Color get sidebarBackground =>
      isLight ? const Color(0xFFEFEFEF) : const Color(0xFF1E1E1E);

  /// 侧边导航选中但未聚焦背景（主题自适应）
  static Color get navItemSelectedBackground =>
      isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white10;

  // ── 主题色相关 ────────────────────────────────────────────
  /// 聚焦背景 alpha 值
  static double get focusAlpha => SettingsService.videoCardThemeAlpha;

  /// 评论项聚焦背景 alpha 值（开发者选项可调）
  static double get commentFocusAlpha => SettingsService.commentFocusAlpha;

  /// 开关 active track alpha 值
  static const double switchActiveAlpha = 0.5;
}

/// 全局文字样式
abstract final class AppFonts {
  // ── 字号（6 档，TV 观看距离下每档间距 ≥ 2px 确保可辨）──
  /// 角标、弱提示信息
  static const double sizeXS = 10;

  /// 辅助信息、副标题、进度条标签
  static const double sizeSM = 12;

  /// 正文、列表项内容
  static const double sizeMD = 14;

  /// 按钮、Tab 标签、设置项标题
  static const double sizeLG = 16;

  /// 面板标题、空状态提示
  static const double sizeXL = 20;

  /// 页面大标题、强调文字
  static const double sizeXXL = 24;

  // ── 字重 ──────────────────────────────────────────────────
  /// 常规（辅助信息）
  static const FontWeight regular = FontWeight.w400;

  /// 半粗（未聚焦卡片标题）
  static const FontWeight medium = FontWeight.w500;

  /// 次粗（卡片辅助信息、强调正文）
  static const FontWeight semibold = FontWeight.w600;

  /// 粗体（聚焦标题、选中项）
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
  static const EdgeInsets settingContentPadding = EdgeInsets.symmetric(
    horizontal: 16,
  );

  /// 设置项行内水平 padding
  static const EdgeInsets settingRowPadding = EdgeInsets.symmetric(
    horizontal: 14,
  );

  /// 设置项 section 标题左侧 padding（与 settingRowPadding 对齐）
  static const EdgeInsets settingSectionTitlePadding = EdgeInsets.only(
    left: 14,
    bottom: 8,
  );

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

  /// 根据字体缩放和网格列数动态计算视频卡片宽高比。
  /// 列数越多（卡片越窄）时，自动增加高度，防止底部文字区被挤压。
  static double videoCardAspectRatio(BuildContext context, int gridColumns) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
    final cols = gridColumns.clamp(3, 6);

    // 估算当前网格单卡宽度（使用偏保守的水平 padding），
    // 再由“封面高度 + 文字区最小高度”反推安全比例。
    final viewportWidth = MediaQuery.sizeOf(context).width;
    const horizontalPadding = 60.0;
    const crossAxisSpacing = 20.0;
    final availableWidth =
        (viewportWidth - horizontalPadding - crossAxisSpacing * (cols - 1))
            .clamp(120.0, viewportWidth);
    final cardWidth = availableWidth / cols;

    final imageHeight = cardWidth * 9.0 / 16.0;
    final textScaleProgress = ((textScale - 1.0) / 0.4).clamp(0.0, 1.0);
    // 底部信息区预算：标题 + 间距 + UP 主行 + 上下内边距 + 大字号冗余
    // 普通模式下标题可显示 2 行，需要额外预算高度，防止网格内文字溢出。
    final extraTitleHeight =
        SettingsService.focusedTitleDisplayMode == FocusedTitleDisplayMode.normal
        ? 18.0
        : 0.0;
    final infoHeight = 58.0 + 20.0 * textScaleProgress + extraTitleHeight;
    final cardHeight = imageHeight + infoHeight;

    return cardWidth / cardHeight;
  }

  /// 网格列间距
  static const double crossAxisSpacing = 20;

  /// 网格行间距
  static const double mainAxisSpacing = 10;
}

/// Tab 页面布局（首页、动态、关注、历史、直播、设置共享）
abstract final class TabStyle {
  // ── Header 区域 ──────────────────────────────────────────

  /// Header 固定背景色
  static Color get headerBackgroundColor => AppColors.headerBackground;

  /// Header 外层 padding（适用于 Positioned / Container）
  static const EdgeInsets headerPadding = EdgeInsets.only(
    left: 20,
    right: 20,
    top: 12,
  );

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
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(24, 60, 24, 80);

  /// 默认顶部遮挡区域高度（分类标签等）
  static const double defaultTopOffset = 60.0;

  // ── 滚动行为 ─────────────────────────────────────────────

  /// 滚动时露出相邻行的比例（卡片高度的 1/4）
  static const double scrollRevealRatio = 0.25;

  // ── 时间显示 ─────────────────────────────────────────────

  /// 右上角 TimeDisplay 的 top 偏移
  static const double timeDisplayTop = 10;

  /// 右上角 TimeDisplay 的 right 偏移
  static const double timeDisplayRight = 14;
}

/// 设置弹窗样式（确认框/选择框）
abstract final class SettingsDialogStyle {
  /// 背景遮罩
  static Color get barrierColor => Colors.black.withValues(alpha: 0.7);

  /// 弹窗背景（浅色主题使用浅底，避免黑字/深底冲突）
  static Color get background =>
      AppColors.isLight ? const Color(0xFFF5F5F5) : AppColors.panelBackground;

  /// 弹窗动作按钮文字色
  static Color get actionForeground => AppColors.primaryText;
}

/// 播放器右侧面板样式
abstract final class SidePanelStyle {
  /// 面板背景色（开发者选项可调）
  static Color get backgroundColor =>
      Color(SettingsService.panelBackgroundColorValue);

  /// 面板背景透明度（开发者选项可调）
  static double get backgroundAlpha => SettingsService.panelBackgroundAlpha;

  /// 获取带透明度的背景色
  static Color get background => AppColors.sidePanelBackgroundAdaptive;
}

/// 播放器控制栏样式
abstract final class PlayerControlsStyle {
  /// 按钮区域占屏幕宽度的比例
  static const double buttonAreaRatio = 0.5;

  /// 按钮间距占按钮大小的比例
  static const double spacingRatio = 0.4;

  /// 信息文字字体占按钮大小的比例
  static const double infoFontRatio = 0.35;

  /// 信息区间距占按钮大小的比例
  static const double infoSpacingRatio = 0.4;
}
