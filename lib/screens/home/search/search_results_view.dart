import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../models/video.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/tv_video_card.dart';
import '../../player/player_screen.dart';

/// 判断是否为按键按下或重复事件
bool _isKeyDownOrRepeat(KeyEvent event) =>
    event is KeyDownEvent || event is KeyRepeatEvent;

class SearchResultsView extends StatefulWidget {
  final String query;
  final FocusNode? sidebarFocusNode;
  final VoidCallback onBackToKeyboard;

  const SearchResultsView({
    super.key,
    required this.query,
    this.sidebarFocusNode,
    required this.onBackToKeyboard,
  });

  @override
  State<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<SearchResultsView> {
  List<Video> _searchResults = [];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  // Pagination & Sorting State
  int _currentPage = 1;
  String _currentOrder = 'totalrank'; // totalrank, click, pubdate, dm
  bool _isLoadingMore = false;
  bool _hasMore = true;
  // Focus Management
  late final List<FocusNode> _sortFocusNodes;
  final Map<int, FocusNode> _videoFocusNodes = {};
  bool _shouldFocusFirstResult = false;
  // 空结果时返回按钮的 FocusNode
  final FocusNode _emptyBackButtonFocusNode = FocusNode();

  final Map<String, String> _sortOptions = {
    'totalrank': '综合排序',
    'click': '最多播放',
    'pubdate': '最新发布',
    'dm': '最多弹幕',
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _sortFocusNodes = List.generate(_sortOptions.length, (_) => FocusNode());
    // Initial search
    _searchVideos(reset: true, focusStart: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (final node in _sortFocusNodes) {
      node.dispose();
    }
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _emptyBackButtonFocusNode.dispose();
    super.dispose();
  }

  // Exposed for Parent to check status or force refresh if needed
  // But generally self-contained.

  void _onScroll() {
    if (!_isLoading && !_isLoadingMore && _hasMore) {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    }
  }

  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  Future<void> _searchVideos({
    bool reset = true,
    bool focusStart = false,
  }) async {
    if (widget.query.isEmpty) return;

    if (reset) {
      if (focusStart) {
        _shouldFocusFirstResult = true;
      }
      // 释放旧的 FocusNode，防止内存泄漏
      for (final node in _videoFocusNodes.values) {
        node.dispose();
      }
      _videoFocusNodes.clear();
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _searchResults = [];
        _hasMore = true;
      });
    }

    final results = await BilibiliApi.searchVideos(
      widget.query,
      page: _currentPage,
      order: _currentOrder,
    );

    if (!mounted) return;
    setState(() {
      if (reset) {
        _searchResults = results;
      } else {
        _searchResults.addAll(results);
      }

      _isLoading = false;
      _isLoadingMore = false;
      if (results.length < 20) {
        _hasMore = false;
      }

      // Handle explicit focus request after build
      if (_shouldFocusFirstResult) {
        _shouldFocusFirstResult = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_searchResults.isNotEmpty) {
            final firstNode = _getFocusNode(0);
            if (firstNode.canRequestFocus) {
              firstNode.requestFocus();
            }
          } else {
            // 无结果时聚焦返回按钮
            if (_emptyBackButtonFocusNode.canRequestFocus) {
              _emptyBackButtonFocusNode.requestFocus();
            }
          }
        });
      }
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    // 达到上限后停止加载更多，防止内存无限增长
    if (_searchResults.length >= SettingsService.listMaxItems) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    await _searchVideos(reset: false);
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    final gridColumns = SettingsService.videoGridColumns;
    Widget content;

    // 初始加载或完全重新加载时显示加载圈
    if (_isLoading && _currentPage == 1) {
      if (_currentOrder == 'totalrank' && _searchResults.isEmpty) {
        // 初始搜索加载
        content = const Center(child: CircularProgressIndicator());
      } else {
        // 切换排序或刷新 existing -> Loading overlaid but header visible
        content = const Center(child: CircularProgressIndicator());
      }
    } else if (_searchResults.isEmpty) {
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/search.svg',
              width: 80,
              height: 80,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.2),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '未找到相关视频',
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
            const SizedBox(height: 20),
            // 可聚焦的返回按钮
            _BackToSearchButton(
              focusNode: _emptyBackButtonFocusNode,
              onTap: widget.onBackToKeyboard,
            ),
          ],
        ),
      );
    } else {
      content = CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(30, 140, 30, 40),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridColumns,
                childAspectRatio: 360 / 300,
                crossAxisSpacing: 20,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final video = _searchResults[index];

                Widget buildCard(BuildContext cardContext) {
                  return TvVideoCard(
                    video: video,
                    // Use index 0 special focus node logic if needed, but handled globally
                    focusNode: _getFocusNode(index),
                    autofocus: index == 0,
                    disableCache: false,
                    index: index,
                    gridColumns: gridColumns,
                    onTap: () => _onVideoTap(video),
                    // 最左列按左键跳到侧边栏
                    onMoveLeft: (index % gridColumns == 0)
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : () => _getFocusNode(index - 1).requestFocus(),
                    // 强制向右导航
                    onMoveRight: (index + 1 < _searchResults.length)
                        ? () => _getFocusNode(index + 1).requestFocus()
                        : null,
                    // 严格按列向上移动，最顶行跳到排序按钮
                    onMoveUp: index >= gridColumns
                        ? () =>
                              _getFocusNode(index - gridColumns).requestFocus()
                        : () {
                            final sortIdx = _sortOptions.keys.toList().indexOf(
                              _currentOrder,
                            );
                            if (sortIdx >= 0 &&
                                sortIdx < _sortFocusNodes.length) {
                              _sortFocusNodes[sortIdx].requestFocus();
                            }
                          },
                    // 严格按列向下移动
                    onMoveDown: (index + gridColumns < _searchResults.length)
                        ? () =>
                              _getFocusNode(index + gridColumns).requestFocus()
                        : null,
                    onBack: widget.onBackToKeyboard,
                    onFocus: () {},
                  );
                }

                return Builder(builder: (ctx) => buildCard(ctx));
              }, childCount: _searchResults.length),
            ),
          ),
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: content),
        // 固定标题栏 + 排序栏
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.fromLTRB(30, 20, 30, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '搜索结果: ${widget.query}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: _sortOptions.entries.toList().asMap().entries.map((
                    mapEntry,
                  ) {
                    final idx = mapEntry.key;
                    final entry = mapEntry.value;
                    final isSelected = _currentOrder == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 15),
                      child: _SortButton(
                        label: entry.value,
                        isSelected: isSelected,
                        focusNode: _sortFocusNodes[idx],
                        onTap: () {
                          if (!isSelected) {
                            setState(() => _currentOrder = entry.key);
                            _searchVideos(reset: true);
                          }
                        },
                        onFocus: () {
                          if (!isSelected) {
                            setState(() => _currentOrder = entry.key);
                            _searchVideos(reset: true);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SortButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;

  const _SortButton({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
  });

  @override
  State<_SortButton> createState() => _SortButtonState();
}

class _SortButtonState extends State<_SortButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) widget.onFocus();
      },
      onKeyEvent: (node, event) {
        if (_isKeyDownOrRepeat(event)) {
          // 阻止上键导航到其他页面
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isFocused
              ? SettingsService.themeColor
              : widget.isSelected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: widget.isSelected || _isFocused
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// 返回搜索按钮 - 搜索结果为空时显示
class _BackToSearchButton extends StatefulWidget {
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const _BackToSearchButton({required this.onTap, this.focusNode});

  @override
  State<_BackToSearchButton> createState() => _BackToSearchButtonState();
}

class _BackToSearchButtonState extends State<_BackToSearchButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (_isKeyDownOrRepeat(event)) {
          // 返回键
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // 确认键
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // 阻止方向键导航到其他地方
          if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused ? SettingsService.themeColor : Colors.white12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back,
                size: 18,
                color: _isFocused ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                '返回重新搜索',
                style: TextStyle(
                  color: _isFocused ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: _isFocused ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
