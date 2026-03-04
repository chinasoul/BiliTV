import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import '../models/comment.dart';
import '../services/bilibili_api.dart';
import '../services/settings_service.dart';
import '../config/app_style.dart';
import '../utils/image_url_utils.dart';

/// 评论列表（共享组件），用于播放器侧面板和视频详情弹窗。
/// 返回键统一由自身处理（调用 onClose）。
class CommentListView extends StatefulWidget {
  final int aid;
  final VoidCallback onClose;

  const CommentListView({
    super.key,
    required this.aid,
    required this.onClose,
  });

  @override
  State<CommentListView> createState() => _CommentListViewState();
}

class _CommentListViewState extends State<CommentListView> {
  static const double _topBoundary = 24.0;
  static const double _bottomPadding = 24.0;

  final List<Comment> _comments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _totalCount = 0;
  String? _nextOffset;
  bool _hasMore = true;
  int _sortMode = 3; // 3=热度, 2=时间

  final Map<int, List<Comment>> _cachedComments = {};
  final Map<int, int> _cachedTotalCount = {};
  final Map<int, String?> _cachedNextOffset = {};
  final Map<int, bool> _cachedHasMore = {};

  final Map<int, List<Comment>> _expandedReplies = {};
  final Map<int, int> _replyPages = {};
  final Map<int, bool> _replyHasMore = {};

  int _focusedIndex = 0; // 0+ = comment items, -1 = sort热度, -2 = sort时间
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _loadComments();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _loadComments({bool loadMore = false}) async {
    if (loadMore && (!_hasMore || _isLoadingMore)) return;

    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() => _isLoading = true);
    }

    final result = await BilibiliApi.getComments(
      oid: widget.aid,
      mode: _sortMode,
      nextOffset: loadMore ? _nextOffset : null,
    );

    if (!mounted) return;

    setState(() {
      if (!loadMore) {
        _comments.clear();
        _expandedReplies.clear();
        _replyPages.clear();
        _replyHasMore.clear();
      }
      _comments.addAll(result.comments);
      _totalCount = result.totalCount;
      _nextOffset = result.nextOffset;
      _hasMore = result.hasMore;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  Future<void> _toggleReplies(int index) async {
    final comment = _comments[index];
    if (comment.rcount == 0) return;

    if (_expandedReplies.containsKey(comment.rpid)) {
      setState(() {
        _expandedReplies.remove(comment.rpid);
        _replyPages.remove(comment.rpid);
        _replyHasMore.remove(comment.rpid);
      });
    } else {
      final replies = await BilibiliApi.getReplies(
        oid: widget.aid,
        root: comment.rpid,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _expandedReplies[comment.rpid] = replies;
        _replyPages[comment.rpid] = 1;
        _replyHasMore[comment.rpid] = replies.length >= 10;
      });
    }

    _ensureFocusedVisibleAfterLayout(
      allowPageFallback: true,
      movingDown: true,
    );
  }

  Future<void> _loadMoreReplies(int rpid) async {
    if (_replyHasMore[rpid] != true) return;
    final nextPage = (_replyPages[rpid] ?? 1) + 1;
    final replies = await BilibiliApi.getReplies(
      oid: widget.aid,
      root: rpid,
      page: nextPage,
    );
    if (!mounted) return;
    setState(() {
      _expandedReplies[rpid]?.addAll(replies);
      _replyPages[rpid] = nextPage;
      _replyHasMore[rpid] = replies.length >= 10;
    });
  }

  void _switchSort(int mode) {
    if (_sortMode == mode) return;

    if (_comments.isNotEmpty) {
      _cachedComments[_sortMode] = List.from(_comments);
      _cachedTotalCount[_sortMode] = _totalCount;
      _cachedNextOffset[_sortMode] = _nextOffset;
      _cachedHasMore[_sortMode] = _hasMore;
    }

    _sortMode = mode;
    _itemKeys.clear();
    _expandedReplies.clear();
    _replyPages.clear();
    _replyHasMore.clear();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    if (_cachedComments.containsKey(mode)) {
      setState(() {
        _comments.clear();
        _comments.addAll(_cachedComments[mode]!);
        _totalCount = _cachedTotalCount[mode] ?? 0;
        _nextOffset = _cachedNextOffset[mode];
        _hasMore = _cachedHasMore[mode] ?? true;
        _isLoading = false;
      });
      return;
    }

    _loadComments();
  }

  // ---------------------------------------------------------------------------
  // Focus / Scroll
  // ---------------------------------------------------------------------------

  void _scrollToFocused({bool allowPageFallback = false, bool movingDown = true}) {
    if (_comments.isEmpty || _focusedIndex < 0) return;
    if (!_scrollController.hasClients) return;

    if (_focusedIndex == 0) {
      if (_scrollController.offset > 0) _scrollController.jumpTo(0);
      return;
    }

    final key = _itemKeys[_focusedIndex];
    if (key == null) {
      if (allowPageFallback) _pageScroll(movingDown);
      return;
    }
    final itemContext = key.currentContext;
    if (itemContext == null) {
      if (allowPageFallback) _pageScroll(movingDown);
      return;
    }
    final ro = itemContext.findRenderObject() as RenderBox?;
    if (ro == null || !ro.hasSize) {
      if (allowPageFallback) _pageScroll(movingDown);
      return;
    }

    final scrollableState = Scrollable.maybeOf(itemContext);
    if (scrollableState == null) return;
    final position = scrollableState.position;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    final itemInViewport = ro.localToGlobal(Offset.zero, ancestor: scrollableRO);
    final viewportHeight = scrollableRO.size.height;
    final itemHeight = ro.size.height;
    final itemTop = itemInViewport.dy;
    final itemBottom = itemTop + itemHeight;

    final bottomBoundary = viewportHeight - _bottomPadding;
    final oversizedThreshold = viewportHeight - _topBoundary - _bottomPadding;

    double? targetScrollOffset;

    if (itemHeight > oversizedThreshold) {
      if (itemTop > _topBoundary) {
        targetScrollOffset = position.pixels + (itemTop - _topBoundary);
      } else if (itemBottom < bottomBoundary) {
        targetScrollOffset = position.pixels + (itemBottom - bottomBoundary);
      }
    } else {
      if (itemBottom > bottomBoundary) {
        targetScrollOffset = position.pixels + (itemBottom - bottomBoundary);
      } else if (itemTop < _topBoundary) {
        targetScrollOffset = position.pixels + (itemTop - _topBoundary);
      }
    }

    if (targetScrollOffset == null) return;
    final target = targetScrollOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((position.pixels - target).abs() < 4.0) return;
    _scrollController.jumpTo(target);
  }

  void _pageScroll(bool down) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final step = (viewport * 0.75).clamp(120.0, 420.0);
    final target = (down ? position.pixels + step : position.pixels - step)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1.0) return;
    _scrollController.jumpTo(target);
  }

  bool _scrollFocusedItemContent({required bool down}) {
    if (_comments.isEmpty || _focusedIndex < 0) return false;
    if (!_scrollController.hasClients) return false;

    final key = _itemKeys[_focusedIndex];
    if (key == null) return false;
    final itemContext = key.currentContext;
    if (itemContext == null) return false;

    final itemRO = itemContext.findRenderObject() as RenderBox?;
    if (itemRO == null || !itemRO.hasSize) return false;

    final scrollableState = Scrollable.maybeOf(itemContext);
    if (scrollableState == null) return false;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return false;

    final position = scrollableState.position;
    final viewportHeight = scrollableRO.size.height;
    final itemTop =
        itemRO.localToGlobal(Offset.zero, ancestor: scrollableRO).dy;
    final itemBottom = itemTop + itemRO.size.height;

    final bottomBoundary = viewportHeight - _bottomPadding;
    final pageStep = (viewportHeight * 0.7).clamp(120.0, 420.0);

    double? target;
    if (down && itemBottom > bottomBoundary + 1) {
      final delta = itemBottom - bottomBoundary;
      target = (position.pixels + delta.clamp(0.0, pageStep))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
    } else if (!down && itemTop < _topBoundary - 1) {
      final delta = _topBoundary - itemTop;
      target = (position.pixels - delta.clamp(0.0, pageStep))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
    }

    if (target == null || (target - position.pixels).abs() < 1.0) {
      return false;
    }
    _scrollController.jumpTo(target);
    return true;
  }

  bool _isFocusedItemOutsideViewport() {
    if (_comments.isEmpty || _focusedIndex < 0) return false;
    if (!_scrollController.hasClients) return false;

    final key = _itemKeys[_focusedIndex];
    final itemContext = key?.currentContext;
    if (itemContext == null) return true;

    final itemRO = itemContext.findRenderObject() as RenderBox?;
    if (itemRO == null || !itemRO.hasSize) return true;

    final scrollableState = Scrollable.maybeOf(itemContext);
    if (scrollableState == null) return true;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return true;

    final itemTop =
        itemRO.localToGlobal(Offset.zero, ancestor: scrollableRO).dy;
    final itemBottom = itemTop + itemRO.size.height;
    final viewportHeight = scrollableRO.size.height;
    final bottomBoundary = viewportHeight - _bottomPadding;

    return itemBottom < _topBoundary || itemTop > bottomBoundary;
  }

  void _ensureFocusedVisibleAfterLayout({
    int retries = 3,
    bool allowPageFallback = false,
    bool movingDown = true,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_focusNode.hasFocus) _focusNode.requestFocus();

      _scrollToFocused(
        allowPageFallback: allowPageFallback,
        movingDown: movingDown,
      );
      if (retries > 0 && _isFocusedItemOutsideViewport()) {
        _ensureFocusedVisibleAfterLayout(
          retries: retries - 1,
          allowPageFallback: allowPageFallback,
          movingDown: movingDown,
        );
      }
    });
  }

  bool _isCurrentExpanded() {
    if (_focusedIndex < 0 || _focusedIndex >= _comments.length) return false;
    return _expandedReplies.containsKey(_comments[_focusedIndex].rpid);
  }

  bool _isItemBuilt(int index) {
    final key = _itemKeys[index];
    return key != null && key.currentContext != null;
  }

  void _moveFocusBy(int delta) {
    final nextIndex = (_focusedIndex + delta).clamp(0, _comments.length - 1);
    if (nextIndex == _focusedIndex) return;

    setState(() => _focusedIndex = nextIndex);
    final down = delta > 0;
    _ensureFocusedVisibleAfterLayout(
      retries: 3,
      allowPageFallback: true,
      movingDown: down,
    );
  }

  // ---------------------------------------------------------------------------
  // Key handling
  // ---------------------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {

    // 排序按钮区域
    if (_focusedIndex < 0) {
      return TvKeyHandler.handleNavigation(
        event,
        onLeft: () {
          if (_focusedIndex == -2) {
            setState(() => _focusedIndex = -1);
            if (SettingsService.focusSwitchTab) _switchSort(3);
          } else {
            widget.onClose();
          }
        },
        onRight: () {
          if (_focusedIndex == -1) {
            setState(() => _focusedIndex = -2);
            if (SettingsService.focusSwitchTab) _switchSort(2);
          }
        },
        onDown: () {
          if (_comments.isNotEmpty) {
            setState(() => _focusedIndex = 0);
            _scrollToFocused();
          }
        },
        onSelect: () {
          _switchSort(_focusedIndex == -1 ? 3 : 2);
        },
        blockUp: true,
      );
    }

    // 评论列表区域
    final isKeyDown = event is KeyDownEvent;

    final upDownResult = TvKeyHandler.handleNavigationWithRepeat(
      event,
      onUp: () {
        if (_scrollFocusedItemContent(down: false)) return;
        if (_focusedIndex > 0) {
          if (_isCurrentExpanded() && !_isItemBuilt(_focusedIndex - 1)) {
            _pageScroll(false);
            return;
          }
          _moveFocusBy(-1);
        } else if (isKeyDown) {
          setState(() => _focusedIndex = _sortMode == 3 ? -1 : -2);
        }
      },
      onDown: () {
        if (_scrollFocusedItemContent(down: true)) return;
        if (_focusedIndex < _comments.length - 1) {
          if (_isCurrentExpanded() && !_isItemBuilt(_focusedIndex + 1)) {
            _pageScroll(true);
            return;
          }
          _moveFocusBy(1);
          if (_focusedIndex >= _comments.length - 3) {
            _loadComments(loadMore: true);
          }
        }
      },
    );
    if (upDownResult == KeyEventResult.handled) return upDownResult;

    return TvKeyHandler.handleSinglePress(
      event,
      onLeft: () => widget.onClose(),
      onSelect: () {
        if (_focusedIndex >= 0 && _focusedIndex < _comments.length) {
          _toggleReplies(_focusedIndex);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          _buildHeader(),
          Divider(color: AppColors.navItemSelectedBackground, height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final themeColor = SettingsService.themeColor;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.comment_outlined, color: AppColors.primaryText, size: 20),
          const SizedBox(width: 8),
          Text(
            '评论 $_totalCount',
            style: TextStyle(
              color: AppColors.primaryText,
              fontSize: AppFonts.sizeLG,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _buildSortChip('最热', -1, _sortMode == 3, themeColor),
          const SizedBox(width: 8),
          _buildSortChip('最新', -2, _sortMode == 2, themeColor),
        ],
      ),
    );
  }

  Widget _buildSortChip(
    String label,
    int focusIndex,
    bool isActive,
    Color themeColor,
  ) {
    final isFocused = _focusedIndex == focusIndex;
    return GestureDetector(
      onTap: () => _switchSort(focusIndex == -1 ? 3 : 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isFocused
              ? themeColor.withValues(alpha: AppColors.focusAlpha)
              : isActive
                  ? AppColors.navItemSelectedBackground
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isActive && !isFocused
              ? Border.all(color: AppColors.inactiveText, width: 0.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isFocused || isActive
                ? AppColors.primaryText
                : AppColors.inactiveText,
            fontSize: AppFonts.sizeSM,
            fontWeight: isActive ? AppFonts.semibold : AppFonts.regular,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_comments.isEmpty) {
      return Center(
        child: Text(
          '暂无评论',
          style:
              TextStyle(color: AppColors.inactiveText, fontSize: AppFonts.sizeMD),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: _comments.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _comments.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        _itemKeys[index] ??= GlobalKey();
        return _buildCommentItem(
            _comments[index], _focusedIndex == index, index);
      },
    );
  }

  Widget _buildCommentItem(Comment comment, bool isFocused, int index) {
    final themeColor = SettingsService.themeColor;
    final hasReplies = comment.rcount > 0;
    final isExpanded = _expandedReplies.containsKey(comment.rpid);
    final replies = _expandedReplies[comment.rpid] ?? [];

    return Container(
      key: _itemKeys[index],
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isFocused
            ? themeColor.withValues(alpha: AppColors.commentFocusAlpha)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: ImageUrlUtils.getResizedUrl(
                      comment.avatar,
                      width: 64,
                    ),
                    width: 32,
                    height: 32,
                    memCacheWidth: 64,
                    memCacheHeight: 64,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        Container(width: 32, height: 32, color: AppColors.navItemSelectedBackground),
                    errorWidget: (_, _, _) => Container(
                      width: 32,
                      height: 32,
                      color: AppColors.navItemSelectedBackground,
                      child: Icon(
                        Icons.person,
                        color: AppColors.inactiveText,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              comment.uname,
                              style: TextStyle(
                                color: AppColors.inactiveText,
                                fontSize: AppFonts.sizeSM,
                                fontWeight: AppFonts.medium,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            comment.timeText,
                            style: TextStyle(
                              color: AppColors.disabledText,
                              fontSize: AppFonts.sizeXS,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment.content,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: AppFonts.sizeSM,
                          height: 1.4,
                        ),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.thumb_up_outlined,
                            color: AppColors.disabledText,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            comment.likeText,
                            style: TextStyle(
                              color: AppColors.disabledText,
                              fontSize: AppFonts.sizeXS,
                            ),
                          ),
                          if (hasReplies) ...[
                            const SizedBox(width: 16),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: AppColors.disabledText,
                              size: 15,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              isExpanded
                                  ? '收起回复'
                                  : '${comment.rcount}条回复',
                              style: TextStyle(
                                color: AppColors.disabledText,
                                fontSize: AppFonts.sizeXS,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded && replies.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 52, right: 12, bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.navItemSelectedBackground,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  for (final reply in replies) _buildReplyItem(reply),
                  if (_replyHasMore[comment.rpid] == true)
                    GestureDetector(
                      onTap: () => _loadMoreReplies(comment.rpid),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '查看更多回复',
                          style: TextStyle(
                            color: themeColor,
                            fontSize: AppFonts.sizeSM,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(Comment reply) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: ImageUrlUtils.getResizedUrl(reply.avatar, width: 48),
              width: 20,
              height: 20,
              memCacheWidth: 48,
              memCacheHeight: 48,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  Container(width: 20, height: 20, color: AppColors.navItemSelectedBackground),
              errorWidget: (_, _, _) =>
                  Container(width: 20, height: 20, color: AppColors.navItemSelectedBackground),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${reply.uname}  ',
                    style: TextStyle(
                      color: AppColors.inactiveText,
                      fontSize: AppFonts.sizeSM,
                      fontWeight: AppFonts.medium,
                    ),
                  ),
                  TextSpan(
                    text: reply.content,
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: AppFonts.sizeSM,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
