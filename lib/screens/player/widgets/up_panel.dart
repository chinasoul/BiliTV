import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../../services/bilibili_api.dart';
import '../../../models/video.dart';

/// Uploader Panel - Shows uploader's videos and follow button
class UpPanel extends StatefulWidget {
  final String upName;
  final String upFace;
  final int upMid;
  final Function(Video) onVideoSelect;
  final VoidCallback onClose;

  const UpPanel({
    super.key,
    required this.upName,
    required this.upFace,
    required this.upMid,
    required this.onVideoSelect,
    required this.onClose,
  });

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  List<Video> _videos = [];
  bool _isFollowing = false;
  bool _isLoading = true;
  String _order = 'pubdate'; // 'pubdate' = time, 'click' = popularity
  // Focus index: 0+ = video list, -1 = sort button, -2 = follow button
  int _focusedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      BilibiliApi.getSpaceVideos(mid: widget.upMid, order: _order),
      BilibiliApi.checkFollowStatus(widget.upMid),
    ]);

    if (mounted) {
      setState(() {
        _videos = results[0] as List<Video>;
        _isFollowing = results[1] as bool;
        _isLoading = false;
        // Default focus on first video
        _focusedIndex = _videos.isNotEmpty ? 0 : -1;
      });
    }
  }

  Future<void> _toggleSort() async {
    final newOrder = _order == 'pubdate' ? 'click' : 'pubdate';
    setState(() {
      _order = newOrder;
      _isLoading = true;
    });

    final videos = await BilibiliApi.getSpaceVideos(
      mid: widget.upMid,
      order: newOrder,
    );
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
        _focusedIndex = _videos.isNotEmpty ? 0 : -1;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final success = await BilibiliApi.followUser(
      mid: widget.upMid,
      follow: !_isFollowing,
    );

    if (success) {
      setState(() => _isFollowing = !_isFollowing);
      Fluttertoast.showToast(msg: _isFollowing ? '已关注' : '已取消关注');
    } else {
      Fluttertoast.showToast(msg: '操作失败');
    }
  }

  void _scrollToFocused() {
    if (_videos.isEmpty || _focusedIndex < 0) return;
    final itemHeight = 90.0;
    final offset = _focusedIndex * itemHeight;
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > -2) {
        setState(() => _focusedIndex--);
        if (_focusedIndex >= 0) _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _videos.length - 1) {
        setState(() => _focusedIndex++);
        if (_focusedIndex >= 0) _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // Left on video list closes panel, ignored on header buttons
      if (_focusedIndex >= 0) {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // Right on header buttons toggles buttons
      if (_focusedIndex == -1) {
        setState(() => _focusedIndex = -2);
      } else if (_focusedIndex == -2) {
        setState(() => _focusedIndex = -1);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedIndex == -1) {
        _toggleSort();
      } else if (_focusedIndex == -2) {
        _toggleFollow();
      } else if (_videos.isNotEmpty && _focusedIndex >= 0) {
        widget.onVideoSelect(_videos[_focusedIndex]);
      }
      return KeyEventResult.handled;
    }

    // Back key: Not handled here, handled by PopScope/onPopInvoked
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isSortButtonFocused = _focusedIndex == -1;
    final isFollowButtonFocused = _focusedIndex == -2;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 400,
          height: double.infinity,
          color: Colors.black.withValues(alpha: 0.9),
          child: Column(
            children: [
              // Header: Uploader Info
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // 头像
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: widget.upFace.isNotEmpty
                          ? NetworkImage(widget.upFace)
                          : null,
                      child: widget.upFace.isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    // 名称
                    Expanded(
                      child: Text(
                        widget.upName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 排序按钮 - 可聚焦
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.all(isSortButtonFocused ? 4 : 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: isSortButtonFocused
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _order == 'pubdate'
                                  ? Icons.schedule
                                  : Icons.whatshot,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _order == 'pubdate' ? '最新' : '最热',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 关注按钮 - 可聚焦
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.all(isFollowButtonFocused ? 4 : 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: isFollowButtonFocused
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _isFollowing
                              ? Colors.grey[700]
                              : const Color(0xFF81C784),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isFollowing ? Icons.check : Icons.add,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isFollowing ? '已关注' : '关注',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.grey, height: 1),
              // 视频列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _videos.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无视频',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _videos.length,
                        itemBuilder: (context, index) => _buildVideoItem(
                          _videos[index],
                          index == _focusedIndex,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoItem(Video video, bool isFocused) {
    return Container(
      height: 88,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isFocused
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isFocused ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Row(
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              video.pic,
              width: 140,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 140,
                height: 80,
                color: Colors.grey[800],
                child: const Icon(Icons.error, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isFocused ? Colors.white : Colors.grey[300],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${video.viewFormatted} 播放',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    if (video.pubdateFormatted.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        video.pubdateFormatted,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
