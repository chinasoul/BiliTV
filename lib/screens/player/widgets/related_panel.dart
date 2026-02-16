import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../models/video.dart';

/// Related Videos Panel
class RelatedPanel extends StatefulWidget {
  final String bvid;
  final Function(Video) onVideoSelect;
  final VoidCallback onClose;

  const RelatedPanel({
    super.key,
    required this.bvid,
    required this.onVideoSelect,
    required this.onClose,
  });

  @override
  State<RelatedPanel> createState() => _RelatedPanelState();
}

class _RelatedPanelState extends State<RelatedPanel> {
  List<Video> _videos = [];
  bool _isLoading = true;
  int _focusedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadVideos();
    // Request focus in next frame to ensure panel is rendered
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

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    final videos = await BilibiliApi.getRelatedVideos(widget.bvid);
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    }
  }

  void _scrollToFocused() {
    if (_videos.isEmpty) return;
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
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _videos.length - 1) {
        setState(() => _focusedIndex++);
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_videos.isNotEmpty) {
        widget.onVideoSelect(_videos[_focusedIndex]);
      }
      return KeyEventResult.handled;
    }

    // Back key: Not handled here, handled by PopScope/onPopInvoked
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = SettingsService.getSidePanelWidth(context);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: panelWidth,
          height: double.infinity,
          color: Colors.black.withValues(alpha: 0.9),
          child: Column(
            children: [
              // 头部
              Container(
                padding: const EdgeInsets.all(16),
                child: const Row(
                  children: [
                    Icon(Icons.expand_more, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      '更多视频',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
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
                          '暂无相关视频',
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
      height: 70,
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
              width: 100,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 100,
                height: 56,
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
                      video.ownerName,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      video.viewFormatted,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
