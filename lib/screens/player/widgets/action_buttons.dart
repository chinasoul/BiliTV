import 'package:flutter/material.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../services/bilibili_api.dart';
import '../../../models/video.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 点赞/投币/收藏 按钮组件
class ActionButtons extends StatefulWidget {
  final Video video;
  final int aid;
  final bool isFocused; // 整个组件是否被聚焦
  final VoidCallback? onFocusExit; // 用户退出时回调
  final VoidCallback? onUserInteraction; // 用户交互回调 (用于重置定时器)

  const ActionButtons({
    super.key,
    required this.video,
    required this.aid,
    this.isFocused = false,
    this.onFocusExit,
    this.onUserInteraction,
  });

  @override
  State<ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<ActionButtons> {
  bool _isLiked = false;
  int _coinCount = 0;
  bool _isFavorited = false;
  int _focusedIndex = 0; // 0=点赞, 1=投币, 2=收藏
  bool _isLoading = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadStatus();
    if (widget.isFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aid != widget.aid) {
      _loadStatus();
    }
    // 当 isFocused 变为 true 时请求焦点
    if (widget.isFocused && !oldWidget.isFocused) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (widget.aid <= 0) return;

    final results = await Future.wait([
      BilibiliApi.checkLikeStatus(widget.aid),
      BilibiliApi.checkCoinStatus(widget.aid),
      BilibiliApi.checkFavoriteStatus(widget.aid),
    ]);

    if (mounted) {
      setState(() {
        _isLiked = results[0] as bool;
        _coinCount = results[1] as int;
        _isFavorited = results[2] as bool;
      });
    }
  }

  Future<void> _onLike() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final success = await BilibiliApi.likeVideo(
      aid: widget.aid,
      like: !_isLiked,
    );

    if (success) {
      setState(() => _isLiked = !_isLiked);
      ToastUtils.dismiss();
      ToastUtils.show(context, _isLiked ? '已点赞' : '已取消点赞');
    } else {
      ToastUtils.dismiss();
      ToastUtils.show(context, '操作失败');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _onCoin() async {
    if (_isLoading || _coinCount >= 2) {
      if (_coinCount >= 2) {
        ToastUtils.dismiss();
        ToastUtils.show(context, '已投满2个硬币');
      }
      return;
    }
    setState(() => _isLoading = true);

    final error = await BilibiliApi.coinVideo(aid: widget.aid, count: 1);

    if (error == null) {
      setState(() => _coinCount = _coinCount + 1);
      ToastUtils.dismiss();
      ToastUtils.show(context, '投币成功 ($_coinCount/2)');

      // 触发交互回调，重置隐藏定时器
      widget.onUserInteraction?.call();
    } else {
      ToastUtils.dismiss();
      ToastUtils.show(context, error);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _onFavorite() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final success = await BilibiliApi.favoriteVideo(
      aid: widget.aid,
      favorite: !_isFavorited,
    );

    if (success) {
      setState(() => _isFavorited = !_isFavorited);
      ToastUtils.dismiss();
      ToastUtils.show(context, _isFavorited ? '已收藏' : '已取消收藏');
    } else {
      ToastUtils.dismiss();
      ToastUtils.show(context, '操作失败');
    }
    setState(() => _isLoading = false);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    return TvKeyHandler.handleNavigation(
      event,
      onLeft: () {
        setState(() => _focusedIndex = (_focusedIndex - 1).clamp(0, 2));
        widget.onUserInteraction?.call();
      },
      onRight: () {
        setState(() => _focusedIndex = (_focusedIndex + 1).clamp(0, 2));
        widget.onUserInteraction?.call();
      },
      onUp: () => widget.onFocusExit?.call(),
      onSelect: () {
        switch (_focusedIndex) {
          case 0:
            _onLike();
            break;
          case 1:
            _onCoin();
            break;
          case 2:
            _onFavorite();
            break;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) =>
          widget.isFocused ? _handleKeyEvent(event) : KeyEventResult.ignored,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(
              index: 0,
              svgPath: 'assets/icons/like.svg',
              label: _isLiked ? '已点赞' : '点赞',
              isActive: _isLiked,
            ),
            const SizedBox(width: 24),
            _buildButton(
              index: 1,
              svgPath: 'assets/icons/coin.svg',
              label: _coinCount > 0 ? '已投($_coinCount/2)个币' : '投币',
              isActive: _coinCount > 0,
            ),
            const SizedBox(width: 24),
            _buildButton(
              index: 2,
              svgPath: 'assets/icons/favorite.svg',
              label: _isFavorited ? '已收藏' : '收藏',
              isActive: _isFavorited,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required int index,
    required String svgPath,
    required String label,
    bool isActive = false,
  }) {
    final isFocused = widget.isFocused && _focusedIndex == index;
    final color = isActive ? SettingsService.themeColor : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.all(isFocused ? 12 : 8),
      decoration: BoxDecoration(
        color: isFocused
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isFocused ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            svgPath,
            width: isFocused ? 32 : 28,
            height: isFocused ? 32 : 28,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: isFocused ? AppFonts.sizeMD : AppFonts.sizeSM),
          ),
        ],
      ),
    );
  }
}
