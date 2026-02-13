import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:keframe/keframe.dart';
import '../../services/api/live_api.dart';
import '../../services/api/base_api.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/tv_live_card.dart';
import '../../widgets/time_display.dart';
import '../live/live_player_screen.dart';

class LiveTab extends StatefulWidget {
  final FocusNode sidebarFocusNode;
  final bool isVisible;

  const LiveTab({
    super.key,
    required this.sidebarFocusNode,
    required this.isVisible,
  });

  @override
  State<LiveTab> createState() => LiveTabState();
}

class LiveTabState extends State<LiveTab> {
  int _selectedCategoryIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late List<_LiveCategory> _categories;
  late List<FocusNode> _categoryFocusNodes;

  // Data Cache
  final Map<int, List<dynamic>> _categoryRooms = {};
  final Map<int, bool> _categoryLoading = {};
  final Map<int, int> _categoryPage = {};

  // Focus Nodes for Grid Items
  final Map<int, FocusNode> _roomFocusNodes = {};

  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _initCategories();
    _categoryFocusNodes = List.generate(_categories.length, (_) => FocusNode());
    _loadDataForCategory(0);
  }

  void _initCategories() {
    _categories = [
      _LiveCategory(
        id: 'following',
        label: '我的关注',
        type: _LiveCategoryType.following,
      ),
      _LiveCategory(
        id: 'recommend',
        label: '推荐直播',
        type: _LiveCategoryType.recommend,
      ),
    ];

    final liveOrder = SettingsService.liveCategoryOrder;
    for (var key in liveOrder) {
      if (SettingsService.isLiveCategoryEnabled(key)) {
        final label = SettingsService.liveCategoryLabels[key] ?? key;
        final id = SettingsService.liveCategoryIds[key];
        if (id != null) {
          _categories.add(
            _LiveCategory(
              id: key,
              label: label,
              type: _LiveCategoryType.partition,
              parentId: id,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    for (var node in _roomFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _getFocusNode(int index) {
    return _roomFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  /// Exposed method for sidebar navigation
  void focusFirstItem() {
    if (_categoryFocusNodes.isNotEmpty) {
      _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
    }
  }

  void refresh() {
    _loadDataForCategory(_selectedCategoryIndex, refresh: true);
  }

  Future<void> _loadDataForCategory(int index, {bool refresh = false}) async {
    if (_categoryLoading[index] == true) return;

    final category = _categories[index];
    final currentPage = _categoryPage[index] ?? 1;

    if (refresh) {
      setState(() {
        _categoryLoading[index] = true;
        _categoryRooms[index] = [];
        _categoryPage[index] = 1;
        _isRefreshing = true;
      });
    } else {
      setState(() {
        _categoryLoading[index] = true;
      });
    }

    try {
      List<dynamic> rooms = [];
      if (category.type == _LiveCategoryType.following) {
        if (AuthService.isLoggedIn) {
          // Following list usually doesn't have deep pagination in this API context,
          // but we follow standard pattern.
          // Note: getFollowedLive filters internally, so page size might result in fewer items.
          // We might need to fetch more pages if empty, but keep simple for now.
          rooms = await LiveApi.getFollowedLive(
            page: refresh ? 1 : currentPage,
            pageSize: 20,
          );
        }
      } else if (category.type == _LiveCategoryType.recommend) {
        rooms = await LiveApi.getRecommended(
          page: refresh ? 1 : currentPage,
          pageSize: 30,
        );
      } else if (category.type == _LiveCategoryType.partition) {
        rooms = await LiveApi.getRecommended(
          parentId: category.parentId!,
          page: refresh ? 1 : currentPage,
          pageSize: 30,
        );
      }

      if (mounted) {
        setState(() {
          if (refresh) {
            _categoryRooms[index] = rooms;
          } else {
            _categoryRooms[index] = [
              ...(_categoryRooms[index] ?? []),
              ...rooms,
            ];
          }
          _categoryLoading[index] = false;
          _isRefreshing = false; // Clear refreshing
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _categoryLoading[index] = false;
          _isRefreshing = false; // Clear refreshing on error too
        });
      }
    }
  }

  void _loadMore() {
    if (_categoryLoading[_selectedCategoryIndex] == true) return;
    // 到 60 条后停止加载更多，防止内存无限增长
    if ((_categoryRooms[_selectedCategoryIndex] ?? []).length >= 60) return;

    // Following list often returns all or has limited pages, avoid infinite loop if empty
    // But for now, simple increment
    final page = (_categoryPage[_selectedCategoryIndex] ?? 1) + 1;
    _categoryPage[_selectedCategoryIndex] = page;
    _loadDataForCategory(_selectedCategoryIndex);
  }

  void _switchCategory(int index) {
    if (_selectedCategoryIndex == index) return;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() => _selectedCategoryIndex = index);
    if ((_categoryRooms[index] ?? []).isEmpty) {
      _loadDataForCategory(index);
    }
  }

  void _navigateToRoom(dynamic room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LivePlayerScreen(
          roomId: room['roomid'],
          title: room['title'],
          cover:
              room['pic'] ??
              room['room_cover'] ??
              room['cover'] ??
              room['user_cover'] ??
              room['keyframe'],
          uname: room['uname'],
          face: room['face'],
          online: BaseApi.toInt(room['online'] ?? room['text_small']),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final currentRooms = _categoryRooms[_selectedCategoryIndex] ?? [];
    final isLoading = _categoryLoading[_selectedCategoryIndex] ?? false;
    // Special case for 'Following' when not logged in
    final isFollowingTab =
        _categories[_selectedCategoryIndex].type == _LiveCategoryType.following;
    final showLoginText = isFollowingTab && !AuthService.isLoggedIn;

    // 判断是否是"启动后的第一屏数据" (Simulated)
    final bool isInitialLoad =
        _categoryPage[_selectedCategoryIndex] == 1 &&
        !_categoryLoading[_selectedCategoryIndex]!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FocusTraversalGroup(
            child: showLoginText
                ? const Center(
                    child: Text("请先登录", style: TextStyle(color: Colors.white)),
                  )
                : isLoading && currentRooms.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF81C784)),
                  )
                : currentRooms.isEmpty
                ? const Center(
                    child: Text(
                      "暂无开播的主播",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : SizeCacheWidget(
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 70, 24, 80),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 320 / 280,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 10,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              if (index == currentRooms.length - 4) {
                                _loadMore();
                              }

                              final room = currentRooms[index];

                              // 构建卡片
                              Widget buildCard(BuildContext ctx) {
                                return TvLiveCard(
                                  room: room,
                                  autofocus: isInitialLoad && index == 0,
                                  focusNode: _getFocusNode(index),
                                  onTap: () => _navigateToRoom(room),
                                  onFocus: () {
                                    if (!_scrollController.hasClients) {
                                      return;
                                    }
                                    final RenderObject? object = ctx
                                        .findRenderObject();
                                    if (object != null && object is RenderBox) {
                                      final viewport =
                                          RenderAbstractViewport.of(object);
                                      final offsetToReveal = viewport
                                          .getOffsetToReveal(object, 0.0)
                                          .offset;
                                      final targetOffset =
                                          (offsetToReveal - 120).clamp(
                                            0.0,
                                            _scrollController
                                                .position
                                                .maxScrollExtent,
                                          );
                                      if ((_scrollController.offset -
                                                  targetOffset)
                                              .abs() >
                                          50) {
                                        _scrollController.animateTo(
                                          targetOffset,
                                          duration: const Duration(
                                            milliseconds: 500,
                                          ),
                                          curve: Curves.easeOutCubic,
                                        );
                                      }
                                    }
                                  },
                                  onMoveLeft: (index % 4 == 0)
                                      ? () => widget.sidebarFocusNode
                                            .requestFocus()
                                      : () => _getFocusNode(
                                          index - 1,
                                        ).requestFocus(),
                                  onMoveRight: (index + 1 < currentRooms.length)
                                      ? () => _getFocusNode(
                                          index + 1,
                                        ).requestFocus()
                                      : null,
                                  onMoveUp: index >= 4
                                      ? () => _getFocusNode(
                                          index - 4,
                                        ).requestFocus()
                                      : () =>
                                            _categoryFocusNodes[_selectedCategoryIndex]
                                                .requestFocus(),
                                  onMoveDown: (index + 4 < currentRooms.length)
                                      ? () => _getFocusNode(
                                          index + 4,
                                        ).requestFocus()
                                      : null,
                                );
                              }

                              // 只有刷新时使用分帧渲染 (match HomeTab)
                              if (_isRefreshing) {
                                return FrameSeparateWidget(
                                  index: index,
                                  placeHolder: const SizedBox(
                                    width: 30,
                                    height: 30,
                                  ),
                                  child: Builder(builder: buildCard),
                                );
                              }

                              return Builder(builder: buildCard);
                            }, childCount: currentRooms.length),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // Top Category Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 56,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
            child: FocusTraversalGroup(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_categories.length, (index) {
                    return _LiveCategoryTab(
                      label: _categories[index].label,
                      isSelected: _selectedCategoryIndex == index,
                      focusNode: _categoryFocusNodes[index],
                      onTap: () {
                        if (_selectedCategoryIndex == index) {
                          refresh(); // Refresh if already selected
                        } else {
                          _switchCategory(index);
                        }
                      },
                      onFocus: () => _switchCategory(index),
                      onMoveLeft: index == 0
                          ? () => widget.sidebarFocusNode.requestFocus()
                          : null,
                    );
                  }),
                ),
              ),
            ),
          ),
        ),

        const Positioned(top: 10, right: 14, child: TimeDisplay()),
      ],
    );
  }
}

enum _LiveCategoryType { following, recommend, partition }

class _LiveCategory {
  final String id;
  final String label;
  final _LiveCategoryType type;
  final int? parentId;

  _LiveCategory({
    required this.id,
    required this.label,
    required this.type,
    this.parentId,
  });
}

class _LiveCategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;

  const _LiveCategoryTab({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) => f ? onFocus() : null,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                onMoveLeft != null) {
              onMoveLeft!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              // Refresh or select
              onTap();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final f = Focus.of(ctx).hasFocus;
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
                decoration: BoxDecoration(
                  color: f ? const Color(0xFF81C784) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: f ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: f
                            ? Colors.white
                            : (isSelected
                                  ? const Color(0xFF81C784)
                                  : Colors.grey),
                        fontSize: 16,
                        fontWeight: f || isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      width: 20,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF81C784)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
