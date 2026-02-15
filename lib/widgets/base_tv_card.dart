import 'package:flutter/material.dart';
import '../core/focus/focus_navigation.dart';
import '../services/settings_service.dart';

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
    final scrollableRO = scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    final cardInViewport = ro.localToGlobal(Offset.zero, ancestor: scrollableRO);
    final viewportHeight = scrollableRO.size.height;

    final desiredY = viewportHeight * 0.2;
    final delta = cardInViewport.dy - desiredY;

    if (delta.abs() < 4.0) return;

    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

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
      child: RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _isFocused ? SettingsService.themeColor.withValues(alpha: 0.6) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面区域
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
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
    );
  }
}
