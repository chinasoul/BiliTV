import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../services/settings_service.dart';
import '../../../../config/app_style.dart';
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
  double _fontScale = SettingsService.fontScale;
  int _themeColorValue = SettingsService.themeColorValue;
  double _sidePanelWidthRatio = SettingsService.sidePanelWidthRatio;

  // 分区排序相关
  List<String> _categoryOrder = [];
  int _selectedCategoryOrderIndex = 0;
  bool _isDragging = false;
  late List<FocusNode> _categoryOrderFocusNodes;
  late List<FocusNode> _categoryToggleFocusNodes; // 分区开关焦点
  late List<FocusNode> _themeColorFocusNodes; // 主题色焦点

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
    for (var node in _themeColorFocusNodes) {
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
    _themeColorFocusNodes = List.generate(
      SettingsService.themeColorOptions.length,
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
        // 聚焦即切换
        SettingToggleRow(
          label: '标签页选中即切换',
          subtitleWidget: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: '焦点移动即切换页面，',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                TextSpan(
                  text: '低内存设备建议关闭',
                  style: TextStyle(
                    color: Colors.amber.shade300,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          value: SettingsService.focusSwitchTab,
          autofocus: true,
          isFirst: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setFocusSwitchTab(value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        // 启动时自动刷新首页
        SettingToggleRow(
          label: '启动时自动刷新首页',
          subtitle: '关闭后启动时使用缓存数据，显示上次更新时间',
          value: SettingsService.autoRefreshOnLaunch,
          autofocus: false,
          isFirst: false,
          onMoveUp: null,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setAutoRefreshOnLaunch(value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        // 默认启动页面
        SettingActionRow(
          label: '默认启动页面',
          value: '当前: ${SettingsService.defaultStartPageLabel}',
          buttonLabel: SettingsService.defaultStartPageLabel,
          autofocus: false,
          onMoveUp: null,
          sidebarFocusNode: widget.sidebarFocusNode,
          optionLabels: SettingsService.defaultStartPageOptions.values.toList(),
          selectedOption: SettingsService.defaultStartPageLabel,
          onTap: null,
          onOptionSelected: (selectedLabel) async {
            // 根据选中的标签找到对应的 key
            final entry = SettingsService.defaultStartPageOptions.entries
                .firstWhere((e) => e.value == selectedLabel);
            await SettingsService.setDefaultStartPage(entry.key);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        // 每行视频列数
        SettingActionRow(
          label: '每行视频列数',
          value: '当前: $_videoGridColumns 列',
          buttonLabel: '$_videoGridColumns 列',
          autofocus: false,
          onMoveUp: null,
          sidebarFocusNode: widget.sidebarFocusNode,
          optionLabels: const ['4 列', '5 列', '6 列'],
          selectedOption: '$_videoGridColumns 列',
          onTap: null,
          onOptionSelected: (selectedLabel) async {
            final columns = int.parse(selectedLabel.replaceAll(' 列', ''));
            await SettingsService.setVideoGridColumns(columns);
            setState(() => _videoGridColumns = columns);
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        // 右侧栏宽度
        SettingActionRow(
          label: '播放页侧栏宽度',
          value:
              '当前: ${SettingsService.sidePanelWidthLabel(_sidePanelWidthRatio)}',
          buttonLabel: SettingsService.sidePanelWidthLabel(
            _sidePanelWidthRatio,
          ),
          autofocus: false,
          onMoveUp: null,
          sidebarFocusNode: widget.sidebarFocusNode,
          optionLabels: SettingsService.sidePanelWidthOptions
              .map((r) => SettingsService.sidePanelWidthLabel(r))
              .toList(),
          selectedOption: SettingsService.sidePanelWidthLabel(
            _sidePanelWidthRatio,
          ),
          onTap: null,
          onOptionSelected: (selectedLabel) async {
            // 根据选中的标签找到对应的值
            final options = SettingsService.sidePanelWidthOptions;
            final idx = options.indexWhere(
              (r) => SettingsService.sidePanelWidthLabel(r) == selectedLabel,
            );
            if (idx >= 0) {
              await SettingsService.setSidePanelWidthRatio(options[idx]);
              setState(() => _sidePanelWidthRatio = options[idx]);
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        // 时间显示开关（全局）
        SettingToggleRow(
          label: '显示时间',
          subtitle: '在界面右上角显示当前时间',
          value: SettingsService.showTimeDisplay,
          autofocus: false,
          onMoveUp: null, // 允许自然向上导航到上一项
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setShowTimeDisplay(value);
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        // 字体大小
        SettingActionRow(
          label: '字体大小',
          value: '当前: ${SettingsService.fontScaleLabel(_fontScale)}',
          buttonLabel: SettingsService.fontScaleLabel(_fontScale),
          sidebarFocusNode: widget.sidebarFocusNode,
          isLast: true,
          onMoveDown: () => _themeColorFocusNodes[0].requestFocus(),
          optionLabels: SettingsService.fontScaleOptions
              .map((s) => SettingsService.fontScaleLabel(s))
              .toList(),
          selectedOption: SettingsService.fontScaleLabel(_fontScale),
          onTap: null,
          onOptionSelected: (selectedLabel) async {
            // 根据选中的标签找到对应的值
            final options = SettingsService.fontScaleOptions;
            final idx = options.indexWhere(
              (s) => SettingsService.fontScaleLabel(s) == selectedLabel,
            );
            if (idx >= 0) {
              await SettingsService.setFontScale(options[idx]);
              setState(() => _fontScale = options[idx]);
            }
          },
        ),
        const SizedBox(height: AppSpacing.settingItemGap),
        // 主题色
        Padding(
          padding: AppSpacing.settingSectionTitlePadding,
          child: Text(
            '主题色',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 14), // 颜色选项与标题对齐
            itemCount: SettingsService.themeColorOptions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final entry = SettingsService.themeColorOptions.entries.elementAt(
                index,
              );
              final colorValue = entry.key;
              final label = entry.value;
              final isSelected = _themeColorValue == colorValue;

              return TvFocusScope(
                pattern: FocusPattern.horizontal,
                enableKeyRepeat: true,
                focusNode: _themeColorFocusNodes[index],
                isFirst: index == 0,
                isLast: index == SettingsService.themeColorOptions.length - 1,
                exitLeft: widget.sidebarFocusNode,
                exitDown: _categoryToggleFocusNodes[0],
                onSelect: () {
                  SettingsService.setThemeColor(colorValue);
                  setState(() => _themeColorValue = colorValue);
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return GestureDetector(
                      onTap: () {
                        SettingsService.setThemeColor(colorValue);
                        setState(() => _themeColorValue = colorValue);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Color(colorValue),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: focused
                                    ? Colors.white
                                    : (isSelected
                                          ? Colors.white70
                                          : Colors.transparent),
                                width: focused ? 3 : (isSelected ? 2 : 0),
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            style: TextStyle(
                              color: focused ? Colors.white : Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // 分区开关
        Padding(
          padding: AppSpacing.settingSectionTitlePadding,
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
                enableKeyRepeat: true,
                focusNode: _categoryToggleFocusNodes[index],
                isFirst: index == 0,
                isLast: index == _categoryOrder.length - 1,
                exitLeft: widget.sidebarFocusNode,
                exitUp: _themeColorFocusNodes[0],
                onExitDown: () {
                  // 跳转到分区排序的第一个已启用分区
                  final enabled = _categoryOrder
                      .where((n) => SettingsService.isCategoryEnabled(n))
                      .toList();
                  if (enabled.isNotEmpty) {
                    final idx = _categoryOrder.indexOf(enabled.first);
                    if (idx >= 0 && idx < _categoryOrderFocusNodes.length) {
                      _categoryOrderFocusNodes[idx].requestFocus();
                    }
                  }
                },
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
                            ? SettingsService.themeColor.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: focused
                              ? Colors.white
                              : isEnabled
                              ? SettingsService.themeColor
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
          padding: AppSpacing.settingSectionTitlePadding,
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
                  ? SettingsService.themeColor
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

                        // 向上导航到分区开关第一项
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _categoryToggleFocusNodes[0].requestFocus();
                          return KeyEventResult.handled;
                        }

                        // 向下导航到直播分区开关
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (_liveCategoryToggleFocusNodes.isNotEmpty) {
                            _liveCategoryToggleFocusNodes.first.requestFocus();
                          }
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
                                  ? SettingsService.themeColor
                                  : focused
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: null,
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
          padding: AppSpacing.settingSectionTitlePadding,
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
                enableKeyRepeat: true,
                focusNode: _liveCategoryToggleFocusNodes[index],
                isFirst: index == 0,
                isLast: index == _liveCategoryOrder.length - 1,
                exitLeft: widget.sidebarFocusNode,
                onExitUp: () {
                  final enabled = _categoryOrder
                      .where((n) => SettingsService.isCategoryEnabled(n))
                      .toList();
                  if (enabled.isNotEmpty) {
                    final idx = _categoryOrder.indexOf(enabled.first);
                    if (idx >= 0 && idx < _categoryOrderFocusNodes.length) {
                      _categoryOrderFocusNodes[idx].requestFocus();
                    }
                  }
                },
                onExitDown: () {
                  // 跳转到直播分区排序的第一个已启用分区
                  final enabled = _liveCategoryOrder
                      .where((n) => SettingsService.isLiveCategoryEnabled(n))
                      .toList();
                  if (enabled.isNotEmpty) {
                    final idx = _liveCategoryOrder.indexOf(enabled.first);
                    if (idx >= 0 && idx < _liveCategoryOrderFocusNodes.length) {
                      _liveCategoryOrderFocusNodes[idx].requestFocus();
                    }
                  }
                },
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
                            ? SettingsService.themeColor.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: focused
                              ? Colors.white
                              : isEnabled
                              ? SettingsService.themeColor
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
          padding: AppSpacing.settingSectionTitlePadding,
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
                  ? SettingsService.themeColor
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child:
              _liveCategoryOrder
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
                                      ? SettingsService.themeColor
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
        color: SettingsService.themeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: SettingsService.themeColor, size: 16),
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
