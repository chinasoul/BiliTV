import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../config/app_style.dart';
import '../../widgets/history_video_card.dart';
import '../../widgets/update_time_banner.dart';
import '../player/player_screen.dart';

/// 观看历史 Tab
class HistoryTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const HistoryTab({super.key, this.sidebarFocusNode, this.isVisible = false});

  @override
  State<HistoryTab> createState() => HistoryTabState();
}

class HistoryTabState extends State<HistoryTab> {
  List<Video> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _viewAt = 0;
  int _max = 0;
  final ScrollController _scrollController = ScrollController();
  bool _hasLoaded = false;
  int _currentLimit = SettingsService.listMaxItems;
  String _updateTimeText = ''; // 用于显示更新时间的 Banner
  int _updateTimeBannerKey = 0; // 用于强制重建 Banner
  // 每个视频卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};
  final FocusNode _loadMoreFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.isVisible && AuthService.isLoggedIn) {
      if (!_tryLoadFromCache()) {
        _loadHistory(reset: true);
      }
      _hasLoaded = true;
    }
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible &&
        !oldWidget.isVisible &&
        !_hasLoaded &&
        AuthService.isLoggedIn) {
      if (!_tryLoadFromCache()) {
        _loadHistory(reset: true);
      }
      _hasLoaded = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _loadMoreFocusNode.dispose();
    // 清理所有视频卡片的 FocusNode
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _videoFocusNodes.clear();
    super.dispose();
  }

  // 获取或创建视频卡片的 FocusNode
  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  bool get _reachedLimit => _videos.length >= _currentLimit && _hasMore;

  void _onScroll() {
    if (!_isLoading && !_isLoadingMore && _hasMore) {
      // 达到上限后停止自动加载，等待用户手动触发
      if (_videos.length >= _currentLimit) return;
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadHistory(reset: false);
      }
    }
  }

  void focusFirstItem() {
    if (_videos.isNotEmpty) {
      _getFocusNode(0).requestFocus();
    }
  }

  /// 用户主动点击"加载更多"时，扩展上限并继续加载
  void _extendLimit() {
    setState(() {
      _currentLimit += SettingsService.listMaxItems;
    });
    _loadHistory(reset: false);
  }

  /// 公开的刷新方法 - 供外部调用
  void refresh() {
    if (!AuthService.isLoggedIn) {
      _hasLoaded = false;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _videos = [];
        _viewAt = 0;
        _max = 0;
        _hasMore = true;
        _updateTimeText = ''; // 清除旧的更新时间
      });
      return;
    }
    _hasLoaded = true; // 标记已加载，避免切换时重复加载
    setState(() => _updateTimeText = ''); // 刷新时先清除旧的更新时间
    _loadHistory(reset: true, isManualRefresh: true);
  }

  Future<void> _loadHistory({
    bool reset = false,
    bool isManualRefresh = false,
  }) async {
    if (!AuthService.isLoggedIn) return;

    // 记录刷新前的第一个视频 bvid，用于判断是否有更新
    final oldFirstBvid = isManualRefresh && _videos.isNotEmpty
        ? _videos.first.bvid
        : null;

    if (reset) {
      // 释放旧的 FocusNode，防止内存泄漏
      for (final node in _videoFocusNodes.values) {
        node.dispose();
      }
      _videoFocusNodes.clear();
      _currentLimit = SettingsService.listMaxItems; // 重置上限
      setState(() {
        _isLoading = true;
        _videos = [];
        _viewAt = 0;
        _max = 0;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final result = await BilibiliApi.getHistory(
      ps: 30,
      viewAt: reset ? 0 : _viewAt,
      max: reset ? 0 : _max,
    );

    if (!mounted) return;

    final newVideos = result['list'] as List<Video>;
    final nextViewAt = result['viewAt'] as int;
    final nextMax = result['max'] as int;
    final hasMore = result['hasMore'] as bool;

    setState(() {
      if (reset) {
        _videos = newVideos;
        _isLoading = false;
      } else {
        // 去重：过滤掉已存在的视频
        final existingBvids = _videos.map((v) => v.bvid).toSet();
        final uniqueNewVideos = newVideos
            .where((v) => !existingBvids.contains(v.bvid))
            .toList();
        _videos.addAll(uniqueNewVideos);
        _isLoadingMore = false;
      }

      _viewAt = nextViewAt;
      _max = nextMax;

      if (!hasMore || newVideos.isEmpty) {
        _hasMore = false;
      }
    });

    // 首次加载完成后保存缓存
    if (reset && _videos.isNotEmpty) {
      // 手动刷新时，先判断数据是否变化，再决定是否保存缓存
      if (isManualRefresh) {
        final newFirstBvid = _videos.isNotEmpty ? _videos.first.bvid : null;
        final hasChanged = oldFirstBvid != newFirstBvid;
        if (hasChanged) {
          // 数据有变化，保存缓存并显示"更新于刚刚"
          _saveHistoryCache();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _updateTimeText = '更新于刚刚';
                _updateTimeBannerKey++;
              });
            }
          });
        } else {
          // 数据无变化，显示上次缓存的时间
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final timeStr = SettingsService.formatTimestamp(
                SettingsService.lastHistoryRefreshTime,
              );
              if (timeStr.isNotEmpty) {
                setState(() {
                  _updateTimeText = timeStr;
                  _updateTimeBannerKey++;
                });
              }
            }
          });
        }
      } else {
        // 非手动刷新（如首次加载），只保存缓存
        _saveHistoryCache();
      }
    }
  }

  /// 保存历史记录到本地缓存
  void _saveHistoryCache() {
    try {
      final json = jsonEncode(_videos.map((v) => v.toMap()).toList());
      SettingsService.setCachedHistoryJson(json);
    } catch (_) {}
  }

  /// 从本地缓存加载历史记录，成功返回 true
  bool _tryLoadFromCache() {
    final jsonStr = SettingsService.cachedHistoryJson;
    if (jsonStr == null) return false;
    try {
      final list = jsonDecode(jsonStr) as List;
      final videos = list
          .map((item) => Video.fromMap(item as Map<String, dynamic>))
          .toList();
      if (videos.isEmpty) return false;
      setState(() {
        _videos = videos;
        _isLoading = false;
        _hasMore = false; // 缓存不支持加载更多
      });
      // 显示上次更新时间 Banner
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final timeStr = SettingsService.formatTimestamp(
          SettingsService.lastHistoryRefreshTime,
        );
        if (timeStr.isNotEmpty && mounted) {
          setState(() {
            _updateTimeText = timeStr;
            _updateTimeBannerKey++; // 强制重建 Banner
          });
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _buildLoadMoreTile() {
    return Focus(
      focusNode: _loadMoreFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final gridColumns = SettingsService.videoGridColumns;
          final lastRowStart = (_videos.length ~/ gridColumns) * gridColumns;
          final targetIndex = lastRowStart < _videos.length
              ? lastRowStart
              : _videos.length - 1;
          _getFocusNode(targetIndex).requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.sidebarFocusNode?.requestFocus();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          _extendLimit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: _extendLimit,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isFocused
                    ? SettingsService.themeColor.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.expand_more,
                    color: isFocused ? Colors.white : Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已加载 ${_videos.length} 条，按确认键加载更多',
                    style: TextStyle(
                      color: isFocused ? Colors.white : Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    final gridColumns = SettingsService.videoGridColumns;

    // 未登录提示
    if (!AuthService.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '请先登录',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
            const SizedBox(height: 10),
            const Text(
              '登录后可查看观看历史',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_isLoading && _videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/history.svg',
              width: 80,
              height: 80,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.3),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '暂无观看历史',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 视频网格
        Positioned.fill(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: TabStyle.contentPadding,
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridColumns,
                    childAspectRatio: 320 / 280,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final video = _videos[index];

                      // 构建卡片内容
                      Widget buildCard(BuildContext ctx) {
                        return HistoryVideoCard(
                          video: video,
                          focusNode: _getFocusNode(index),
                          index: index,
                          gridColumns: gridColumns,
                          onTap: () => _onVideoTap(video),
                          // 最左列按左键跳到侧边栏
                          onMoveLeft: (index % gridColumns == 0)
                              ? () => widget.sidebarFocusNode?.requestFocus()
                              : () => _getFocusNode(index - 1).requestFocus(),
                          // 强制向右导航
                          onMoveRight: (index + 1 < _videos.length)
                              ? () => _getFocusNode(index + 1).requestFocus()
                              : null,
                          // 严格按列向上移动
                          onMoveUp: index >= gridColumns
                              ? () => _getFocusNode(
                                  index - gridColumns,
                                ).requestFocus()
                              : () {}, // 最顶行为无效输入
                          // 严格按列向下移动；最后一行：有"加载更多"时跳转到它，否则阻止
                          onMoveDown: (index + gridColumns < _videos.length)
                              ? () => _getFocusNode(
                                  index + gridColumns,
                                ).requestFocus()
                              : _reachedLimit
                              ? () => _loadMoreFocusNode.requestFocus()
                              : () {},
                          onFocus: () {},
                        );
                      }

                      return Builder(builder: buildCard);
                    },
                    childCount: _videos.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                  ),
                ),
              ),
              if (_reachedLimit)
                SliverToBoxAdapter(child: _buildLoadMoreTile())
              else if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
        // 固定标题 — 与其他 tab 页保持一致的 tab 样式
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: TabStyle.headerHeight,
          child: Container(
            color: TabStyle.headerBackgroundColor,
            padding: TabStyle.headerPadding,
            child: Row(
              children: [
                Container(
                  padding: TabStyle.tabPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '观看历史',
                        style: TextStyle(
                          color: SettingsService.themeColor,
                          fontSize: TabStyle.tabFontSize,
                          fontWeight: FontWeight.bold,
                          height: TabStyle.tabLineHeight,
                        ),
                      ),
                      const SizedBox(height: TabStyle.tabUnderlineGap),
                      Container(
                        height: TabStyle.tabUnderlineHeight,
                        width: TabStyle.tabUnderlineWidth,
                        decoration: BoxDecoration(
                          color: SettingsService.themeColor,
                          borderRadius: BorderRadius.circular(
                            TabStyle.tabUnderlineRadius,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 更新时间 Banner (显示在屏幕高度 2/3 处，自动收起)
        if (_updateTimeText.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).size.height * 2 / 3,
            left: 0,
            right: 0,
            child: Center(
              child: UpdateTimeBanner(
                key: ValueKey(_updateTimeBannerKey),
                timeText: _updateTimeText,
              ),
            ),
          ),
      ],
    );
  }
}
