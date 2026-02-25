import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/build_flags.dart';
import 'tabs/playback_settings.dart';
import 'tabs/danmaku_settings.dart';
import 'tabs/interface_settings.dart';
import 'tabs/plugins_settings.dart';
import 'tabs/storage_settings.dart';
import 'tabs/about_settings.dart';
import 'tabs/device_info_settings.dart';
import 'tabs/developer_settings.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 设置分类枚举
enum SettingsCategory {
  playback('播放设置'),
  danmaku('弹幕设置'),
  interface_('界面设置'),
  plugins('插件中心'),
  storage('其他设置'),
  about('关于软件'),
  deviceInfo('本机信息'),
  developerOptions('开发者选项');

  const SettingsCategory(this.label);
  final String label;
}

class SettingsView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;

  const SettingsView({super.key, this.sidebarFocusNode});

  @override
  State<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends State<SettingsView> {
  int _selectedCategoryIndex = 0;
  late List<FocusNode> _categoryFocusNodes;
  late List<ScrollController> _contentScrollControllers;
  Timer? _focusVisibleDebounce;
  DateTime _lastFocusScrollAt = DateTime(0);
  static const Duration _rapidFocusThreshold = Duration(milliseconds: 150);
  List<SettingsCategory> get _visibleCategories => [
    SettingsCategory.interface_,
    SettingsCategory.playback,
    SettingsCategory.danmaku,
    if (BuildFlags.pluginsEnabled) SettingsCategory.plugins,
    SettingsCategory.storage,
    SettingsCategory.about,
    SettingsCategory.deviceInfo,
    if (SettingsService.developerMode) SettingsCategory.developerOptions,
  ];

  @override
  void initState() {
    super.initState();
    _categoryFocusNodes = List.generate(
      _visibleCategories.length,
      (_) => FocusNode(),
    );
    _contentScrollControllers = List.generate(
      _visibleCategories.length,
      (_) => ScrollController(),
    );
    SettingsService.onDeveloperModeChanged = _onDeveloperModeChanged;
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    _focusVisibleDebounce?.cancel();
    SettingsService.onDeveloperModeChanged = null;
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    for (final controller in _contentScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onPrimaryFocusChanged() {
    _focusVisibleDebounce?.cancel();
    _focusVisibleDebounce = Timer(const Duration(milliseconds: 10), () {
      if (!mounted) return;
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext == null) return;
      final owner = focusedContext.findAncestorStateOfType<SettingsViewState>();
      if (owner != this) return;
      _scrollFocusedIntoView(focusedContext);
    });
  }

  void _scrollFocusedIntoView(BuildContext focusedContext) {
    final measurableContext = _findMeasurableContext(focusedContext);
    if (measurableContext == null) return;
    final ro = measurableContext.findRenderObject() as RenderBox?;
    if (ro == null || !ro.hasSize) return;

    final selectedController = _contentScrollControllers[_selectedCategoryIndex];
    if (!selectedController.hasClients) return;

    final scrollableContext =
        selectedController.position.context.notificationContext;
    if (scrollableContext == null) return;
    final scrollableRO = scrollableContext.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    Offset itemInViewport;
    try {
      itemInViewport = ro.localToGlobal(Offset.zero, ancestor: scrollableRO);
    } catch (_) {
      return;
    }
    final viewportHeight = scrollableRO.size.height;
    final itemHeight = ro.size.height;
    final itemTop = itemInViewport.dy;
    final itemBottom = itemTop + itemHeight;

    // 设置页内容区域已经位于 header 下方，因此不额外叠加 topOffset。
    // 混合阈值：行高比例 + 视口托底（并限制上下界），避免固定像素在不同分辨率下体感漂移。
    final viewportBasedReveal = (viewportHeight * 0.06).clamp(32.0, 96.0);
    final itemBasedReveal = itemHeight * 0.25;
    final revealHeight = viewportBasedReveal > itemBasedReveal
        ? viewportBasedReveal
        : itemBasedReveal;
    final topBoundary = revealHeight;
    final bottomBoundary = viewportHeight - revealHeight;

    double? targetScrollOffset;
    if (itemBottom > bottomBoundary) {
      targetScrollOffset = selectedController.offset + (itemBottom - bottomBoundary);
    } else if (itemTop < topBoundary) {
      targetScrollOffset = selectedController.offset + (itemTop - topBoundary);
    }
    if (targetScrollOffset == null) return;

    final target = targetScrollOffset.clamp(
      selectedController.position.minScrollExtent,
      selectedController.position.maxScrollExtent,
    );
    if ((selectedController.offset - target).abs() < 4.0) return;

    final now = DateTime.now();
    final isRapid = now.difference(_lastFocusScrollAt) < _rapidFocusThreshold;
    _lastFocusScrollAt = now;
    if (isRapid) {
      selectedController.jumpTo(target);
    } else {
      selectedController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  BuildContext? _findMeasurableContext(BuildContext start) {
    BuildContext? result;

    bool checkContext(BuildContext ctx) {
      final ro = ctx.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final size = ro.size;
        if (size.width > 0 && size.height > 0) {
          result = ctx;
          return true;
        }
      }
      return false;
    }

    if (checkContext(start)) return result;
    start.visitAncestorElements((element) {
      return !checkContext(element);
    });
    return result;
  }

  void _onDeveloperModeChanged() {
    if (!mounted) return;
    setState(() {
      // 重建 FocusNode 列表以匹配新的 tab 数量
      for (var node in _categoryFocusNodes) {
        node.dispose();
      }
      _categoryFocusNodes = List.generate(
        _visibleCategories.length,
        (_) => FocusNode(),
      );
      for (final controller in _contentScrollControllers) {
        controller.dispose();
      }
      _contentScrollControllers = List.generate(
        _visibleCategories.length,
        (_) => ScrollController(),
      );
      // 如果当前选中的 index 超出范围（关闭开发者模式时可能发生），回退
      if (_selectedCategoryIndex >= _visibleCategories.length) {
        _selectedCategoryIndex = _visibleCategories.length - 1;
      }
    });
  }

  /// 请求第一个分类标签的焦点（用于从侧边栏导航）
  void focusFirstCategory() {
    if (_categoryFocusNodes.isNotEmpty) {
      _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
    }
  }

  /// 处理返回键：如果焦点在设置项上，先回到分类标签；否则返回 false 让上层处理
  bool handleBack() {
    // 检查焦点是否在分类标签上
    for (final node in _categoryFocusNodes) {
      if (node.hasFocus) {
        return false; // 已经在分类标签上，让上层处理（回到侧边栏）
      }
    }
    // 焦点在设置项或其他地方，回到当前分类标签
    _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
    return true;
  }

  /// 构建分类标签
  Widget _buildCategoryTab({
    required String label,
    required bool isSelected,
    required FocusNode focusNode,
    required VoidCallback onTap,
    VoidCallback? onMoveLeft,
    VoidCallback? onMoveRight,
  }) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) => f ? onTap() : null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            onMoveLeft != null) {
          onMoveLeft();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
            onMoveRight != null) {
          onMoveRight();
          return KeyEventResult.handled;
        }
        // 设置页顶部，阻止向上导航
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                focusNode.requestFocus();
                onTap();
              },
              child: Container(
                padding: TabStyle.tabPadding,
                decoration: BoxDecoration(
                  color: isFocused
                      ? SettingsService.themeColor.withValues(alpha: 0.6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(TabStyle.tabBorderRadius),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isFocused
                            ? Colors.white
                            : (isSelected
                                  ? SettingsService.themeColor
                                  : Colors.grey),
                        fontSize: TabStyle.tabFontSize,
                        fontWeight: isFocused || isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        height: TabStyle.tabLineHeight,
                      ),
                    ),
                    const SizedBox(height: TabStyle.tabUnderlineGap),
                    Container(
                      height: TabStyle.tabUnderlineHeight,
                      width: TabStyle.tabUnderlineWidth,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SettingsService.themeColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          TabStyle.tabUnderlineRadius,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void moveToCurrentTab() {
      if (_categoryFocusNodes.isNotEmpty) {
        _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
      }
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 设置内容区域 - IndexedStack 保持各 tab 状态，避免切换时重复加载
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: IndexedStack(
              index: _selectedCategoryIndex,
              children: _buildAllContents(moveToCurrentTab),
            ),
          ),
        ),

        // 设置分类标签栏（固定高度，与其他 tab 对齐）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: TabStyle.headerHeight,
          child: Container(
            color: TabStyle.headerBackgroundColor,
            padding: TabStyle.headerPadding,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_visibleCategories.length, (index) {
                  final category = _visibleCategories[index];
                  final isSelected = _selectedCategoryIndex == index;
                  return _buildCategoryTab(
                    label: category.label,
                    isSelected: isSelected,
                    focusNode: _categoryFocusNodes[index],
                    onTap: () => setState(() => _selectedCategoryIndex = index),
                    onMoveLeft: index == 0
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : null,
                    // 最后一项向右循环到第一项
                    onMoveRight: index == _visibleCategories.length - 1
                        ? () => _categoryFocusNodes[0].requestFocus()
                        : null,
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAllContents(VoidCallback moveToCurrentTab) {
    return _visibleCategories.asMap().entries.map((entry) {
      final index = entry.key;
      final category = entry.value;
      final content = _buildContentForCategory(category, moveToCurrentTab);
      return SingleChildScrollView(
        controller: _contentScrollControllers[index],
        padding: AppSpacing.settingContentPadding,
        child: content,
      );
    }).toList();
  }

  Widget _buildContentForCategory(
    SettingsCategory category,
    VoidCallback moveToCurrentTab,
  ) {
    switch (category) {
      case SettingsCategory.playback:
        return PlaybackSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.danmaku:
        return DanmakuSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.interface_:
        return InterfaceSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.plugins:
        return PluginsSettingsTab(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.storage:
        return StorageSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.about:
        return AboutSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.deviceInfo:
        return DeviceInfoSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.developerOptions:
        return DeveloperSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
    }
  }
}
