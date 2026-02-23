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
  deviceInfo('本机信息');

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
  List<SettingsCategory> get _visibleCategories => [
    SettingsCategory.interface_,
    SettingsCategory.playback,
    SettingsCategory.danmaku,
    if (BuildFlags.pluginsEnabled) SettingsCategory.plugins,
    SettingsCategory.storage,
    SettingsCategory.about,
    SettingsCategory.deviceInfo,
  ];

  @override
  void initState() {
    super.initState();
    _categoryFocusNodes = List.generate(
      _visibleCategories.length,
      (_) => FocusNode(),
    );
  }

  @override
  void dispose() {
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
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
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

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
          return Container(
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
    return _visibleCategories.map((category) {
      final content = _buildContentForCategory(category, moveToCurrentTab);
      return SingleChildScrollView(
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
    }
  }
}
