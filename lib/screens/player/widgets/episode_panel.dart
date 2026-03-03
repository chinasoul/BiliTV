import 'package:flutter/material.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

class EpisodePanel extends StatefulWidget {
  final List<dynamic> episodes;
  final int currentCid;
  final int focusedIndex;
  final Function(int cid) onEpisodeSave;
  final VoidCallback onClose;
  final bool isUgcSeason;
  final String? currentBvid;
  final Function(String bvid)? onUgcEpisodeSelect;
  final bool hasBothTabs;
  final bool showingPagesTab;

  const EpisodePanel({
    super.key,
    required this.episodes,
    required this.currentCid,
    required this.focusedIndex,
    required this.onEpisodeSave,
    required this.onClose,
    this.isUgcSeason = false,
    this.currentBvid,
    this.onUgcEpisodeSelect,
    this.hasBothTabs = false,
    this.showingPagesTab = false,
  });

  @override
  State<EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<EpisodePanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToIndex(widget.focusedIndex),
    );
  }

  @override
  void didUpdateWidget(EpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showingPagesTab != oldWidget.showingPagesTab) {
      // tab 切换：等布局完成后重置滚动位置再定位到焦点项
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
          _scrollToIndex(widget.focusedIndex);
        }
      });
    } else if (widget.focusedIndex != oldWidget.focusedIndex) {
      _scrollToIndex(widget.focusedIndex);
    }
  }

  /// 每项高度 = padding(15*2) + 文本行高(fontSize 16 * ~1.4) ≈ 52，再乘以字体缩放
  double get _itemHeight => 52.0 * SettingsService.fontScale;

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final itemHeight = _itemHeight;
    final offset = index * itemHeight;
    final viewport = _scrollController.position.viewportDimension;

    final currentOffset = _scrollController.offset;

    if (offset < currentOffset) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (offset + itemHeight > currentOffset + viewport) {
      _scrollController.animateTo(
        offset + itemHeight - viewport,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = SettingsService.getSidePanelWidth(context);

    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: panelWidth,
      child: Container(
        color: SidePanelStyle.background,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: widget.hasBothTabs
                  ? Row(
                      children: [
                        Text(
                          '合集',
                          style: TextStyle(
                            color: !widget.showingPagesTab
                                ? SettingsService.themeColor
                                : AppColors.textHint,
                            fontSize: AppFonts.sizeXL,
                            fontWeight: !widget.showingPagesTab
                                ? FontWeight.bold
                                : AppFonts.regular,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '|',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.2),
                              fontSize: AppFonts.sizeXL,
                            ),
                          ),
                        ),
                        Text(
                          '分P',
                          style: TextStyle(
                            color: widget.showingPagesTab
                                ? SettingsService.themeColor
                                : AppColors.textHint,
                            fontSize: AppFonts.sizeXL,
                            fontWeight: widget.showingPagesTab
                                ? FontWeight.bold
                                : AppFonts.regular,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '◀▶ 切换',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: AppFonts.sizeSM,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Text(
                          widget.isUgcSeason ? '合集' : '分P',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppFonts.sizeXL,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: widget.episodes.length,
                itemBuilder: (context, index) {
                  final episode = widget.episodes[index];

                  final bool isCurrent;
                  final String title;
                  final VoidCallback onTap;

                  if (widget.isUgcSeason) {
                    // 合集：按 bvid 判断当前集，显示标题
                    isCurrent = episode['bvid'] == widget.currentBvid;
                    title = episode['title'] ?? '第${index + 1}集';
                    onTap = () {
                      if (widget.onUgcEpisodeSelect != null) {
                        widget.onUgcEpisodeSelect!(episode['bvid']);
                      }
                    };
                  } else {
                    // 分P：按 cid 判断当前集
                    isCurrent = episode['cid'] == widget.currentCid;
                    final partName =
                        episode['part'] ?? episode['page_part'] ?? '';
                    title = 'P${index + 1} $partName';
                    onTap = () => widget.onEpisodeSave(episode['cid']);
                  }

                  return _EpisodeItem(
                    title: title,
                    isSelected: isCurrent,
                    isFocused: widget.focusedIndex == index,
                    onTap: onTap,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  final bool isFocused;
  final VoidCallback onTap;

  const _EpisodeItem({
    required this.title,
    required this.isSelected,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: isFocused
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isSelected
                ? SettingsService.themeColor
                : (isFocused
                      ? SettingsService.themeColor.withValues(alpha: 0.5)
                      : Colors.transparent),
            width: 4,
          ),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: isSelected ? SettingsService.themeColor : Colors.white,
          fontSize: AppFonts.sizeLG,
          fontWeight: isSelected || isFocused
              ? FontWeight.bold
              : AppFonts.regular,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
