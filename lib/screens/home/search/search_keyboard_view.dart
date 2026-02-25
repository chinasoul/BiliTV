import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/search_history_service.dart';
import '../../../widgets/tv_keyboard_button.dart';
import 'package:bili_tv_app/services/settings_service.dart';

/// 判断是否为按键按下或重复事件
bool _isKeyDownOrRepeat(KeyEvent event) =>
    event is KeyDownEvent || event is KeyRepeatEvent;

class _SearchInputMoveLeftIntent extends Intent {
  const _SearchInputMoveLeftIntent();
}

class _SearchInputMoveDownIntent extends Intent {
  const _SearchInputMoveDownIntent();
}

class _SearchInputBlockUpIntent extends Intent {
  const _SearchInputBlockUpIntent();
}

class SearchKeyboardView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onBackToHome;
  final ValueChanged<String> onSearch;

  const SearchKeyboardView({
    super.key,
    this.sidebarFocusNode,
    this.onBackToHome,
    required this.onSearch,
  });

  @override
  State<SearchKeyboardView> createState() => SearchKeyboardViewState();
}

class SearchKeyboardViewState extends State<SearchKeyboardView> {
  String _searchText = '';
  List<String> _suggestions = [];
  List<HotSearchItem> _hotSearchItems = [];
  bool _isLoadingHotSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchInputFocusNode = FocusNode();

  // 热搜列表的 FocusNode
  final List<FocusNode> _hotSearchFocusNodes = [];
  // 搜索历史的 FocusNode
  final List<FocusNode> _historyFocusNodes = [];
  // 清空按钮的 FocusNode
  final FocusNode _clearButtonFocusNode = FocusNode();
  // 键盘区第一个按钮的 FocusNode (清空按钮)
  final FocusNode _keyboardFirstFocusNode = FocusNode();
  // 键盘区第二个按钮的 FocusNode (后退按钮)
  final FocusNode _keyboardBackFocusNode = FocusNode();
  // 字母数字键盘 FocusNode
  final List<FocusNode> _gridFocusNodes = [];

  final List<String> _gridKeys = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
  ];

  @override
  void initState() {
    super.initState();
    _searchInputFocusNode.addListener(_onSearchInputFocusChanged);
    _gridFocusNodes.addAll(List.generate(_gridKeys.length, (_) => FocusNode()));
    SearchHistoryService.init();
    _loadHotSearch();
  }

  @override
  void dispose() {
    _searchInputFocusNode.removeListener(_onSearchInputFocusChanged);
    for (final node in _hotSearchFocusNodes) {
      node.dispose();
    }
    for (final node in _historyFocusNodes) {
      node.dispose();
    }
    for (final node in _gridFocusNodes) {
      node.dispose();
    }
    _clearButtonFocusNode.dispose();
    _keyboardFirstFocusNode.dispose();
    _keyboardBackFocusNode.dispose();
    _searchController.dispose();
    _searchInputFocusNode.dispose();
    super.dispose();
  }

  void _onSearchInputFocusChanged() {
    if (_searchInputFocusNode.hasFocus) {
      // TV 上聚焦输入框时主动请求系统输入法。
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return;
    }
    // 输入法关闭后，部分设备会让焦点丢失；仅在搜索区无任何焦点时兜底回到输入框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hasAnySearchAreaFocus()) return;
      if (widget.sidebarFocusNode?.hasFocus == true) return;
      _searchInputFocusNode.requestFocus();
    });
  }

  bool _hasAnySearchAreaFocus() {
    if (_searchInputFocusNode.hasFocus) return true;
    if (_keyboardFirstFocusNode.hasFocus || _keyboardBackFocusNode.hasFocus) {
      return true;
    }
    if (_clearButtonFocusNode.hasFocus) return true;
    for (final node in _gridFocusNodes) {
      if (node.hasFocus) return true;
    }
    for (final node in _hotSearchFocusNodes) {
      if (node.hasFocus) return true;
    }
    for (final node in _historyFocusNodes) {
      if (node.hasFocus) return true;
    }
    return false;
  }

  void focusSearchInput() {
    if (!_searchInputFocusNode.hasFocus) {
      _searchInputFocusNode.requestFocus();
    }
  }

  void focusDefaultEntry() {
    if (_gridFocusNodes.isNotEmpty && _gridFocusNodes.first.canRequestFocus) {
      _gridFocusNodes.first.requestFocus();
    }
  }

  Future<void> _loadHotSearch() async {
    if (_isLoadingHotSearch) return;
    setState(() => _isLoadingHotSearch = true);

    try {
      final items = await BilibiliApi.getHotSearchKeywords();
      if (mounted) {
        setState(() {
          _hotSearchItems = items;
          _isLoadingHotSearch = false;
          // 初始化热搜 FocusNode
          _hotSearchFocusNodes.clear();
          for (int i = 0; i < items.length; i++) {
            _hotSearchFocusNodes.add(FocusNode());
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingHotSearch = false);
      }
    }
  }

  void _updateHistoryFocusNodes() {
    final history = SearchHistoryService.getAll();
    // 清理多余的节点
    while (_historyFocusNodes.length > history.length) {
      _historyFocusNodes.removeLast().dispose();
    }
    // 添加缺少的节点
    while (_historyFocusNodes.length < history.length) {
      _historyFocusNodes.add(FocusNode());
    }
  }

  void _handleKeyboardTap(String key) {
    if (key == '后退') {
      if (_searchText.isNotEmpty) {
        final next = _searchText.substring(0, _searchText.length - 1);
        _setSearchText(next);
      }
    } else if (key == '清空') {
      _setSearchText('');
    } else if (key == '搜索') {
      if (_searchText.trim().isNotEmpty) {
        SearchHistoryService.add(_searchText.trim());
      }
      widget.onSearch(_searchText);
    } else {
      _setSearchText('$_searchText$key');
    }
  }

  void _setSearchText(String value) {
    setState(() {
      _searchText = value;
      _searchController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    });
    _fetchSuggestions();
  }

  Future<void> _fetchSuggestions() async {
    if (_searchText.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    final suggestions = await BilibiliApi.getSearchSuggestions(_searchText);

    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
    });
  }

  void _selectSuggestion(String suggestion) {
    _setSearchText(suggestion);
    SearchHistoryService.add(suggestion);
    widget.onSearch(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    _updateHistoryFocusNodes();
    final history = SearchHistoryService.getAll();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：键盘区
        SizedBox(width: 380, child: _buildKeyboardSection()),
        // 中间：热门搜索
        Expanded(child: _buildHotSearchSection()),
        // 右侧：搜索历史
        if (history.isNotEmpty)
          SizedBox(width: 280, child: _buildHistorySection(history)),
      ],
    );
  }

  /// 构建键盘区域
  Widget _buildKeyboardSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // 搜索输入框
            FocusTraversalOrder(
              order: const NumericFocusOrder(0.5),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (_isKeyDownOrRepeat(event)) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      widget.sidebarFocusNode?.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      return KeyEventResult.handled;
                    }
                    if ((event.logicalKey == LogicalKeyboardKey.escape ||
                            event.logicalKey == LogicalKeyboardKey.goBack ||
                            event.logicalKey == LogicalKeyboardKey.browserBack) &&
                        widget.onBackToHome != null) {
                      widget.onBackToHome!();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: Shortcuts(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(
                        LogicalKeyboardKey.arrowLeft,
                      ): _SearchInputMoveLeftIntent(),
                      SingleActivator(
                        LogicalKeyboardKey.arrowDown,
                      ): _SearchInputMoveDownIntent(),
                      SingleActivator(
                        LogicalKeyboardKey.arrowUp,
                      ): _SearchInputBlockUpIntent(),
                    },
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        _SearchInputMoveLeftIntent: CallbackAction<
                          _SearchInputMoveLeftIntent
                        >(
                          onInvoke: (_) {
                            widget.sidebarFocusNode?.requestFocus();
                            return null;
                          },
                        ),
                        _SearchInputMoveDownIntent: CallbackAction<
                          _SearchInputMoveDownIntent
                        >(
                          onInvoke: (_) {
                            _keyboardFirstFocusNode.requestFocus();
                            return null;
                          },
                        ),
                        _SearchInputBlockUpIntent: CallbackAction<
                          _SearchInputBlockUpIntent
                        >(onInvoke: (_) => null),
                      },
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchInputFocusNode,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                        decoration: InputDecoration(
                          hintText: '输入关键词搜索...',
                          hintStyle: const TextStyle(
                            color: Colors.white24,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15,
                          ),
                          filled: true,
                          fillColor: Colors.white10,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: SettingsService.themeColor,
                            ),
                          ),
                        ),
                        onTap: () =>
                            SystemChannels.textInput.invokeMethod<void>(
                              'TextInput.show',
                            ),
                        onChanged: (value) {
                          setState(() => _searchText = value);
                          _fetchSuggestions();
                        },
                        onSubmitted: (_) {
                          if (_searchText.trim().isNotEmpty) {
                            SearchHistoryService.add(_searchText.trim());
                          }
                          widget.onSearch(_searchText);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            // 清空/后退按钮
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(1.0),
                      child: TvKeyboardButton(
                        label: '清空',
                        focusNode: _keyboardFirstFocusNode,
                        onTap: () => _handleKeyboardTap('清空'),
                        onMoveLeft: () =>
                            widget.sidebarFocusNode?.requestFocus(),
                        onMoveUp: focusSearchInput,
                        onBack: widget.onBackToHome,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(1.1),
                      child: TvKeyboardButton(
                        label: '后退',
                        focusNode: _keyboardBackFocusNode,
                        onTap: () => _handleKeyboardTap('后退'),
                        onMoveUp: focusSearchInput,
                        onBack: widget.onBackToHome,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 字母数字键盘
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 1.1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _gridKeys.length,
              itemBuilder: (context, index) => FocusTraversalOrder(
                order: NumericFocusOrder(2.0 + (index * 0.001)),
                child: TvKeyboardButton(
                  label: _gridKeys[index],
                  focusNode: _gridFocusNodes[index],
                  onTap: () => _handleKeyboardTap(_gridKeys[index]),
                  onMoveLeft: (index % 6 == 0)
                      ? () => widget.sidebarFocusNode?.requestFocus()
                      : null,
                  onMoveUp: index < 6
                      ? () {
                          if (index < 3) {
                            _keyboardFirstFocusNode.requestFocus();
                          } else {
                            _keyboardBackFocusNode.requestFocus();
                          }
                        }
                      : null,
                  onBack: widget.onBackToHome,
                ),
              ),
            ),
            const SizedBox(height: 15),
            // 搜索按钮
            FocusTraversalOrder(
              order: const NumericFocusOrder(3.0),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: TvActionButton(
                  label: '搜索',
                  color: SettingsService.themeColor,
                  onTap: () => _handleKeyboardTap('搜索'),
                  onMoveLeft: () => widget.sidebarFocusNode?.requestFocus(),
                  onBack: widget.onBackToHome,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建热门搜索区域
  Widget _buildHotSearchSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(
                Icons.local_fire_department,
                color: Colors.orange.shade400,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                '热门搜索',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          // 热搜列表
          Expanded(
            child: _isLoadingHotSearch
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _hotSearchItems.isEmpty
                ? const Center(
                    child: Text(
                      '暂无热搜',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: _hotSearchItems.length,
                    itemBuilder: (context, index) {
                      final item = _hotSearchItems[index];
                      final isFirst = index == 0;
                      final isLast = index == _hotSearchItems.length - 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _HotSearchItem(
                          item: item,
                          focusNode: _hotSearchFocusNodes[index],
                          onTap: () => _selectSuggestion(item.keyword),
                          onBack: widget.onBackToHome,
                          onMoveUp: isFirst
                              ? () {}
                              : () {
                                  _hotSearchFocusNodes[index - 1]
                                      .requestFocus();
                                },
                          onMoveDown: isLast
                              ? () {}
                              : () {
                                  _hotSearchFocusNodes[index + 1]
                                      .requestFocus();
                                },
                          onMoveLeft: () =>
                              _keyboardFirstFocusNode.requestFocus(),
                          onMoveRight: _historyFocusNodes.isNotEmpty
                              ? () => _historyFocusNodes[0].requestFocus()
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建搜索历史区域
  Widget _buildHistorySection(List<String> history) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题和清除按钮
          Row(
            children: [
              const Icon(Icons.history, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              const Text(
                '搜索历史',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              _ClearButton(
                focusNode: _clearButtonFocusNode,
                onTap: () async {
                  await SearchHistoryService.clear();
                  setState(() {});
                },
                onBack: widget.onBackToHome,
                onMoveLeft: _hotSearchFocusNodes.isNotEmpty
                    ? () => _hotSearchFocusNodes[0].requestFocus()
                    : () => _keyboardFirstFocusNode.requestFocus(),
              ),
            ],
          ),
          const SizedBox(height: 15),
          // 历史列表
          Expanded(
            child: ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final item = history[index];
                final isFirst = index == 0;
                final isLast = index == history.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _HistoryItem(
                    text: item,
                    focusNode: _historyFocusNodes[index],
                    onTap: () => _selectSuggestion(item),
                    onBack: widget.onBackToHome,
                    onMoveUp: isFirst
                        ? () => _clearButtonFocusNode.requestFocus()
                        : () => _historyFocusNodes[index - 1].requestFocus(),
                    onMoveDown: isLast
                        ? () {}
                        : () {
                            _historyFocusNodes[index + 1].requestFocus();
                          },
                    onMoveLeft: _hotSearchFocusNodes.isNotEmpty
                        ? () =>
                              _hotSearchFocusNodes[index.clamp(
                                    0,
                                    _hotSearchFocusNodes.length - 1,
                                  )]
                                  .requestFocus()
                        : () => _keyboardFirstFocusNode.requestFocus(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 清除按钮
class _ClearButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onBack;
  final VoidCallback? onMoveLeft;

  const _ClearButton({
    required this.focusNode,
    required this.onTap,
    this.onBack,
    this.onMoveLeft,
  });

  @override
  State<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends State<_ClearButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onKeyEvent: (node, event) {
          if (_isKeyDownOrRepeat(event)) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              return KeyEventResult.handled; // 阻止上键
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                widget.onMoveLeft != null) {
              widget.onMoveLeft!();
              return KeyEventResult.handled;
            }
            if ((event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack) &&
                widget.onBack != null) {
              widget.onBack!();
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isFocused ? SettingsService.themeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_outline,
                color: _isFocused ? Colors.white : Colors.white38,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '清除',
                style: TextStyle(
                  color: _isFocused ? Colors.white : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 热门搜索项
class _HotSearchItem extends StatefulWidget {
  final HotSearchItem item;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onBack;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const _HotSearchItem({
    required this.item,
    required this.focusNode,
    required this.onTap,
    this.onBack,
    this.onMoveUp,
    this.onMoveDown,
    this.onMoveLeft,
    this.onMoveRight,
  });

  @override
  State<_HotSearchItem> createState() => _HotSearchItemState();
}

class _HotSearchItemState extends State<_HotSearchItem> {
  bool _isFocused = false;

  Color _getRankColor(int rank) {
    if (rank == 1) return Colors.red.shade400;
    if (rank == 2) return Colors.orange.shade400;
    if (rank == 3) return Colors.amber.shade600;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onKeyEvent: (node, event) {
          if (_isKeyDownOrRepeat(event)) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                widget.onMoveUp != null) {
              widget.onMoveUp!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                widget.onMoveDown != null) {
              widget.onMoveDown!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                widget.onMoveLeft != null) {
              widget.onMoveLeft!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                widget.onMoveRight != null) {
              widget.onMoveRight!();
              return KeyEventResult.handled;
            }
            if ((event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack) &&
                widget.onBack != null) {
              widget.onBack!();
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isFocused ? SettingsService.themeColor : Colors.white12,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              // 排名
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isFocused
                      ? Colors.white.withValues(alpha: 0.2)
                      : _getRankColor(widget.item.rank).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.item.rank}',
                  style: TextStyle(
                    color: _isFocused
                        ? Colors.white
                        : _getRankColor(widget.item.rank),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 关键词
              Expanded(
                child: Text(
                  widget.item.showName,
                  style: TextStyle(
                    color: _isFocused ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: _isFocused
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 热搜图标
              if (widget.item.icon.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.whatshot,
                  size: 14,
                  color: _isFocused ? Colors.white : Colors.orange.shade300,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 搜索历史项
class _HistoryItem extends StatefulWidget {
  final String text;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onBack;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onMoveLeft;

  const _HistoryItem({
    required this.text,
    required this.focusNode,
    required this.onTap,
    this.onBack,
    this.onMoveUp,
    this.onMoveDown,
    this.onMoveLeft,
  });

  @override
  State<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<_HistoryItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onKeyEvent: (node, event) {
          if (_isKeyDownOrRepeat(event)) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                widget.onMoveUp != null) {
              widget.onMoveUp!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                widget.onMoveDown != null) {
              widget.onMoveDown!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                widget.onMoveLeft != null) {
              widget.onMoveLeft!();
              return KeyEventResult.handled;
            }
            // 右键不处理，最右边不能再往右
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              return KeyEventResult.handled;
            }
            if ((event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack) &&
                widget.onBack != null) {
              widget.onBack!();
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isFocused ? SettingsService.themeColor : Colors.white12,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: _isFocused ? Colors.white : Colors.white54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: _isFocused ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: _isFocused
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
