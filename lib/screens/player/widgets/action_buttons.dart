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
  final VoidCallback? onFocusExit; // 用户按上键退出时回调
  final VoidCallback? onDownExit; // 用户按下键退出时回调
  final VoidCallback? onRightExit; // 用户在最右按钮按右键退出时回调
  final VoidCallback? onLeftExit; // 用户在最左按钮按左键退出时回调
  final VoidCallback? onUserInteraction; // 用户交互回调 (用于重置定时器)
  final bool compact; // 紧凑模式：无文字、显示数量、无动画
  final int statLike; // 视频总点赞数
  final int statCoin; // 视频总投币数
  final int statFavorite; // 视频总收藏数
  final int statShare; // 视频总分享数
  final bool showShare; // 是否显示分享按钮
  final VoidCallback? onShareTap; // 自定义分享回调

  const ActionButtons({
    super.key,
    required this.video,
    required this.aid,
    this.isFocused = false,
    this.onFocusExit,
    this.onDownExit,
    this.onRightExit,
    this.onLeftExit,
    this.onUserInteraction,
    this.compact = false,
    this.statLike = 0,
    this.statCoin = 0,
    this.statFavorite = 0,
    this.statShare = 0,
    this.showShare = false,
    this.onShareTap,
  });

  @override
  State<ActionButtons> createState() => ActionButtonsState();
}

class ActionButtonsState extends State<ActionButtons> {
  bool _isLiked = false;
  int _coinCount = 0;
  bool _isFavorited = false;
  int _focusedIndex = 0; // 0=点赞, 1=投币, 2=收藏, 3=分享(可选)
  bool _isLoading = false;
  final FocusNode _focusNode = FocusNode();
  final Map<int, GlobalKey> _buttonKeys = {};

  GlobalKey _getButtonKey(int index) {
    return _buttonKeys.putIfAbsent(index, () => GlobalKey());
  }

  int get focusedIndex => _focusedIndex;
  int get maxButtonIndex => _maxIndex;

  void setFocusedIndex(int index) {
    if (index >= 0 && index <= _maxIndex) {
      _focusedIndex = index;
    }
  }

  void requestInternalFocus() {
    _focusNode.requestFocus();
  }

  Offset? getButtonCenter(int index) {
    final key = _buttonKeys[index];
    if (key == null) return null;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final pos = box.localToGlobal(Offset.zero);
    return Offset(pos.dx + box.size.width / 2, pos.dy + box.size.height / 2);
  }

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

  /// 刷新点赞/投币/收藏状态（从外部调用）
  void refreshStatus() => _loadStatus();

  int get _maxIndex => widget.showShare ? 3 : 2;

  void _onShare() {
    if (widget.onShareTap != null) {
      widget.onShareTap!();
      return;
    }
    ToastUtils.dismiss();
    ToastUtils.show(context, '已分享');
    BilibiliApi.shareVideo(aid: widget.aid, bvid: widget.video.bvid);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    return TvKeyHandler.handleNavigationWithRepeat(
      event,
      onLeft: () {
        if (_focusedIndex > 0) {
          setState(() => _focusedIndex--);
          widget.onUserInteraction?.call();
        } else {
          widget.onLeftExit?.call();
        }
      },
      onRight: () {
        if (_focusedIndex < _maxIndex) {
          setState(() => _focusedIndex++);
          widget.onUserInteraction?.call();
        } else {
          widget.onRightExit?.call();
        }
      },
      onUp: () => widget.onFocusExit?.call(),
      onDown: () => widget.onDownExit?.call(),
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
          case 3:
            _onShare();
            break;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = SettingsService.themeColor;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) =>
          widget.isFocused ? _handleKeyEvent(event) : KeyEventResult.ignored,
      child: Container(
        padding: widget.compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: widget.compact
            ? null
            : BoxDecoration(
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
              statCount: widget.statLike,
              themeColor: themeColor,
            ),
            SizedBox(width: widget.compact ? 4 : 24),
            _buildButton(
              index: 1,
              svgPath: 'assets/icons/coin.svg',
              label: _coinCount > 0 ? '已投($_coinCount/2)个币' : '投币',
              isActive: _coinCount > 0,
              statCount: widget.statCoin,
              themeColor: themeColor,
            ),
            SizedBox(width: widget.compact ? 4 : 24),
            _buildButton(
              index: 2,
              svgPath: 'assets/icons/favorite.svg',
              label: _isFavorited ? '已收藏' : '收藏',
              isActive: _isFavorited,
              statCount: widget.statFavorite,
              themeColor: themeColor,
            ),
            if (widget.showShare) ...[
              SizedBox(width: widget.compact ? 4 : 24),
              _buildButton(
                index: 3,
                icon: Icons.share_outlined,
                svgPath: '',
                label: '分享',
                statCount: widget.statShare,
                themeColor: themeColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }

  Widget _buildIconWidget(String svgPath, IconData? icon, double size, Color color) {
    if (svgPath.isNotEmpty) {
      return SvgPicture.asset(
        svgPath,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(icon ?? Icons.help_outline, size: size, color: color);
  }

  Widget _buildButton({
    required int index,
    required String svgPath,
    required String label,
    required Color themeColor,
    IconData? icon,
    bool isActive = false,
    int statCount = 0,
  }) {
    final isFocused = widget.isFocused && _focusedIndex == index;
    final color = isActive ? themeColor : Colors.white;

    if (widget.compact) {
      return Container(
        key: _getButtonKey(index),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isFocused
              ? themeColor.withValues(alpha: AppColors.focusAlpha)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIconWidget(svgPath, icon, 22, color),
            if (statCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                _formatCount(statCount),
                style: TextStyle(color: color, fontSize: AppFonts.sizeSM),
              ),
            ],
          ],
        ),
      );
    }

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
          _buildIconWidget(svgPath, icon, isFocused ? 32 : 28, color),
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
