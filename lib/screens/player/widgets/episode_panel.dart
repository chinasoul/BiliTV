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

  double _getItemExtent() {
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledFontSize = textScaler.scale(AppFonts.sizeLG);
    return 30.0 + scaledFontSize * 1.25;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToIndex(widget.focusedIndex, animate: false),
    );
  }

  @override
  void didUpdateWidget(EpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showingPagesTab != oldWidget.showingPagesTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
          _scrollToIndex(widget.focusedIndex, animate: false);
        }
      });
    } else if (widget.focusedIndex != oldWidget.focusedIndex) {
      _scrollToIndex(widget.focusedIndex);
    }
  }

  void _scrollToIndex(int index, {bool animate = true}) {
    if (!_scrollController.hasClients) return;
    if (widget.episodes.isEmpty) return;

    final safeIndex = index.clamp(0, widget.episodes.length - 1);
    final itemExtent = _getItemExtent();
    final position = _scrollController.position;
    final viewportHeight = position.viewportDimension;

    final itemTop = safeIndex * itemExtent;
    final itemBottom = itemTop + itemExtent;
    final scrollTop = position.pixels;
    final scrollBottom = scrollTop + viewportHeight;

    if (itemTop >= scrollTop && itemBottom <= scrollBottom) return;

    double targetOffset;
    if (itemTop < scrollTop) {
      targetOffset = itemTop;
    } else {
      targetOffset = itemBottom - viewportHeight;
    }
    targetOffset = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((position.pixels - targetOffset).abs() < 2.0) return;

    if (animate) {
      position.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      position.jumpTo(targetOffset);
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
                    color: AppColors.navItemSelectedBackground,
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
                                : AppColors.inactiveText,
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
                              color: AppColors.inactiveText,
                              fontSize: AppFonts.sizeXL,
                            ),
                          ),
                        ),
                        Text(
                          '分P',
                          style: TextStyle(
                            color: widget.showingPagesTab
                                ? SettingsService.themeColor
                                : AppColors.inactiveText,
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
                            color: AppColors.inactiveText,
                            fontSize: AppFonts.sizeSM,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Text(
                          widget.isUgcSeason ? '合集' : '分P',
                          style: TextStyle(
                            color: AppColors.primaryText,
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
                itemExtent: _getItemExtent(),
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
    super.key,
    required this.title,
    required this.isSelected,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: isFocused
            ? AppColors.navItemSelectedBackground
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isSelected
                ? SettingsService.themeColor
                : (isFocused
                      ? SettingsService.themeColor.withValues(alpha: AppColors.focusAlpha)
                      : Colors.transparent),
            width: 4,
          ),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: isSelected ? SettingsService.themeColor : AppColors.secondaryText,
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
