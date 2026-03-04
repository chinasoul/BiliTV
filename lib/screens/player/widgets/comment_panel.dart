import 'package:flutter/material.dart';
import '../../../services/settings_service.dart';
import '../../../config/app_style.dart';
import '../../../widgets/comment_list_view.dart';

/// 播放器评论侧面板（从右侧滑入）
class CommentPanel extends StatelessWidget {
  final int aid;
  final VoidCallback onClose;

  const CommentPanel({super.key, required this.aid, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final panelWidth = SettingsService.getSidePanelWidth(context);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: panelWidth,
        height: double.infinity,
        color: AppColors.sidePanelBackgroundAdaptive,
        child: CommentListView(
          aid: aid,
          onClose: onClose,
        ),
      ),
    );
  }
}
