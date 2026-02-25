import 'package:flutter/material.dart';
import '../core/focus/focus_navigation.dart';
import '../services/settings_service.dart';
import '../config/app_style.dart';

/// TV 视频卡片基类
///
/// 使用统一的焦点管理系统，支持网格导航模式
/// 聚焦效果：主题色背景 + 白色边框（无缩放、无发光，性能友好）
class BaseTvCard extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onBack;
  final bool autofocus;
  final FocusNode? focusNode;

  /// The main image content (usually CachedNetworkImage)
  final Widget imageContent;

  /// The information content below the image, aware of focus state
  final Widget Function(BuildContext context, bool isFocused)
  infoContentBuilder;

  /// Grid boundary flags
  final bool isFirst;
  final bool isLast;

  /// 当前卡片在列表中的索引
  final int index;

  /// 网格列数（用于判断是否第一行）
  final int gridColumns;

  /// 顶部遮挡区域高度（如分类标签、收藏夹标签等）
  final double topOffset;

  const BaseTvCard({
    super.key,
    required this.onTap,
    required this.onFocus,
    required this.imageContent,
    required this.infoContentBuilder,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onBack,
    this.autofocus = false,
    this.focusNode,
    this.isFirst = false,
    this.isLast = false,
    this.index = 0,
    this.gridColumns = 4,
    this.topOffset = TabStyle.defaultTopOffset,
  });

  @override
  State<BaseTvCard> createState() => _BaseTvCardState();
}

class _BaseTvCardState extends State<BaseTvCard> {
  bool _isFocused = false;

  // 快速导航节流：记录上次焦点时间，短间隔内用 jumpTo 而非 animateTo
  DateTime _lastFocusTime = DateTime(0);
  static const _rapidThreshold = Duration(milliseconds: 150);

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      widget.onFocus();
      final now = DateTime.now();
      final isRapid = now.difference(_lastFocusTime) < _rapidThreshold;
      _lastFocusTime = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToRevealPreviousRow(animate: !isRapid);
      });
    }
  }

  void _scrollToRevealPreviousRow({required bool animate}) {
    final ro = context.findRenderObject() as RenderBox?;
    if (ro == null || !ro.hasSize) return;

    final scrollableState = Scrollable.maybeOf(context);
    if (scrollableState == null) return;

    final position = scrollableState.position;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    final cardInViewport = ro.localToGlobal(
      Offset.zero,
      ancestor: scrollableRO,
    );
    final viewportHeight = scrollableRO.size.height;
    final cardHeight = ro.size.height;
    final cardTop = cardInViewport.dy;
    final cardBottom = cardTop + cardHeight;

    // 顶部安全边界：考虑顶部遮挡区域 + 露出上一行的比例
    final revealHeight = cardHeight * TabStyle.scrollRevealRatio;
    final topBoundary = widget.topOffset + revealHeight;

    // 底部安全边界：屏幕底部留出空间，用于显示下一行
    final bottomBoundary = viewportHeight - revealHeight;

    // 判断是否是第一行
    final isFirstRow = widget.index < widget.gridColumns;

    double? targetScrollOffset;

    if (isFirstRow) {
      // 第一行：确保卡片顶部在顶部边界位置（初始位置）
      if ((cardTop - topBoundary).abs() > 50) {
        final delta = cardTop - topBoundary;
        targetScrollOffset = position.pixels + delta;
      }
    } else if (cardBottom > bottomBoundary) {
      // 卡片底部超出底部边界：向上滚动，使卡片底部对齐到边界
      final delta = cardBottom - bottomBoundary;
      targetScrollOffset = position.pixels + delta;
    } else if (cardTop < topBoundary) {
      // 卡片顶部超出顶部边界：向下滚动，使卡片顶部对齐到边界
      final delta = cardTop - topBoundary;
      targetScrollOffset = position.pixels + delta;
    }
    // 卡片在安全区域内：不滚动

    if (targetScrollOffset == null) return;

    final target = targetScrollOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    // 只有滚动距离超过阈值才执行
    if ((position.pixels - target).abs() < 4.0) return;

    if (animate) {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      position.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.grid,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onExitLeft: widget.onMoveLeft,
      onExitRight: widget.onMoveRight,
      onExitUp: widget.onMoveUp,
      onExitDown: widget.onMoveDown,
      onSelect: widget.onTap,
      isFirst: widget.isFirst,
      isLast: widget.isLast,
      enableKeyRepeat: true,
      child: Builder(
        builder: (ctx) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _isFocused
                      ? SettingsService.themeColor.withValues(alpha: 0.6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面区域
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        clipBehavior: Clip.hardEdge,
                        borderRadius: BorderRadius.circular(8),
                        child: widget.imageContent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 底部信息区域
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: widget.infoContentBuilder(context, _isFocused),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
