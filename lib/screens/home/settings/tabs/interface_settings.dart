import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../services/settings_service.dart';
import '../../../../core/focus/focus_navigation.dart';
import '../widgets/setting_action_row.dart';
import '../widgets/setting_toggle_row.dart';

class InterfaceSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const InterfaceSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<InterfaceSettings> createState() => _InterfaceSettingsState();
}

class _InterfaceSettingsState extends State<InterfaceSettings> {
  int _videoGridColumns = SettingsService.videoGridColumns;

  // 分区排序相关
  List<String> _categoryOrder = [];
  int _selectedCategoryOrderIndex = 0;
  bool _isDragging = false;
  late List<FocusNode> _categoryOrderFocusNodes;
  late List<FocusNode> _categoryToggleFocusNodes; // 分区开关焦点

  // 直播分区排序相关
  List<String> _liveCategoryOrder = [];
  int _selectedLiveCategoryOrderIndex = 0;
  bool _isLiveDragging = false;
  late List<FocusNode> _liveCategoryOrderFocusNodes;
  late List<FocusNode> _liveCategoryToggleFocusNodes;

  static const categoryLabels = {
    'recommend': '推荐',
    'popular': '热门',
    'anime': '番剧',
    'movie': '影视',
    'game': '游戏',
    'knowledge': '知识',
    'tech': '科技',
    'music': '音乐',
    'dance': '舞蹈',
    'life': '生活',
    'food': '美食',
    'douga': '动画',
  };

  @override
  void initState() {
    super.initState();
    _loadCategoryOrder();
  }

  @override
  void dispose() {
    for (var node in _categoryOrderFocusNodes) {
      node.dispose();
    }
    for (var node in _categoryToggleFocusNodes) {
      node.dispose();
    }
    for (var node in _liveCategoryOrderFocusNodes) {
      node.dispose();
    }
    for (var node in _liveCategoryToggleFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _loadCategoryOrder() {
    _categoryOrder = SettingsService.categoryOrder;
    _categoryOrderFocusNodes = List.generate(
      _categoryOrder.length,
      (_) => FocusNode(),
    );
    _categoryToggleFocusNodes = List.generate(
      _categoryOrder.length,
      (_) => FocusNode(),
    );

    _liveCategoryOrder = SettingsService.liveCategoryOrder;
    _liveCategoryOrderFocusNodes = List.generate(
      _liveCategoryOrder.length,
      (_) => FocusNode(),
    );
    _liveCategoryToggleFocusNodes = List.generate(
      _liveCategoryOrder.length,
      (_) => FocusNode(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取启用的分区 (用于排序)
    final enabledOrder = _categoryOrder
        .where((name) => SettingsService.isCategoryEnabled(name))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 启动动画开关
        SettingActionRow(
          label: '每行视频列数',
          value: '当前: $_videoGridColumns 列',
          buttonLabel: '切换：$_videoGridColumns',
          autofocus: true,
          isFirst: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: () async {
            const options = [4, 5, 6];
            final current = _videoGridColumns.clamp(4, 6);
            final idx = options.indexOf(current);
            final next = options[(idx + 1) % options.length];
            await SettingsService.setVideoGridColumns(next);
            setState(() => _videoGridColumns = next);
          },
        ),
        const SizedBox(height: 10),
        // 播放器时间显示开关
        SettingToggleRow(
          label: '总是显示时间',
          subtitle: '播放界面右上角总是显示当前时间',
          value: SettingsService.alwaysShowPlayerTime,
          autofocus: false,
          onMoveUp: null, // 允许自然向上导航到上一项
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setAlwaysShowPlayerTime(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 10),

        // 分区开关
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '分区开关 (确认键切换)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categoryOrder.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final catName = _categoryOrder[index];
              final label = categoryLabels[catName] ?? catName;
              final isEnabled = SettingsService.isCategoryEnabled(catName);

              return TvFocusScope(
                pattern: FocusPattern.horizontal,
                focusNode: _categoryToggleFocusNodes[index],
                isFirst: index == 0,
                isLast: index == _categoryOrder.length - 1,
                exitLeft: widget.sidebarFocusNode,
                onSelect: () {
                  SettingsService.toggleCategory(catName, !isEnabled);
                  setState(() {});
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? const Color(0xFFfb7299).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: focused
                              ? Colors.white
                              : isEnabled
                              ? const Color(0xFFfb7299)
                              : Colors.transparent,
                          width: focused ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isEnabled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: focused
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // 分区排序标题
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '分区排序 (仅显示已启用)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _isDragging ? '← → 移动位置，确认键固定' : '确认键选中，← → 移动',
            style: TextStyle(
              color: _isDragging
                  ? const Color(0xFFfb7299)
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: enabledOrder.isEmpty
              ? Center(
                  child: Text(
                    '请至少启用一个分区',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: enabledOrder.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final catName = enabledOrder[index];
                    final label = categoryLabels[catName] ?? catName;
                    final isSelected = index == _selectedCategoryOrderIndex;

                    // 确保 focusNode 索引有效
                    final focusNodeIndex = _categoryOrder.indexOf(catName);
                    if (focusNodeIndex < 0 ||
                        focusNodeIndex >= _categoryOrderFocusNodes.length) {
                      return const SizedBox.shrink();
                    }

                    return Focus(
                      focusNode: _categoryOrderFocusNodes[focusNodeIndex],
                      onFocusChange: (focused) {
                        if (focused && !_isDragging) {
                          setState(() => _selectedCategoryOrderIndex = index);
                        }
                      },
                      onKeyEvent: (node, event) {
                        if (event is KeyUpEvent) {
                          return KeyEventResult.ignored;
                        }

                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter)) {
                          setState(() => _isDragging = !_isDragging);
                          return KeyEventResult.handled;
                        }

                        // 阻止向下导航
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          return KeyEventResult.handled;
                        }

                        if (_isDragging) {
                          // 在完整的 _categoryOrder 中找到当前位置
                          final fullIndex = _categoryOrder.indexOf(catName);

                          if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft &&
                              index > 0) {
                            // 找到前一个启用的分区
                            final prevCat = enabledOrder[index - 1];
                            final prevFullIndex = _categoryOrder.indexOf(
                              prevCat,
                            );

                            // 交换
                            setState(() {
                              _categoryOrder[fullIndex] = prevCat;
                              _categoryOrder[prevFullIndex] = catName;
                              _selectedCategoryOrderIndex = index - 1;
                            });
                            SettingsService.setCategoryOrder(_categoryOrder);
                            // 焦点跟随到新位置
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _categoryOrderFocusNodes[prevFullIndex]
                                  .requestFocus();
                            });
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight &&
                              index < enabledOrder.length - 1) {
                            // 找到后一个启用的分区
                            final nextCat = enabledOrder[index + 1];
                            final nextFullIndex = _categoryOrder.indexOf(
                              nextCat,
                            );

                            // 交换
                            setState(() {
                              _categoryOrder[fullIndex] = nextCat;
                              _categoryOrder[nextFullIndex] = catName;
                              _selectedCategoryOrderIndex = index + 1;
                            });
                            SettingsService.setCategoryOrder(_categoryOrder);
                            // 焦点跟随到新位置
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _categoryOrderFocusNodes[nextFullIndex]
                                  .requestFocus();
                            });
                            return KeyEventResult.handled;
                          }
                        }

                        // 上键跳转到分区开关区域
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          // 跳到分区开关的对应位置
                          if (index < _categoryToggleFocusNodes.length) {
                            _categoryToggleFocusNodes[index].requestFocus();
                          } else if (_categoryToggleFocusNodes.isNotEmpty) {
                            _categoryToggleFocusNodes.first.requestFocus();
                          }
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                            index == 0) {
                          widget.sidebarFocusNode?.requestFocus();
                          return KeyEventResult.handled;
                        }

                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _isDragging && isSelected
                                  ? const Color(0xFFfb7299)
                                  : focused
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: focused
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: focused
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ), // End of existing ListView
        const SizedBox(height: 18),
        // ==================== 直播分区设置 ====================
        // 直播分区开关
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '直播分区开关 (确认键切换)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _liveCategoryOrder.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final catKey = _liveCategoryOrder[index];
              final label =
                  SettingsService.liveCategoryLabels[catKey] ?? catKey;
              final isEnabled = SettingsService.isLiveCategoryEnabled(catKey);

              return TvFocusScope(
                pattern: FocusPattern.horizontal,
                focusNode: _liveCategoryToggleFocusNodes[index],
                onSelect: () {
                  SettingsService.toggleLiveCategory(catKey, !isEnabled);
                  setState(() {});
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? const Color(0xFFfb7299).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: focused
                              ? Colors.white
                              : isEnabled
                              ? const Color(0xFFfb7299)
                              : Colors.transparent,
                          width: focused ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isEnabled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: focused
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // 直播分区排序标题
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '直播分区排序 (仅显示已启用)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _isLiveDragging ? '← → 移动位置，确认键固定' : '确认键选中，← → 移动',
            style: TextStyle(
              color: _isLiveDragging
                  ? const Color(0xFFfb7299)
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child:
              _categoryOrder
                  .where((name) => SettingsService.isLiveCategoryEnabled(name))
                  .isEmpty
              ? Center(
                  child: Text(
                    '请至少启用一个分区',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final enabledLiveOrder = _liveCategoryOrder
                        .where(
                          (name) => SettingsService.isLiveCategoryEnabled(name),
                        )
                        .toList();
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: enabledLiveOrder.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final catKey = enabledLiveOrder[index];
                        final label =
                            SettingsService.liveCategoryLabels[catKey] ??
                            catKey;
                        final isSelected =
                            index == _selectedLiveCategoryOrderIndex;

                        // 确保 focusNode 索引有效
                        final focusNodeIndex = _liveCategoryOrder.indexOf(
                          catKey,
                        );
                        if (focusNodeIndex < 0 ||
                            focusNodeIndex >=
                                _liveCategoryOrderFocusNodes.length) {
                          return const SizedBox.shrink();
                        }

                        return Focus(
                          focusNode:
                              _liveCategoryOrderFocusNodes[focusNodeIndex],
                          onFocusChange: (focused) {
                            if (focused && !_isLiveDragging) {
                              setState(
                                () => _selectedLiveCategoryOrderIndex = index,
                              );
                            }
                          },
                          onKeyEvent: (node, event) {
                            if (event is KeyUpEvent) {
                              return KeyEventResult.ignored;
                            }

                            if (event is KeyDownEvent &&
                                (event.logicalKey ==
                                        LogicalKeyboardKey.select ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter)) {
                              setState(
                                () => _isLiveDragging = !_isLiveDragging,
                              );
                              return KeyEventResult.handled;
                            }

                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              return KeyEventResult.handled;
                            }

                            if (_isLiveDragging) {
                              final fullIndex = _liveCategoryOrder.indexOf(
                                catKey,
                              );

                              if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowLeft &&
                                  index > 0) {
                                final prevCat = enabledLiveOrder[index - 1];
                                final prevFullIndex = _liveCategoryOrder
                                    .indexOf(prevCat);

                                setState(() {
                                  _liveCategoryOrder[fullIndex] = prevCat;
                                  _liveCategoryOrder[prevFullIndex] = catKey;
                                  _selectedLiveCategoryOrderIndex = index - 1;
                                });
                                SettingsService.setLiveCategoryOrder(
                                  _liveCategoryOrder,
                                );
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _liveCategoryOrderFocusNodes[prevFullIndex]
                                      .requestFocus();
                                });
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowRight &&
                                  index < enabledLiveOrder.length - 1) {
                                final nextCat = enabledLiveOrder[index + 1];
                                final nextFullIndex = _liveCategoryOrder
                                    .indexOf(nextCat);

                                setState(() {
                                  _liveCategoryOrder[fullIndex] = nextCat;
                                  _liveCategoryOrder[nextFullIndex] = catKey;
                                  _selectedLiveCategoryOrderIndex = index + 1;
                                });
                                SettingsService.setLiveCategoryOrder(
                                  _liveCategoryOrder,
                                );
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _liveCategoryOrderFocusNodes[nextFullIndex]
                                      .requestFocus();
                                });
                                return KeyEventResult.handled;
                              }
                            }

                            // 上键跳转到直播分区开关区域
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              // 跳到分区开关的对应位置
                              if (index <
                                  _liveCategoryToggleFocusNodes.length) {
                                _liveCategoryToggleFocusNodes[index]
                                    .requestFocus();
                              } else if (_liveCategoryToggleFocusNodes
                                  .isNotEmpty) {
                                _liveCategoryToggleFocusNodes.first
                                    .requestFocus();
                              }
                              return KeyEventResult.handled;
                            }

                            return KeyEventResult.ignored;
                          },
                          child: Builder(
                            builder: (context) {
                              final focused = Focus.of(context).hasFocus;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _isLiveDragging && isSelected
                                      ? const Color(0xFFfb7299)
                                      : focused
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: focused
                                      ? Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: focused
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRestartHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFfb7299).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFfb7299), size: 16),
          const SizedBox(width: 4),
          Text(
            '修改后需重启APP生效',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
