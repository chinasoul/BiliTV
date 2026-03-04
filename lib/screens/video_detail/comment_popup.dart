import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_style.dart';
import '../../widgets/comment_list_view.dart';

/// 评论弹窗（半透明遮罩 + 居中大弹窗），用于视频详情页
class CommentPopup extends StatelessWidget {
  final int aid;
  final VoidCallback onClose;

  const CommentPopup({super.key, required this.aid, required this.onClose});

  static bool _isBackKey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.browserBack;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final popupWidth = (screenSize.width * 0.78).clamp(900.0, 1500.0);
    final popupHeight = (screenSize.height * 0.82).clamp(560.0, 980.0);

    return FocusScope(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (_isBackKey(event)) return KeyEventResult.ignored;
        return KeyEventResult.handled;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: Container(color: AppColors.popupBarrier),
            ),
          ),
          Center(
            child: Container(
              width: popupWidth,
              height: popupHeight,
              decoration: BoxDecoration(
                color: AppColors.popupBackgroundAdaptive,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.navItemSelectedBackground, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: CommentListView(
                aid: aid,
                onClose: onClose,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
