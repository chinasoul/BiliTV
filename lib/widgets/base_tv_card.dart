import 'package:flutter/material.dart';
import '../core/focus/focus_navigation.dart';

/// TV 视频卡片基类
///
/// 使用统一的焦点管理系统，支持网格导航模式
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
  /// This will be wrapped in AspectRatio and Stack for glow/border
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

class _BaseTvCardState extends State<BaseTvCard>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;

  // 快速导航节流：记录上次焦点时间，短间隔内用 jumpTo 而非 animateTo
  DateTime _lastFocusTime = DateTime(0);
  static const _rapidThreshold = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _glowAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      widget.onFocus();
      _animController.forward();
      final now = DateTime.now();
      final isRapid = now.difference(_lastFocusTime) < _rapidThreshold;
      _lastFocusTime = now;
      // 等默认 showOnScreen 完成后，测量卡片在视口中的位置并调整
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToRevealPreviousRow(animate: !isRapid);
      });
    } else {
      _animController.reverse();
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

    // 卡片当前在视口中的 y 坐标（相对于 Scrollable widget 的原点）
    final cardInViewport = ro.localToGlobal(Offset.zero, ancestor: scrollableRO);
    final viewportHeight = scrollableRO.size.height;

    // 目标：卡片顶端位于视口高度的 20% 处
    final desiredY = viewportHeight * 0.2;
    final delta = cardInViewport.dy - desiredY;

    // 差距太小就不滚动（避免无意义微调）
    if (delta.abs() < 4.0) return;

    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (animate) {
      // 慢速导航：平滑动画
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      // 快速导航：直接跳转，避免大量动画对象堆积
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
      enableKeyRepeat: true, // 网格导航支持按住快速移动
      child: ScaleTransition(
        scale: _scaleAnim,
        child: RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面区域
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 阴影层
                    Positioned.fill(
                      top: 10,
                      child: FadeTransition(
                        opacity: _glowAnim,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF81C784,
                                ).withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 图片与内容层
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: widget.imageContent,
                        ),
                        // 聚焦时的边框
                        if (_isFocused)
                          IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                  strokeAlign: BorderSide.strokeAlignOutside,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 底部信息区域
              widget.infoContentBuilder(context, _isFocused),
            ],
          ),
        ),
      ),
    );
  }
}
