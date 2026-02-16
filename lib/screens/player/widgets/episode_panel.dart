import 'package:flutter/material.dart';
import 'package:bili_tv_app/services/settings_service.dart';

class EpisodePanel extends StatefulWidget {
  final List<dynamic> episodes;
  final int currentCid;
  final int focusedIndex;
  final Function(int cid) onEpisodeSave;
  final VoidCallback onClose;
  final bool isUgcSeason;
  final String? currentBvid;
  final Function(String bvid)? onUgcEpisodeSelect;

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
    if (widget.focusedIndex != oldWidget.focusedIndex) {
      _scrollToIndex(widget.focusedIndex);
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 54.0; // Approx height
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
        color: const Color(0xFF1F1F1F).withValues(alpha: 0.95),
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
              child: Row(
                children: [
                  Text(
                    widget.isUgcSeason ? '合集' : '分P',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
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
          fontSize: 16,
          fontWeight: isSelected || isFocused
              ? FontWeight.bold
              : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
