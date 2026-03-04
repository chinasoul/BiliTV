import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 使用 Overlay 显示数值选择弹窗
class ValuePickerOverlay {
  static OverlayEntry? _overlayEntry;
  static FocusNode? _callerFocusNode;
  static DateTime? _lastCloseTime;

  /// 检查弹窗是否正在显示
  static bool get isShowing => _overlayEntry != null;

  /// 关闭弹窗（供外部调用，如处理返回键）
  /// 返回 true 表示弹窗已关闭或刚刚关闭（200ms内）
  static bool close() {
    if (_overlayEntry != null) {
      _closeInternal();
      return true;
    }
    // 检查是否刚刚关闭（防止 goBack 键重复处理）
    if (_lastCloseTime != null &&
        DateTime.now().difference(_lastCloseTime!) <
            const Duration(milliseconds: 200)) {
      return true;
    }
    return false;
  }

  /// 显示数值选择弹窗
  static void show<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required T currentValue,
    required String Function(T) itemLabel,
    String Function(T)? itemSubtitle,
    Widget Function(T item, bool isFocused, bool isSelected)? itemBuilder,
    required ValueChanged<T> onSelected,
  }) {
    _callerFocusNode = FocusManager.instance.primaryFocus;
    _lastCloseTime = null;

    _overlayEntry = OverlayEntry(
      builder: (context) => _ValuePickerContent<T>(
        title: title,
        items: items,
        itemLabel: itemLabel,
        itemSubtitle: itemSubtitle,
        itemBuilder: itemBuilder,
        currentValue: currentValue,
        onSelected: (selectedValue) {
          _closeInternal();
          onSelected(selectedValue);
        },
        onClose: _closeInternal,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void _closeInternal() {
    final focusNode = _callerFocusNode;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _callerFocusNode = null;
    _lastCloseTime = DateTime.now();

    if (focusNode != null && focusNode.canRequestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusNode.requestFocus();
      });
    }
  }
}

/// 弹窗内容
class _ValuePickerContent<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) itemLabel;
  final String Function(T)? itemSubtitle;
  final Widget Function(T item, bool isFocused, bool isSelected)? itemBuilder;
  final T currentValue;
  final ValueChanged<T> onSelected;
  final VoidCallback onClose;

  const _ValuePickerContent({
    required this.title,
    required this.items,
    required this.itemLabel,
    this.itemSubtitle,
    this.itemBuilder,
    required this.currentValue,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_ValuePickerContent<T>> createState() => _ValuePickerContentState<T>();
}

class _ValuePickerContentState<T> extends State<_ValuePickerContent<T>>
    with SingleTickerProviderStateMixin {
  late int _focusedIndex;
  late List<FocusNode> _focusNodes;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.items.indexOf(widget.currentValue);
    if (_focusedIndex < 0) _focusedIndex = 0;
    _focusNodes = List.generate(widget.items.length, (_) => FocusNode());

    _animationController = AnimationController(
      vsync: this,
      duration: AppAnimation.normal,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToItem(_focusedIndex, animate: false);
      if (_focusNodes.isNotEmpty && _focusedIndex < _focusNodes.length) {
        _focusNodes[_focusedIndex].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  final Map<int, GlobalKey> _itemKeys = {};

  void _scrollToItem(int index, {bool animate = true}) {
    if (!mounted) return;
    final key = _itemKeys[index];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: animate ? AppAnimation.fast : Duration.zero,
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }

  void _moveFocus(int delta) {
    final newIndex = (_focusedIndex + delta).clamp(0, widget.items.length - 1);
    if (newIndex != _focusedIndex) {
      setState(() => _focusedIndex = newIndex);
      _scrollToItem(newIndex);
      _focusNodes[newIndex].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final themeColor = SettingsService.themeColor;

    final hasSubtitles =
        widget.itemSubtitle != null &&
        widget.items.any((item) => widget.itemSubtitle!(item).trim().isNotEmpty);
    final itemHeight = hasSubtitles ? 64.0 : 48.0;
    final itemCount = widget.items.length;
    const maxVisibleItems = 7;
    final visibleItems = itemCount > maxVisibleItems
        ? maxVisibleItems
        : itemCount;
    final listHeight = visibleItems * itemHeight;
    final popupWidth = screenSize.width * 0.3;
    const titleHeight = 48.0;
    final popupHeight = listHeight + titleHeight;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: FocusScope(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                if (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack) {
                  widget.onClose();
                  return KeyEventResult.handled;
                }
              }
              return TvKeyHandler.handleNavigationWithRepeat(
                event,
                onUp: () => _moveFocus(-1),
                onDown: () => _moveFocus(1),
                onLeft: widget.onClose,
                blockRight: true,
                onSelect: () => widget.onSelected(widget.items[_focusedIndex]),
              );
            },
            child: Stack(
              children: [
                // 遮罩
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                // 弹窗
                Center(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: popupWidth,
                        height: popupHeight,
                        decoration: BoxDecoration(
                          color: AppColors.isLight
                              ? const Color(0xFFF5F5F5)
                              : AppColors.panelBackground,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: Column(
                            children: [
                              // 标题
                              Container(
                                height: titleHeight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    widget.title,
                                    style: TextStyle(
                                      color: AppColors.primaryText,
                                      fontSize: AppFonts.sizeLG,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                              // 列表
                              Expanded(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: EdgeInsets.zero,
                                  itemCount: widget.items.length,
                                  itemBuilder: (context, index) {
                                    final item = widget.items[index];
                                    final subtitle = widget.itemSubtitle == null
                                        ? ''
                                        : widget.itemSubtitle!(item);
                                    final isSelected =
                                        item == widget.currentValue;
                                    final isFocused = index == _focusedIndex;

                                    return Focus(
                                      key: _itemKeys.putIfAbsent(index, () => GlobalKey()),
                                      focusNode: _focusNodes[index],
                                      onFocusChange: (hasFocus) {
                                        if (hasFocus &&
                                            index != _focusedIndex) {
                                          setState(() => _focusedIndex = index);
                                        }
                                      },
                                      child: Builder(
                                        builder: (_) => MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTapDown: (_) {
                                              if (index != _focusedIndex) {
                                                setState(
                                                  () => _focusedIndex = index,
                                                );
                                              }
                                              _focusNodes[index].requestFocus();
                                              _scrollToItem(
                                                index,
                                                animate: false,
                                              );
                                            },
                                            onTap: () => widget.onSelected(item),
                                            child: Container(
                                          height: itemHeight,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isFocused
                                                ? themeColor.withValues(
                                                    alpha: AppColors.focusAlpha,
                                                  )
                                                : Colors.transparent,
                                            border: isFocused
                                                ? Border(
                                                    left: BorderSide(
                                                      color: themeColor,
                                                      width: 3,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                child: isSelected
                                                    ? Icon(
                                                        Icons.check,
                                                        color: themeColor,
                                                        size: 18,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: widget.itemBuilder != null
                                                    ? widget.itemBuilder!(
                                                        item,
                                                        isFocused,
                                                        isSelected,
                                                      )
                                                    : Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment.center,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            widget.itemLabel(
                                                              item,
                                                            ),
                                                            style: TextStyle(
                                                              color: isFocused
                                                                  ? AppColors.primaryText
                                                                  : isSelected
                                                                  ? AppColors.secondaryText
                                                                  : AppColors.inactiveText,
                                                              fontSize: AppFonts.sizeMD,
                                                              fontWeight: isSelected
                                                                  ? FontWeight.bold
                                                                  : AppFonts.regular,
                                                            ),
                                                          ),
                                                          if (subtitle
                                                              .trim()
                                                              .isNotEmpty)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    top: 2,
                                                                  ),
                                                              child: Text(
                                                                subtitle,
                                                                style: TextStyle(
                                                                  color: isFocused
                                                                      ? AppColors.inactiveText
                                                                      : AppColors.disabledText,
                                                                  fontSize: AppFonts.sizeXS,
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                              ),
                                            ],
                                          ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
