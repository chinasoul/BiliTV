import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import 'package:bili_tv_app/utils/image_url_utils.dart';
import 'package:bili_tv_app/config/app_style.dart';
import 'package:bili_tv_app/services/bilibili_api.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/models/video.dart';
import '../player/player_screen.dart';
import '../player/widgets/action_buttons.dart';
import '../home/search/search_results_view.dart';
import 'comment_popup.dart';

enum _FocusZone { cover, actions, comment, upFollow, labels, episodes }

class VideoDetailScreen extends StatefulWidget {
  final Video video;
  final bool fromPlayer;

  const VideoDetailScreen({
    super.key,
    required this.video,
    this.fromPlayer = false,
  });

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  final FocusNode _mainFocusNode = FocusNode();
  final GlobalKey<ActionButtonsState> _actionButtonsKey = GlobalKey();
  final ScrollController _episodeScrollController = ScrollController();
  final Map<int, FocusNode> _episodeFocusNodes = {};

  // Data
  Map<String, dynamic>? _videoInfo;
  Map<String, dynamic>? _upInfo;
  bool _isLoading = true;
  bool _isFollowing = false;
  int _aid = 0;

  // Episodes (分P or 合集)
  final List<Map<String, dynamic>> _episodes = [];
  String _episodeTitle = '';

  // Honor (ranking)
  String? _honorText;

  // Video tags
  List<String> _videoTags = [];

  // Focus state
  _FocusZone _focusZone = _FocusZone.cover;
  int _episodeFocusIndex = 0;
  int _labelFocusIndex = 0;
  bool _showCommentPopup = false;
  bool _showSharePopup = false;

  // Label position tracking for multi-line navigation
  final Map<int, GlobalKey> _labelKeys = {};
  final GlobalKey _commentButtonKey = GlobalKey();


  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
      _showDetailHintIfNeeded();
    });
  }

  void _showDetailHintIfNeeded() {
    if (widget.fromPlayer) return;
    if (SettingsService.videoDetailHintShown) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      ToastUtils.show(
        context,
        '该页可关闭，见「播放设置」',
        duration: const Duration(seconds: 4),
      );
      SettingsService.setVideoDetailHintShown(true);
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _episodeScrollController.dispose();
    for (final node in _episodeFocusNodes.values) {
      node.dispose();
    }
    _episodeFocusNodes.clear();
    super.dispose();
  }

  GlobalKey _getLabelKey(int index) {
    return _labelKeys.putIfAbsent(index, () => GlobalKey());
  }

  Offset? _getLabelPos(int index) {
    final key = _labelKeys[index];
    if (key == null) return null;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final pos = box.localToGlobal(Offset.zero);
    return Offset(pos.dx + box.size.width / 2, pos.dy);
  }

  /// Find the label closest to [targetX] among labels on a different row.
  /// [direction] > 0 means search forward (down), < 0 means backward (up).
  int? _findLabelInAdjacentRow(int fromIndex, int direction) {
    final currentPos = _getLabelPos(fromIndex);
    if (currentPos == null) return null;
    final currentY = currentPos.dy;
    final targetX = currentPos.dx;
    final labels = _allLabels;

    // Collect labels on the adjacent row
    double? adjacentRowY;
    final candidates = <int>[];

    final start = direction > 0 ? fromIndex + 1 : fromIndex - 1;
    final end = direction > 0 ? labels.length : -1;
    final step = direction > 0 ? 1 : -1;

    for (int i = start; i != end; i += step) {
      final pos = _getLabelPos(i);
      if (pos == null) continue;
      if ((pos.dy - currentY).abs() <= 4) continue; // same row
      if (adjacentRowY == null) {
        adjacentRowY = pos.dy;
        candidates.add(i);
      } else if ((pos.dy - adjacentRowY).abs() <= 4) {
        candidates.add(i); // same adjacent row
      } else {
        break; // moved past the adjacent row
      }
    }

    if (candidates.isEmpty) return null;

    // Find closest by x-position
    int best = candidates.first;
    double bestDist = double.infinity;
    for (final i in candidates) {
      final pos = _getLabelPos(i);
      if (pos == null) continue;
      final dist = (pos.dx - targetX).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  Offset? _getWidgetCenter(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final pos = box.localToGlobal(Offset.zero);
    return Offset(pos.dx + box.size.width / 2, pos.dy + box.size.height / 2);
  }

  int _findClosestLabelOnFirstRow(double targetX) {
    final labels = _allLabels;
    if (labels.isEmpty) return 0;
    double? firstRowY;
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < labels.length; i++) {
      final pos = _getLabelPos(i);
      if (pos == null) continue;
      if (firstRowY == null) firstRowY = pos.dy;
      if ((pos.dy - firstRowY).abs() > 4) break;
      final dist = (pos.dx - targetX).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  void _goFromLabelsToClosestAbove() {
    final currentPos = _getLabelPos(_labelFocusIndex);
    if (currentPos == null) {
      setState(() => _focusZone = _FocusZone.actions);
      return;
    }
    final targetX = currentPos.dx;
    double bestDist = double.infinity;
    int bestActionIndex = -1;
    bool useComment = false;

    final actionState = _actionButtonsKey.currentState;
    if (actionState != null) {
      for (int i = 0; i < 4; i++) {
        final center = actionState.getButtonCenter(i);
        if (center != null) {
          final dist = (center.dx - targetX).abs();
          if (dist < bestDist) {
            bestDist = dist;
            bestActionIndex = i;
            useComment = false;
          }
        }
      }
    }

    final commentCenter = _getWidgetCenter(_commentButtonKey);
    if (commentCenter != null) {
      final dist = (commentCenter.dx - targetX).abs();
      if (dist < bestDist) {
        useComment = true;
      }
    }

    if (useComment) {
      setState(() => _focusZone = _FocusZone.comment);
    } else {
      if (bestActionIndex >= 0) {
        actionState?.setFocusedIndex(bestActionIndex);
      }
      setState(() => _focusZone = _FocusZone.actions);
    }
  }

  FocusNode _getEpisodeFocusNode(int index) {
    return _episodeFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  Future<void> _loadData() async {
    final videoInfoFuture = BilibiliApi.getVideoInfo(widget.video.bvid);
    final upInfoFuture = widget.video.ownerMid > 0
        ? BilibiliApi.getUserCardInfo(widget.video.ownerMid)
        : Future<Map<String, dynamic>?>.value(null);
    final tagsFuture = BilibiliApi.getVideoTags(widget.video.bvid);

    final results = await Future.wait([videoInfoFuture, upInfoFuture]);
    final tags = await tagsFuture;

    if (!mounted) return;

    final videoInfo = results[0];
    final upInfo = results[1];

    if (videoInfo != null) {
      _aid = videoInfo['aid'] ?? 0;
      _parseHonor(videoInfo);
      _parseEpisodes(videoInfo);
    }

    setState(() {
      _videoInfo = videoInfo;
      _upInfo = upInfo;
      _isFollowing = upInfo?['following'] ?? false;
      _videoTags = tags;
      _isLoading = false;
    });
  }

  void _parseHonor(Map<String, dynamic> info) {
    final honorReply = info['honor_reply'] as Map<String, dynamic>?;
    if (honorReply == null) return;
    final honors = honorReply['honor'] as List?;
    if (honors == null || honors.isEmpty) return;
    for (final h in honors) {
      if (h['type'] == 3 || h['type'] == 2 || h['type'] == 1 || h['type'] == 4) {
        _honorText = h['desc'] as String?;
        if (_honorText != null) return;
      }
    }
  }

  void _parseEpisodes(Map<String, dynamic> info) {
    // UGC season (合集) takes priority
    final ugcSeason = info['ugc_season'] as Map<String, dynamic>?;
    if (ugcSeason != null) {
      _episodeTitle = ugcSeason['title'] as String? ?? '合集';
      final sections = ugcSeason['sections'] as List?;
      if (sections != null && sections.isNotEmpty) {
        for (final section in sections) {
          final eps = section['episodes'] as List?;
          if (eps != null) {
            for (final ep in eps) {
              _episodes.add({
                'title': ep['title'] ?? '',
                'cid': ep['cid'] ?? 0,
                'aid': ep['aid'] ?? 0,
                'bvid': ep['bvid'] ?? '',
                'duration': ep['arc']?['duration'] ?? ep['page']?['duration'] ?? 0,
              });
            }
          }
        }
        final reversed = List<Map<String, dynamic>>.from(_episodes.reversed);
        _episodes
          ..clear()
          ..addAll(reversed);
        return;
      }
    }

    // Multi-part (分P)
    final pages = info['pages'] as List?;
    if (pages != null && pages.length > 1) {
      _episodeTitle = '分P列表';
      for (final page in pages) {
        _episodes.add({
          'title': page['part'] ?? 'P${page['page']}',
          'cid': page['cid'] ?? 0,
          'page': page['page'] ?? 1,
          'duration': page['duration'] ?? 0,
        });
      }
    }
  }

  void _playVideo({int? cid, int? page, String? bvid, int? aid}) {
    if (widget.fromPlayer) {
      if (bvid != null && bvid.isNotEmpty && bvid != widget.video.bvid) {
        Navigator.of(context).pop(Video(
          bvid: bvid,
          title: widget.video.title,
          pic: widget.video.pic,
          ownerName: widget.video.ownerName,
          ownerFace: widget.video.ownerFace,
          ownerMid: widget.video.ownerMid,
        ));
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    final video = (bvid != null && bvid.isNotEmpty && bvid != widget.video.bvid)
        ? Video(
            bvid: bvid,
            title: widget.video.title,
            pic: widget.video.pic,
            ownerName: widget.video.ownerName,
            ownerFace: widget.video.ownerFace,
            ownerMid: widget.video.ownerMid,
          )
        : widget.video;
    final fromDetailCover = cid == null && page == null && aid == null;

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              video: video,
              exitPopDepth: fromDetailCover ? 2 : 1,
            ),
          ),
        )
        .then((_) {
          if (!mounted) return;
          _actionButtonsKey.currentState?.refreshStatus();
          _mainFocusNode.requestFocus();
        });
  }

  Future<void> _toggleFollow() async {
    final mid = widget.video.ownerMid;
    if (mid <= 0) return;
    final success = await BilibiliApi.followUser(
      mid: mid,
      follow: !_isFollowing,
    );
    if (!mounted) return;
    if (success) {
      setState(() => _isFollowing = !_isFollowing);
      ToastUtils.dismiss();
      ToastUtils.show(context, _isFollowing ? '已关注' : '已取消关注');
    } else {
      ToastUtils.dismiss();
      ToastUtils.show(context, '操作失败');
    }
  }

  void _openCommentPopup() {
    if (_aid <= 0) return;
    setState(() => _showCommentPopup = true);
  }

  void _closeCommentPopup() {
    setState(() => _showCommentPopup = false);
    _restoreFocusAfterPopup();
  }

  void _openSharePopup() {
    setState(() => _showSharePopup = true);
    BilibiliApi.shareVideo(aid: _aid, bvid: widget.video.bvid);
  }

  void _closeSharePopup() {
    setState(() => _showSharePopup = false);
    _restoreFocusAfterPopup();
  }

  void _restoreFocusAfterPopup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusZone == _FocusZone.actions) {
        _actionButtonsKey.currentState?.requestInternalFocus();
      } else {
        _mainFocusNode.requestFocus();
      }
    });
  }

  // ==================== Focus Navigation ====================

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Back key: always let PopScope handle it
    if (event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      return KeyEventResult.ignored;
    }

    if (_showCommentPopup || _showSharePopup) return KeyEventResult.ignored;

    if (_focusZone == _FocusZone.actions) {
      return KeyEventResult.handled;
    }

    if (_focusZone == _FocusZone.labels) {
      return _handleLabelNavigation(event);
    }

    if (_focusZone == _FocusZone.episodes) {
      return _handleEpisodeNavigation(event);
    }

    return TvKeyHandler.handleNavigationWithRepeat(
      event,
      onLeft: () => _navigateLeft(),
      onRight: () => _navigateRight(),
      onUp: () => _navigateUp(),
      onDown: () => _navigateDown(),
      onSelect: () => _handleSelect(),
    );
  }

  void _navigateLeft() {
    switch (_focusZone) {
      case _FocusZone.actions:
        break; // Handled by ActionButtons internally
      case _FocusZone.comment:
        _actionButtonsKey.currentState?.setFocusedIndex(
          _actionButtonsKey.currentState!.maxButtonIndex,
        );
        setState(() => _focusZone = _FocusZone.actions);
      case _FocusZone.upFollow:
        setState(() => _focusZone = _FocusZone.comment);
      case _FocusZone.labels:
        break; // Handled by _handleLabelNavigation
      case _FocusZone.cover:
        break;
      case _FocusZone.episodes:
        break; // Handled by _handleEpisodeNavigation
    }
  }

  void _navigateRight() {
    switch (_focusZone) {
      case _FocusZone.cover:
        _actionButtonsKey.currentState?.setFocusedIndex(0);
        setState(() => _focusZone = _FocusZone.actions);
      case _FocusZone.actions:
        break; // Handled by ActionButtons internally
      case _FocusZone.comment:
        setState(() => _focusZone = _FocusZone.upFollow);
      case _FocusZone.upFollow:
        break;
      case _FocusZone.labels:
        break; // Handled by _handleLabelNavigation
      case _FocusZone.episodes:
        break; // Handled by _handleEpisodeNavigation
    }
  }

  void _navigateUp() {
    switch (_focusZone) {
      case _FocusZone.cover:
        break;
      case _FocusZone.actions:
        break;
      case _FocusZone.comment:
        break;
      case _FocusZone.upFollow:
        break;
      case _FocusZone.labels:
        break; // Handled by _handleLabelNavigation
      case _FocusZone.episodes:
        break; // Handled by _handleEpisodeNavigation
    }
  }

  void _navigateDown() {
    switch (_focusZone) {
      case _FocusZone.cover:
        if (_episodes.isNotEmpty) {
          setState(() {
            _focusZone = _FocusZone.episodes;
            _episodeFocusIndex = 0;
          });
          _scrollToEpisode(0);
        }
      case _FocusZone.actions:
        if (_allLabels.isNotEmpty) {
          setState(() {
            _focusZone = _FocusZone.labels;
            _labelFocusIndex = 0;
          });
        } else if (_episodes.isNotEmpty) {
          setState(() {
            _focusZone = _FocusZone.episodes;
            _episodeFocusIndex = 0;
          });
          _scrollToEpisode(0);
        }
      case _FocusZone.comment:
        if (_allLabels.isNotEmpty) {
          final center = _getWidgetCenter(_commentButtonKey);
          final labelIdx = center != null
              ? _findClosestLabelOnFirstRow(center.dx)
              : 0;
          setState(() {
            _focusZone = _FocusZone.labels;
            _labelFocusIndex = labelIdx;
          });
        } else if (_episodes.isNotEmpty) {
          setState(() {
            _focusZone = _FocusZone.episodes;
            _episodeFocusIndex = 0;
          });
          _scrollToEpisode(0);
        }
      case _FocusZone.upFollow:
        if (_episodes.isNotEmpty) {
          setState(() {
            _focusZone = _FocusZone.episodes;
            _episodeFocusIndex = 0;
          });
          _scrollToEpisode(0);
        }
      case _FocusZone.labels:
        break; // Handled by _handleLabelNavigation
      case _FocusZone.episodes:
        break; // Handled by _handleEpisodeNavigation
    }
  }

  void _handleSelect() {
    switch (_focusZone) {
      case _FocusZone.cover:
        _playVideo();
      case _FocusZone.comment:
        _openCommentPopup();
      case _FocusZone.upFollow:
        _toggleFollow();
      case _FocusZone.labels:
        break;
      case _FocusZone.actions:
      case _FocusZone.episodes:
        break;
    }
  }

  void _searchByLabel(String keyword) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: AppColors.background,
              body: SearchResultsView(
                query: keyword,
                onBackToKeyboard: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        )
        .then((_) {
          if (!mounted) return;
          _mainFocusNode.requestFocus();
        });
  }

  KeyEventResult _handleLabelNavigation(KeyEvent event) {
    final labels = _allLabels;
    return TvKeyHandler.handleNavigationWithRepeat(
      event,
      onLeft: () {
        if (_labelFocusIndex > 0) {
          final currentPos = _getLabelPos(_labelFocusIndex);
          final prevPos = _getLabelPos(_labelFocusIndex - 1);
          if (currentPos != null && prevPos != null &&
              (prevPos.dy - currentPos.dy).abs() > 4) {
            setState(() => _focusZone = _FocusZone.cover);
          } else {
            setState(() => _labelFocusIndex--);
          }
        } else {
          setState(() => _focusZone = _FocusZone.cover);
        }
      },
      onRight: () {
        if (_labelFocusIndex < labels.length - 1) {
          final currentPos = _getLabelPos(_labelFocusIndex);
          final nextPos = _getLabelPos(_labelFocusIndex + 1);
          if (currentPos != null && nextPos != null &&
              (nextPos.dy - currentPos.dy).abs() > 4) {
            setState(() => _focusZone = _FocusZone.upFollow);
          } else {
            setState(() => _labelFocusIndex++);
          }
        } else {
          setState(() => _focusZone = _FocusZone.upFollow);
        }
      },
      onUp: () {
        final target = _findLabelInAdjacentRow(_labelFocusIndex, -1);
        if (target != null) {
          setState(() => _labelFocusIndex = target);
        } else {
          _goFromLabelsToClosestAbove();
        }
      },
      onDown: () {
        final target = _findLabelInAdjacentRow(_labelFocusIndex, 1);
        if (target != null) {
          setState(() => _labelFocusIndex = target);
        } else {
          _goFromLabelsToEpisodes();
        }
      },
      onSelect: () {
        if (_labelFocusIndex < labels.length) {
          _searchByLabel(labels[_labelFocusIndex]);
        }
      },
    );
  }

  void _goFromLabelsToEpisodes() {
    if (_episodes.isNotEmpty) {
      setState(() {
        _focusZone = _FocusZone.episodes;
        _episodeFocusIndex = 0;
      });
      _scrollToEpisode(0);
    }
  }

  KeyEventResult _handleEpisodeNavigation(KeyEvent event) {
    final columns = _episodeGridColumns;
    return TvKeyHandler.handleNavigationWithRepeat(
      event,
      onLeft: () {
        if (_episodeFocusIndex % columns > 0) {
          setState(() => _episodeFocusIndex--);
          _scrollToEpisode(_episodeFocusIndex);
        }
      },
      onRight: () {
        if (_episodeFocusIndex % columns < columns - 1 &&
            _episodeFocusIndex + 1 < _episodes.length) {
          setState(() => _episodeFocusIndex++);
          _scrollToEpisode(_episodeFocusIndex);
        }
      },
      onUp: () {
        if (_episodeFocusIndex >= columns) {
          setState(() => _episodeFocusIndex -= columns);
          _scrollToEpisode(_episodeFocusIndex);
        } else {
          setState(() => _focusZone = _FocusZone.cover);
        }
      },
      onDown: () {
        if (_episodeFocusIndex + columns < _episodes.length) {
          setState(() => _episodeFocusIndex += columns);
          _scrollToEpisode(_episodeFocusIndex);
        }
      },
      onSelect: () {
        if (_episodeFocusIndex < _episodes.length) {
          final ep = _episodes[_episodeFocusIndex];
          _playVideo(
            cid: ep['cid'],
            page: ep['page'],
            bvid: ep['bvid'],
            aid: ep['aid'],
          );
        }
      },
    );
  }

  List<String> get _allLabels {
    final tname = _videoInfo?['tname'] as String? ?? '';
    final labels = <String>[];
    if (tname.isNotEmpty) labels.add(tname);
    labels.addAll(_videoTags);
    return labels;
  }

  int get _episodeGridColumns {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1600) return 6;
    if (screenWidth > 1200) return 5;
    return 4;
  }

  DateTime _lastEpisodeFocusTime = DateTime(0);
  static const _rapidThreshold = Duration(milliseconds: 150);

  void _scrollToEpisode(int index) {
    final now = DateTime.now();
    final isRapid = now.difference(_lastEpisodeFocusTime) < _rapidThreshold;
    _lastEpisodeFocusTime = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollEpisodeToSafeZone(index, animate: !isRapid);
    });
  }

  void _scrollEpisodeToSafeZone(int index, {required bool animate}) {
    if (!_episodeScrollController.hasClients) return;

    final focusNode = _episodeFocusNodes[index];
    final cardRO = focusNode?.context?.findRenderObject() as RenderBox?;
    if (cardRO == null || !cardRO.hasSize) return;

    final scrollableState = Scrollable.maybeOf(focusNode!.context!);
    if (scrollableState == null) return;

    final position = scrollableState.position;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    final cardInViewport = cardRO.localToGlobal(
      Offset.zero,
      ancestor: scrollableRO,
    );
    final viewportHeight = scrollableRO.size.height;
    final cardHeight = cardRO.size.height;
    final cardTop = cardInViewport.dy;
    final cardBottom = cardTop + cardHeight;

    final revealHeight = cardHeight * TabStyle.scrollRevealRatio;
    final topBoundary = revealHeight;
    final bottomBoundary = viewportHeight - revealHeight;

    final columns = _episodeGridColumns;
    final isFirstRow = index < columns;

    double? targetScrollOffset;

    if (isFirstRow) {
      if ((cardTop - topBoundary).abs() > 50) {
        final delta = cardTop - topBoundary;
        targetScrollOffset = position.pixels + delta;
      }
    } else if (cardBottom > bottomBoundary) {
      final delta = cardBottom - bottomBoundary;
      targetScrollOffset = position.pixels + delta;
    } else if (cardTop < topBoundary) {
      final delta = cardTop - topBoundary;
      targetScrollOffset = position.pixels + delta;
    }

    if (targetScrollOffset == null) return;

    final target = targetScrollOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((position.pixels - target).abs() < 4.0) return;

    if (animate) {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      position.jumpTo(target);
    }
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final themeColor = SettingsService.themeColor;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showSharePopup) {
          _closeSharePopup();
        } else if (_showCommentPopup) {
          _closeCommentPopup();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: FocusScope(
          autofocus: true,
          child: Focus(
            focusNode: _mainFocusNode,
            onKeyEvent: _handleKeyEvent,
            child: Stack(
            children: [
              // Blurred cover background
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: ImageUrlUtils.getResizedUrl(
                    widget.video.pic,
                    width: 480,
                    height: 270,
                  ),
                  cacheManager: BiliCacheManager.instance,
                  memCacheWidth: 480,
                  memCacheHeight: 270,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      Container(color: AppColors.background),
                  errorWidget: (_, _, _) =>
                      Container(color: AppColors.background),
                  imageBuilder: (context, imageProvider) => Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: imageProvider,
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
              ),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(themeColor),
              if (_showCommentPopup && _aid > 0)
                CommentPopup(aid: _aid, onClose: _closeCommentPopup),
              if (_showSharePopup)
                _buildSharePopup(themeColor),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildContent(Color themeColor) {
    return Column(
      children: [
        // Section 1: Header
        _buildHeaderSection(themeColor),
        // Section 2: Episodes (or empty space)
        Expanded(child: _buildEpisodesSection(themeColor)),
      ],
    );
  }

  // ==================== Section 1: Header ====================

  Widget _buildHeaderSection(Color themeColor) {
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = _episodes.isNotEmpty
        ? screenHeight * 0.38
        : screenHeight * 0.55;

    return SizedBox(
      height: headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Cover
            _buildCover(themeColor),
            const SizedBox(width: 20),
            // Middle: Video info
            Expanded(child: _buildVideoInfo(themeColor)),
            const SizedBox(width: 20),
            // Right: UP主 card
            _buildUpCard(themeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(Color themeColor) {
    final isFocused = _focusZone == _FocusZone.cover;
    final coverWidth = MediaQuery.of(context).size.width * 0.28;
    final coverHeight = coverWidth * 9 / 16;

    return GestureDetector(
      onTap: _playVideo,
      child: AnimatedContainer(
        duration: AppAnimation.fast,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isFocused
              ? themeColor.withValues(alpha: AppColors.focusAlpha)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: coverWidth,
            height: coverHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: ImageUrlUtils.getResizedUrl(
                    widget.video.pic,
                    width: 480,
                    height: 270,
                  ),
                  cacheManager: BiliCacheManager.instance,
                  memCacheWidth: 480,
                  memCacheHeight: 270,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.grey[850]),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey[850],
                    child: Icon(Icons.error, color: AppColors.inactiveText),
                  ),
                ),
                // Play icon overlay
                if (isFocused)
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                // Bottom-right: duration badge
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.video.durationFormatted,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppFonts.sizeMD,
                        fontWeight: AppFonts.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoInfo(Color themeColor) {
    final stat = _videoInfo?['stat'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Title
        Text(
          _videoInfo?['title'] ?? widget.video.title,
          style: TextStyle(
            color: Colors.white,
            fontSize: AppFonts.sizeLG,
            fontWeight: AppFonts.bold,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        // Row 2: Publish time + Honor badge
        _buildPubdateRow(themeColor),
        const SizedBox(height: 6),
        // Row 3: Action buttons + Comment button
        Row(
          children: [
            ActionButtons(
              key: _actionButtonsKey,
              video: widget.video,
              aid: _aid,
              compact: true,
              showShare: true,
              statLike: stat?['like'] ?? 0,
              statCoin: stat?['coin'] ?? 0,
              statFavorite: stat?['favorite'] ?? 0,
              statShare: stat?['share'] ?? 0,
              onShareTap: _openSharePopup,
              isFocused: _focusZone == _FocusZone.actions,
              onFocusExit: () {}, // Up from actions: no-op (already top row)
              onDownExit: () {
                if (_allLabels.isNotEmpty) {
                  final actionState = _actionButtonsKey.currentState;
                  final center = actionState?.getButtonCenter(
                    actionState.focusedIndex,
                  );
                  final labelIdx = center != null
                      ? _findClosestLabelOnFirstRow(center.dx)
                      : 0;
                  setState(() {
                    _focusZone = _FocusZone.labels;
                    _labelFocusIndex = labelIdx;
                  });
                } else if (_episodes.isNotEmpty) {
                  setState(() {
                    _focusZone = _FocusZone.episodes;
                    _episodeFocusIndex = 0;
                  });
                  _scrollToEpisode(0);
                }
              },
              onRightExit: () =>
                  setState(() => _focusZone = _FocusZone.comment),
              onLeftExit: () =>
                  setState(() => _focusZone = _FocusZone.cover),
            ),
            const SizedBox(width: 6),
            _buildCommentButton(themeColor, stat),
          ],
        ),
        const SizedBox(height: 6),
        // Row 4: Labels
        _buildLabelsRow(themeColor),
      ],
    );
  }

  Widget _buildPubdateRow(Color themeColor) {
    final pubdate = _videoInfo?['pubdate'] as int? ?? widget.video.pubdate;
    final pubdateStr = _formatPubdateFull(pubdate);
    final viewCount = _videoInfo?['stat']?['view'] as int?;

    return Row(
      children: [
        if (pubdateStr.isNotEmpty)
          Text(
            '$pubdateStr',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: AppFonts.sizeSM,
            ),
          ),
        if (viewCount != null) ...[
          const SizedBox(width: 12),
          Icon(
            Icons.play_arrow,
            color: Colors.white.withValues(alpha: 0.6),
            size: 16,
          ),
          const SizedBox(width: 2),
          Text(
            _formatCount(viewCount),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: AppFonts.sizeSM,
            ),
          ),
        ],
        if (_honorText != null) ...[
          const SizedBox(width: 12),
          Text(
            _honorText!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: AppFonts.sizeSM,
            ),
          ),
        ],
      ],
    );
  }

  String _formatPubdateFull(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月${date.day.toString().padLeft(2, '0')}日 '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  Widget _buildCommentButton(Color themeColor, Map<String, dynamic>? stat) {
    final isFocused = _focusZone == _FocusZone.comment;
    final replyCount = stat?['reply'] ?? 0;

    return GestureDetector(
      onTap: _openCommentPopup,
      child: Container(
        key: _commentButtonKey,
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
            Icon(
              Icons.comment_outlined,
              color: Colors.white,
              size: 22,
            ),
            if (replyCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                _formatCount(replyCount),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppFonts.sizeSM,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabelsRow(Color themeColor) {
    final inLabelsZone = _focusZone == _FocusZone.labels;
    final labels = _allLabels;

    if (labels.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        for (int i = 0; i < labels.length; i++)
          Container(
            key: _getLabelKey(i),
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: inLabelsZone && _labelFocusIndex == i
                  ? themeColor.withValues(alpha: AppColors.focusAlpha)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                color: inLabelsZone && _labelFocusIndex == i
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
                fontSize: AppFonts.sizeXS,
              ),
            ),
          ),
      ],
    );
  }

  // ==================== UP主 Card ====================

  Widget _buildUpCard(Color themeColor) {
    final upName = _upInfo?['name'] ?? widget.video.ownerName;
    final upFace = _upInfo?['face'] ?? widget.video.ownerFace;
    final sex = _upInfo?['sex'] ?? '保密';
    final level = _upInfo?['level'] ?? 0;
    final fans = _upInfo?['fans'] ?? 0;
    final attention = _upInfo?['attention'] ?? 0;
    final likeNum = _upInfo?['likeNum'] ?? 0;
    final archiveCount = _upInfo?['archiveCount'] ?? 0;
    final sign = (_upInfo?['sign'] as String?)?.trim() ?? '';

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // Row: Avatar + Name/Level
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: ImageUrlUtils.getResizedUrl(
                    upFace,
                    width: 96,
                    height: 96,
                  ),
                  cacheManager: BiliCacheManager.instance,
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    width: 48,
                    height: 48,
                    color: AppColors.navItemSelectedBackground,
                    child: Icon(Icons.person, color: AppColors.inactiveText),
                  ),
                  errorWidget: (_, _, _) => Container(
                    width: 48,
                    height: 48,
                    color: AppColors.navItemSelectedBackground,
                    child: Icon(Icons.person, color: AppColors.inactiveText),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppFonts.sizeMD,
                        fontWeight: AppFonts.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLevelBadge(level),
                        if (sex == '男') ...[
                          const SizedBox(width: 6),
                          Icon(Icons.male, color: Colors.blue, size: 14),
                        ] else if (sex == '女') ...[
                          const SizedBox(width: 6),
                          Icon(Icons.female, color: Colors.pink, size: 14),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Bio / sign
          if (sign.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              sign,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: AppFonts.sizeXS,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          // Stats
          Wrap(
            spacing: 10,
            runSpacing: 4,
            alignment: WrapAlignment.start,
            children: [
              _buildStatItem('粉丝', fans),
              _buildStatItem('关注', attention),
              _buildStatItem('获赞', likeNum),
              _buildStatItem('投稿', archiveCount),
            ],
          ),
          const SizedBox(height: 12),
          // Follow button
          _buildFollowButton(themeColor),
        ],
      ),
    );
  }

  Widget _buildLevelBadge(int level) {
    final color = level >= 6
        ? Colors.red
        : level >= 4
            ? Colors.orange
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        'LV$level',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: AppFonts.bold,
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatCount(value),
          style: TextStyle(
            color: Colors.white,
            fontSize: AppFonts.sizeSM,
            fontWeight: AppFonts.semibold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: AppFonts.sizeXS,
          ),
        ),
      ],
    );
  }

  Widget _buildFollowButton(Color themeColor) {
    final isFocused = _focusZone == _FocusZone.upFollow;
    return GestureDetector(
      onTap: _toggleFollow,
      child: AnimatedContainer(
        duration: AppAnimation.fast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isFocused
              ? themeColor.withValues(alpha: AppColors.focusAlpha)
              : _isFollowing
                  ? themeColor.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isFollowing ? Icons.check : Icons.add,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              _isFollowing ? '已关注' : '关注',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppFonts.sizeSM,
                fontWeight: AppFonts.semibold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Section 2: Episodes ====================

  Widget _buildEpisodesSection(Color themeColor) {
    if (_episodes.isEmpty) {
      return const SizedBox.shrink();
    }

    final columns = _episodeGridColumns;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$_episodeTitle (${_episodes.length})',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppFonts.sizeLG,
                      fontWeight: AppFonts.bold,
                    ),
                  ),
                  if (_currentEpisodeLabel != null)
                    TextSpan(
                      text: '  $_currentEpisodeLabel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: AppFonts.sizeSM,
                        fontWeight: AppFonts.regular,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Episode grid
          Expanded(
            child: GridView.builder(
              controller: _episodeScrollController,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 3.0,
                crossAxisSpacing: 10,
                mainAxisSpacing: 8,
              ),
              itemCount: _episodes.length,
              itemBuilder: (context, index) {
                return _buildEpisodeCard(index, themeColor);
              },
            ),
          ),
        ],
      ),
    );
  }

  String? get _currentEpisodeLabel {
    for (int i = 0; i < _episodes.length; i++) {
      if (_isCurrentEpisode(_episodes[i])) {
        return '该视频位于P${_episodes.length - i}';
      }
    }
    return null;
  }

  bool _isCurrentEpisode(Map<String, dynamic> ep) {
    final epBvid = ep['bvid'] as String?;
    if (epBvid != null && epBvid.isNotEmpty) {
      return epBvid == widget.video.bvid;
    }
    return ep['page'] == 1;
  }

  Widget _buildEpisodeCard(int index, Color themeColor) {
    final ep = _episodes[index];
    final isFocused =
        _focusZone == _FocusZone.episodes && _episodeFocusIndex == index;
    final isCurrent = _isCurrentEpisode(ep);
    final title = ep['title'] as String;
    final duration = ep['duration'] as int? ?? 0;

    return Focus(
      focusNode: _getEpisodeFocusNode(index),
      child: GestureDetector(
        onTap: () => _playVideo(
          cid: ep['cid'],
          page: ep['page'],
          bvid: ep['bvid'],
          aid: ep['aid'],
        ),
        child: AnimatedContainer(
          duration: AppAnimation.fast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isFocused
                ? themeColor.withValues(alpha: AppColors.focusAlpha)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${_episodes.length - index}.$title',
                  style: TextStyle(
                    color: isFocused
                        ? Colors.white
                        : isCurrent
                            ? themeColor
                            : Colors.white70,
                    fontSize: AppFonts.sizeSM,
                    fontWeight: isFocused || isCurrent
                        ? AppFonts.semibold
                        : AppFonts.regular,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (duration > 0) ...[
                const SizedBox(width: 6),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: isFocused
                        ? Colors.white70
                        : isCurrent
                            ? themeColor.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.4),
                    fontSize: AppFonts.sizeXS,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== Share Popup ====================

  Widget _buildSharePopup(Color themeColor) {
    final videoUrl = 'https://www.bilibili.com/video/${widget.video.bvid}';

    return FocusScope(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.browserBack) {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: _closeSharePopup,
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '扫码分享视频',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppFonts.sizeLG,
                        fontWeight: AppFonts.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: videoUrl,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.video.bvid,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: AppFonts.sizeSM,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '按返回键关闭',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: AppFonts.sizeXS,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Helpers ====================

  String _formatCount(int count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
