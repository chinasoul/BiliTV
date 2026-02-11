import 'package:flutter/material.dart';

enum LiveSettingsMenuType { main, quality, danmaku, line }

class LiveSettingsPanel extends StatefulWidget {
  final LiveSettingsMenuType menuType;
  final int focusedIndex;
  final String qualityDesc;
  final List<Map<String, dynamic>> qualities;
  final int currentQuality;

  // Line Settings
  final List<Map<String, dynamic>> lines;
  final int currentLineIndex;

  // Danmaku Settings
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuArea;
  final double danmakuSpeed;
  final bool hideTopDanmaku;
  final bool hideBottomDanmaku;

  // Callbacks
  final Function(LiveSettingsMenuType, int) onNavigate;
  final Function(int) onQualitySelect;
  final Function(int) onLineSelect;
  final Function(String, dynamic) onDanmakuSettingChange;

  const LiveSettingsPanel({
    super.key,
    required this.menuType,
    required this.focusedIndex,
    required this.qualityDesc,
    required this.qualities,
    required this.currentQuality,
    this.lines = const [],
    this.currentLineIndex = 0,
    required this.danmakuEnabled,
    required this.danmakuOpacity,
    required this.danmakuFontSize,
    required this.danmakuArea,
    required this.danmakuSpeed,
    required this.hideTopDanmaku,
    required this.hideBottomDanmaku,
    required this.onNavigate,
    required this.onQualitySelect,
    required this.onLineSelect,
    required this.onDanmakuSettingChange,
  });

  @override
  State<LiveSettingsPanel> createState() => _LiveSettingsPanelState();
}

class _LiveSettingsPanelState extends State<LiveSettingsPanel> {
  final ScrollController _scrollController = ScrollController();
  static const List<double> _danmakuAreaOptions = [0.125, 0.25, 0.5, 0.75, 1.0];

  @override
  void didUpdateWidget(LiveSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.menuType == LiveSettingsMenuType.danmaku ||
            widget.menuType == LiveSettingsMenuType.line) &&
        widget.focusedIndex != oldWidget.focusedIndex) {
      _scrollToFocused();
    }
  }

  void _scrollToFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        const itemHeight = 80.0;
        final targetOffset = widget.focusedIndex * itemHeight;
        final currentOffset = _scrollController.offset;
        final viewport = _scrollController.position.viewportDimension;

        if (targetOffset < currentOffset) {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else if (targetOffset + itemHeight > currentOffset + viewport) {
          _scrollController.animateTo(
            targetOffset + itemHeight - viewport,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String title = '设置';
    if (widget.menuType == LiveSettingsMenuType.danmaku) title = '弹幕设置';
    if (widget.menuType == LiveSettingsMenuType.quality) title = '画质选择';
    if (widget.menuType == LiveSettingsMenuType.line) title = '线路选择';

    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 350,
      child: Container(
        color: const Color(0xFF1F1F1F).withValues(alpha: 0.95),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (widget.menuType == LiveSettingsMenuType.main)
                    const Icon(Icons.settings, color: Colors.white54),
                ],
              ),
            ),
            // 列表内容
            Expanded(child: _buildSettingsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsList() {
    switch (widget.menuType) {
      case LiveSettingsMenuType.danmaku:
        return _buildDanmakuSettingsList();
      case LiveSettingsMenuType.quality:
        return _buildQualitySettingsList();
      case LiveSettingsMenuType.line:
        return _buildLineSettingsList();
      case LiveSettingsMenuType.main:
        return _buildMainSettingsList();
    }
  }

  Widget _buildMainSettingsList() {
    final hasLines = widget.lines.length > 1;
    final currentLineName = widget.lines.isNotEmpty
        ? widget.lines[widget.currentLineIndex]['name'] ?? '默认'
        : '默认';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingItem(
          index: 0,
          icon: Icons.hd,
          title: '画质',
          value: widget.qualityDesc,
          onTap: () => widget.onNavigate(LiveSettingsMenuType.quality, 0),
        ),
        if (hasLines)
          _buildSettingItem(
            index: 1,
            icon: Icons.router,
            title: '线路',
            value: currentLineName,
            onTap: () => widget.onNavigate(LiveSettingsMenuType.line, 0),
          ),
        _buildSettingItem(
          index: hasLines ? 2 : 1,
          icon: Icons.subtitles,
          title: '弹幕设置',
          value: widget.danmakuEnabled ? '开' : '关',
          onTap: () => widget.onNavigate(LiveSettingsMenuType.danmaku, 0),
        ),
      ],
    );
  }

  Widget _buildDanmakuSettingsList() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingItem(
          index: 0,
          icon: widget.danmakuEnabled ? Icons.subtitles : Icons.subtitles_off,
          title: '弹幕开关',
          value: widget.danmakuEnabled ? '开' : '关',
          onTap: () =>
              widget.onDanmakuSettingChange('enabled', !widget.danmakuEnabled),
        ),
        _buildSettingItem(
          index: 1,
          icon: Icons.opacity,
          title: '弹幕透明度',
          value: '${(widget.danmakuOpacity * 100).toInt()}%',
          onTap: () {
            double newVal = widget.danmakuOpacity + 0.2;
            if (newVal > 1.0) newVal = 0.2;
            widget.onDanmakuSettingChange('opacity', newVal);
          },
        ),
        _buildSettingItem(
          index: 2,
          icon: Icons.format_size,
          title: '弹幕字体大小',
          value: widget.danmakuFontSize.toInt().toString(),
          onTap: () {
            double newVal = widget.danmakuFontSize + 5.0; // 15, 20, 25, 30
            if (newVal > 30.0) newVal = 15.0;
            widget.onDanmakuSettingChange('fontSize', newVal);
          },
        ),
        _buildSettingItem(
          index: 3,
          icon: Icons.aspect_ratio,
          title: '弹幕占屏比',
          value: _getDanmakuAreaText(),
          onTap: () =>
              widget.onDanmakuSettingChange('area', _nextDanmakuArea()),
        ),
        _buildSettingItem(
          index: 4,
          icon: Icons.shutter_speed,
          title: '弹幕速度',
          value: widget.danmakuSpeed.toInt().toString(),
          onTap: () {
            double newVal = widget.danmakuSpeed + 5.0;
            if (newVal > 20.0) newVal = 5.0;
            widget.onDanmakuSettingChange('speed', newVal);
          },
        ),
        _buildSettingItem(
          index: 5,
          icon: Icons.vertical_align_top,
          title: '允许顶部悬停弹幕',
          value: !widget.hideTopDanmaku ? '开' : '关',
          onTap: () =>
              widget.onDanmakuSettingChange('hideTop', !widget.hideTopDanmaku),
        ),
        _buildSettingItem(
          index: 6,
          icon: Icons.vertical_align_bottom,
          title: '允许底部悬停弹幕',
          value: !widget.hideBottomDanmaku ? '开' : '关',
          onTap: () => widget.onDanmakuSettingChange(
            'hideBottom',
            !widget.hideBottomDanmaku,
          ),
        ),
      ],
    );
  }

  Widget _buildLineSettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: widget.lines.asMap().entries.map((entry) {
        final index = entry.key;
        final line = entry.value;
        final name = line['name'] as String;
        final isSelected = index == widget.currentLineIndex;

        return _buildSettingItem(
          index: index,
          icon: isSelected ? Icons.check_circle : Icons.circle_outlined,
          title: name,
          value: '',
          onTap: () => widget.onLineSelect(index),
        );
      }).toList(),
    );
  }

  Widget _buildQualitySettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: widget.qualities.asMap().entries.map((entry) {
        final index = entry.key;
        final quality = entry.value;
        final qn = quality['qn'] as int;
        final desc = quality['desc'] as String;
        final isSelected = qn == widget.currentQuality;

        return _buildSettingItem(
          index: index,
          icon: isSelected ? Icons.check_circle : Icons.circle_outlined,
          title: desc,
          value: '',
          onTap: () => widget.onQualitySelect(qn),
        );
      }).toList(),
    );
  }

  String _getDanmakuAreaText() {
    switch (_normalizedDanmakuArea()) {
      case 1.0:
        return '满屏';
      case 0.75:
        return '3/4屏';
      case 0.5:
        return '半屏';
      case 0.25:
        return '1/4屏';
      default:
        return '1/8屏';
    }
  }

  double _normalizedDanmakuArea() {
    return _danmakuAreaOptions.firstWhere(
      (v) => widget.danmakuArea <= v + 0.001,
      orElse: () => _danmakuAreaOptions.last,
    );
  }

  double _nextDanmakuArea() {
    final current = _normalizedDanmakuArea();
    final index = _danmakuAreaOptions.indexOf(current);
    return _danmakuAreaOptions[(index + 1) % _danmakuAreaOptions.length];
  }

  Widget _buildSettingItem({
    required int index,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    final isFocused = widget.focusedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isFocused ? const Color(0xFFfb7299) : Colors.transparent,
            border: isFocused
                ? const Border(
                    left: BorderSide(color: Color(0xFFfb7299), width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isFocused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isFocused
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.9),
                        fontSize: 15,
                        fontWeight: isFocused
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (value.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.menuType == LiveSettingsMenuType.main)
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
