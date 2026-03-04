import 'package:flutter/material.dart';
import 'tv_live_card.dart';
import 'package:bili_tv_app/config/app_style.dart';

class TvLiveHorizontalList extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final Function(dynamic) onTap;
  final VoidCallback? onHeaderFocus;
  final FocusNode? firstItemFocusNode;

  const TvLiveHorizontalList({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onHeaderFocus,
    this.firstItemFocusNode,
  });

  @override
  State<TvLiveHorizontalList> createState() => _TvLiveHorizontalListState();
}

class _TvLiveHorizontalListState extends State<TvLiveHorizontalList> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return FocusScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 12, top: 24),
            child: Text(
              widget.title,
              style: TextStyle(
                color: AppColors.primaryText,
                fontSize: AppFonts.sizeXL,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 列表
          SizedBox(
            height: 240, // 增加高度以避免裁剪 (was 180)
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: widget.items.length,
              addAutomaticKeepAlives: true,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return Container(
                    width: 240, // 固定宽度
                    margin: const EdgeInsets.only(right: 20),
                    child: TvLiveCard(
                      room: item,
                      onTap: () => widget.onTap(item),
                      onFocus: () {
                        _scrollToIndex(index);
                      },
                      autofocus: index == 0 && widget.firstItemFocusNode != null
                          ? true
                          : false,
                    ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToIndex(int index) {
    // 简单的滚动逻辑: 居中显示
    // 240 width + 20 margin = 260
    final offset = index * 260.0;
    // 屏幕宽度假设 1920?
    // 让其尽可能居中或靠左显示
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset, // 简单靠左滚动
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
}
