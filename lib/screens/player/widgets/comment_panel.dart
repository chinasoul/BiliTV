import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/comment.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../utils/image_url_utils.dart';

/// 视频评论面板 (从右侧滑入)
class CommentPanel extends StatefulWidget {
  final int aid;
  final VoidCallback onClose;

  const CommentPanel({
    super.key,
    required this.aid,
    required this.onClose,
  });

  @override
  State<CommentPanel> createState() => _CommentPanelState();
}

class _CommentPanelState extends State<CommentPanel> {
  final List<Comment> _comments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _totalCount = 0;
  String? _nextOffset;
  bool _hasMore = true;
  int _sortMode = 3; // 3=热度, 2=时间

  // 展开回复的评论 rpid → 回复列表
  final Map<int, List<Comment>> _expandedReplies = {};
  final Map<int, int> _replyPages = {};
  final Map<int, bool> _replyHasMore = {};

  // Focus
  int _focusedIndex = 0; // 0+ = comment items, -1 = sort热度, -2 = sort时间
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

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
      // 已展开 → 折叠
      setState(() {
        _expandedReplies.remove(comment.rpid);
        _replyPages.remove(comment.rpid);
        _replyHasMore.remove(comment.rpid);
      });
    } else {
      // 展开 → 加载回复
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
    setState(() {
      _sortMode = mode;
      // 焦点保持在当前排序按钮上
    });
    _loadComments();
  }

  void _scrollToFocused() {
    if (_comments.isEmpty || _focusedIndex < 0) return;
    // 估算每条评论高度约 100
    final offset = _focusedIndex * 100.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      offset.clamp(0.0, maxScroll),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Back / Escape
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    // 排序按钮区域 (_focusedIndex < 0)
    if (_focusedIndex < 0) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_focusedIndex == -2) {
          setState(() => _focusedIndex = -1);
        } else {
          widget.onClose();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_focusedIndex == -1) {
          setState(() => _focusedIndex = -2);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_comments.isNotEmpty) {
          setState(() => _focusedIndex = 0);
          _scrollToFocused();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        _switchSort(_focusedIndex == -1 ? 3 : 2);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // 评论列表区域
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToFocused();
      } else {
        setState(() => _focusedIndex = -1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _comments.length - 1) {
        setState(() => _focusedIndex++);
        _scrollToFocused();
        // 接近底部时自动加载更多
        if (_focusedIndex >= _comments.length - 3) {
          _loadComments(loadMore: true);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter) {
      // 展开/折叠回复
      if (_focusedIndex >= 0 && _focusedIndex < _comments.length) {
        _toggleReplies(_focusedIndex);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 420,
          height: double.infinity,
          color: Colors.black.withValues(alpha: 0.92),
          child: Column(
            children: [
              // 头部
              _buildHeader(),
              const Divider(color: Colors.white12, height: 1),
              // 评论列表
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final themeColor = SettingsService.themeColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          const Icon(Icons.comment_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            '评论 $_totalCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // 排序按钮
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
              ? themeColor.withValues(alpha: 0.6)
              : isActive
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isActive && !isFocused
              ? Border.all(color: Colors.white24, width: 0.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isFocused
                ? Colors.white
                : isActive
                    ? Colors.white
                    : Colors.white54,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_comments.isEmpty) {
      return const Center(
        child: Text(
          '暂无评论',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
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
        final comment = _comments[index];
        final isFocused = _focusedIndex == index;
        return _buildCommentItem(comment, isFocused, index);
      },
    );
  }

  Widget _buildCommentItem(Comment comment, bool isFocused, int index) {
    final themeColor = SettingsService.themeColor;
    final hasReplies = comment.rcount > 0;
    final isExpanded = _expandedReplies.containsKey(comment.rpid);
    final replies = _expandedReplies[comment.rpid] ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isFocused
            ? themeColor.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主评论
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头像
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
                    placeholder: (_, _) => Container(
                      width: 32,
                      height: 32,
                      color: Colors.white12,
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 32,
                      height: 32,
                      color: Colors.white12,
                      child: const Icon(
                        Icons.person,
                        color: Colors.white24,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户名 + 时间
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              comment.uname,
                              style: TextStyle(
                                color: isFocused
                                    ? themeColor
                                    : Colors.white60,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            comment.timeText,
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 评论内容
                      Text(
                        comment.content,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // 底部操作行: 点赞 | 回复数
                      Row(
                        children: [
                          Icon(
                            Icons.thumb_up_outlined,
                            color: Colors.white38,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            comment.likeText,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          if (hasReplies) ...[
                            const SizedBox(width: 16),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: isFocused
                                  ? themeColor
                                  : Colors.white38,
                              size: 15,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              isExpanded
                                  ? '收起回复'
                                  : '${comment.rcount}条回复',
                              style: TextStyle(
                                color: isFocused
                                    ? themeColor
                                    : Colors.white38,
                                fontSize: 11,
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

          // 展开的回复列表
          if (isExpanded && replies.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 52, right: 12, bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  for (final reply in replies)
                    _buildReplyItem(reply),
                  if (_replyHasMore[comment.rpid] == true)
                    GestureDetector(
                      onTap: () => _loadMoreReplies(comment.rpid),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '查看更多回复',
                          style: TextStyle(
                            color: themeColor,
                            fontSize: 12,
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
              imageUrl: ImageUrlUtils.getResizedUrl(
                reply.avatar,
                width: 48,
              ),
              width: 20,
              height: 20,
              memCacheWidth: 48,
              memCacheHeight: 48,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 20,
                height: 20,
                color: Colors.white12,
              ),
              errorWidget: (_, _, _) => Container(
                width: 20,
                height: 20,
                color: Colors.white12,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${reply.uname}  ',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: reply.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
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
