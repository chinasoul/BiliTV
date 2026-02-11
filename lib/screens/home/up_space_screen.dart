import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../widgets/time_display.dart';
import '../../widgets/tv_video_card.dart';
import '../player/player_screen.dart';

class UpSpaceScreen extends StatefulWidget {
  final int upMid;
  final String upName;
  final String upFace;

  const UpSpaceScreen({
    super.key,
    required this.upMid,
    required this.upName,
    required this.upFace,
  });

  @override
  State<UpSpaceScreen> createState() => _UpSpaceScreenState();
}

class _UpSpaceScreenState extends State<UpSpaceScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, FocusNode> _videoFocusNodes = {};

  List<Video> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String _order = 'pubdate'; // pubdate / click

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadVideos(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _videoFocusNodes.clear();
    super.dispose();
  }

  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  void _onScroll() {
    if (!_isLoading &&
        !_isLoadingMore &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadVideos(reset: false);
    }
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _videos = [];
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final list = await BilibiliApi.getSpaceVideos(
      mid: widget.upMid,
      page: reset ? 1 : _page,
      order: _order,
    );
    if (!mounted) return;

    setState(() {
      if (reset) {
        _videos = list;
        _isLoading = false;
      } else {
        final existing = _videos.map((v) => v.bvid).toSet();
        _videos.addAll(list.where((v) => !existing.contains(v.bvid)));
        _isLoadingMore = false;
      }
      _hasMore = list.isNotEmpty;
      if (!reset && list.isNotEmpty) {
        _page += 1;
      } else if (reset) {
        _page = 2;
      }
    });
  }

  Future<void> _toggleOrder() async {
    setState(() => _order = _order == 'pubdate' ? 'click' : 'pubdate');
    await _loadVideos(reset: true);
  }

  void _openVideo(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    final gridColumns = SettingsService.videoGridColumns;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _videos.isEmpty
                ? const Center(
                    child: Text(
                      '该 UP 暂无投稿视频',
                      style: TextStyle(color: Colors.white70, fontSize: 20),
                    ),
                  )
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(30, 110, 30, 80),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: gridColumns,
                                childAspectRatio: 320 / 280,
                                crossAxisSpacing: 20,
                                mainAxisSpacing: 30,
                              ),
                          delegate: SliverChildBuilderDelegate((context, index) {
                            final video = _videos[index];
                            return Builder(
                              builder: (ctx) => TvVideoCard(
                                video: video,
                                focusNode: _getFocusNode(index),
                                autofocus: index == 0,
                                disableCache: false,
                                onTap: () => _openVideo(video),
                                onFocus: () {
                                  if (!_scrollController.hasClients) return;
                                  final RenderObject? object = ctx
                                      .findRenderObject();
                                  if (object != null && object is RenderBox) {
                                    final viewport = RenderAbstractViewport.of(
                                      object,
                                    );
                                    final offsetToReveal = viewport
                                        .getOffsetToReveal(object, 0.0)
                                        .offset;
                                    final targetOffset = (offsetToReveal - 120)
                                        .clamp(
                                          0.0,
                                          _scrollController
                                              .position
                                              .maxScrollExtent,
                                        );
                                    if ((_scrollController.offset - targetOffset)
                                            .abs() >
                                        50) {
                                      _scrollController.animateTo(
                                        targetOffset,
                                        duration: const Duration(
                                          milliseconds: 500,
                                        ),
                                        curve: Curves.easeOutCubic,
                                      );
                                    }
                                  }
                                },
                              ),
                            );
                          }, childCount: _videos.length),
                        ),
                      ),
                      if (_isLoadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF121212),
              padding: const EdgeInsets.fromLTRB(30, 20, 30, 15),
              child: Row(
                children: [
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: widget.upFace,
                      cacheManager: BiliCacheManager.instance,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: Colors.white12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.person, color: Colors.white54),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: Colors.white12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.person, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.upName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _toggleOrder,
                    icon: Icon(
                      _order == 'pubdate' ? Icons.schedule : Icons.whatshot,
                      color: const Color(0xFFfb7299),
                    ),
                    label: Text(
                      _order == 'pubdate' ? '按最新' : '按最热',
                      style: const TextStyle(color: Color(0xFFfb7299)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(top: 20, right: 30, child: TimeDisplay()),
        ],
      ),
    );
  }
}
