import 'package:flutter/material.dart';

enum SettingsMenuType { main, quality, danmaku, speed }

class SettingsPanel extends StatefulWidget {
  final SettingsMenuType menuType;
  final int focusedIndex;
  final String qualityDesc;
  final double playbackSpeed;
  final List<double> availableSpeeds;

  // Danmaku Settings
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuArea;
  final double danmakuSpeed;
  final bool hideTopDanmaku;
  final bool hideBottomDanmaku;

  // Callbacks
  final Function(SettingsMenuType, int) onNavigate;
  final VoidCallback onQualityPicker;

  const SettingsPanel({
    super.key,
    required this.menuType,
    required this.focusedIndex,
    required this.qualityDesc,
    required this.playbackSpeed,
    required this.availableSpeeds,
    required this.danmakuEnabled,
    required this.danmakuOpacity,
    required this.danmakuFontSize,
    required this.danmakuArea,
    required this.danmakuSpeed,
    required this.hideTopDanmaku,
    required this.hideBottomDanmaku,
    required this.onNavigate,
    required this.onQualityPicker,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.menuType == SettingsMenuType.danmaku &&
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
    if (widget.menuType == SettingsMenuType.danmaku) title = '弹幕设置';
    if (widget.menuType == SettingsMenuType.speed) title = '倍速播放';
    if (widget.menuType == SettingsMenuType.quality) title = '画质选择';

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
                  /*
                  if (widget.menuType != SettingsMenuType.main)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  */
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (widget.menuType == SettingsMenuType.main)
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
      case SettingsMenuType.danmaku:
        return _buildDanmakuSettingsList();
      case SettingsMenuType.speed:
        return _buildSpeedSettingsList();
      case SettingsMenuType.main:
      default:
        return _buildMainSettingsList();
    }
  }

  Widget _buildMainSettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingItem(
          index: 0,
          icon: Icons.hd,
          title: '画质',
          value: widget.qualityDesc,
          onTap: widget.onQualityPicker,
        ),
        _buildSettingItem(
          index: 1,
          icon: Icons.subtitles,
          title: '弹幕设置',
          value: widget.danmakuEnabled ? '开' : '关',
          onTap: () => widget.onNavigate(SettingsMenuType.danmaku, 0),
        ),
        _buildSettingItem(
          index: 2,
          icon: Icons.speed,
          title: '播放速度',
          value: '${widget.playbackSpeed}x',
          onTap: () => widget.onNavigate(SettingsMenuType.speed, 0),
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
          onTap: () {},
        ),
        _buildSettingItem(
          index: 1,
          icon: Icons.opacity,
          title: '弹幕透明度',
          value: widget.danmakuOpacity.toStringAsFixed(1),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 2,
          icon: Icons.format_size,
          title: '弹幕字体大小',
          value: widget.danmakuFontSize.toInt().toString(),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 3,
          icon: Icons.aspect_ratio,
          title: '弹幕占屏比',
          value: _getDanmakuAreaText(),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 4,
          icon: Icons.shutter_speed,
          title: '弹幕速度',
          value: widget.danmakuSpeed.toInt().toString(),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 5,
          icon: Icons.vertical_align_top,
          title: '允许顶部悬停弹幕',
          value: !widget.hideTopDanmaku ? '开' : '关',
          onTap: () {},
        ),
        _buildSettingItem(
          index: 6,
          icon: Icons.vertical_align_bottom,
          title: '允许底部悬停弹幕',
          value: !widget.hideBottomDanmaku ? '开' : '关',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildSpeedSettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: widget.availableSpeeds.asMap().entries.map((entry) {
        final index = entry.key;
        final speed = entry.value;
        final isSelected = speed == widget.playbackSpeed;
        return _buildSettingItem(
          index: index,
          icon: Icons.speed,
          title: '${speed}x',
          value: isSelected ? '当前' : '',
          onTap: () {},
        );
      }).toList(),
    );
  }

  String _getDanmakuAreaText() {
    if (widget.danmakuArea >= 1.0) return '满屏';
    if (widget.danmakuArea >= 0.75) return '3/4屏';
    if (widget.danmakuArea >= 0.5) return '半屏';
    if (widget.danmakuArea >= 0.25) return '1/4屏';
    return '1/8屏';
  }

  Widget _buildSettingItem({
    required int index,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    // Determine if focused based on parent index
    final isFocused = widget.focusedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isFocused
                ? const Color(0xFF81C784).withValues(alpha: 0.3)
                : Colors.transparent,
            border: isFocused
                ? const Border(
                    left: BorderSide(color: Color(0xFF81C784), width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isFocused
                    ? const Color(0xFF81C784)
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
              if (widget.menuType == SettingsMenuType.main && index > 0)
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
