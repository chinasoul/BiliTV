import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import '../models/dynamic_item.dart';
import '../services/bilibili_api.dart';
import '../services/settings_service.dart';
import '../utils/image_url_utils.dart';
import '../config/app_style.dart';
import '../widgets/comment_list_view.dart';

/// 图文 / 专栏 动态详情页
///
/// 图文模式: 图片预览 + 摘要 + 评论弹窗
/// 专栏模式: 全文 HTML 渲染 + 评论弹窗
class DynamicDetailScreen extends StatefulWidget {
  final String title;
  final String authorName;
  final String authorFace;
  final String desc;
  final List<String> images;
  final String pubdate;
  final String likeText;
  final String commentText;
  /// 评论 oid（图文=动态id, 专栏=cvid）
  final int commentOid;
  /// 评论区类型: 11=图文, 12=专栏
  final int commentType;

  const DynamicDetailScreen({
    super.key,
    required this.title,
    this.authorName = '',
    this.authorFace = '',
    this.desc = '',
    this.images = const [],
    this.pubdate = '',
    this.likeText = '0',
    this.commentText = '0',
    required this.commentOid,
    required this.commentType,
  });

  /// 从 DynamicDraw 构造
  factory DynamicDetailScreen.fromDraw(DynamicDraw draw) {
    return DynamicDetailScreen(
      title: draw.authorName,
      authorName: draw.authorName,
      authorFace: draw.authorFace,
      desc: draw.text,
      images: draw.images,
      pubdate: draw.pubdateFormatted,
      likeText: draw.likeFormatted,
      commentText: draw.commentFormatted,
      commentOid: int.tryParse(draw.id) ?? 0,
      commentType: 11,
    );
  }

  /// 从 DynamicArticle 构造
  factory DynamicDetailScreen.fromArticle(DynamicArticle article) {
    return DynamicDetailScreen(
      title: article.title,
      authorName: article.authorName,
      authorFace: article.authorFace,
      desc: article.desc,
      images: article.coverUrl.isNotEmpty ? [article.coverUrl] : [],
      pubdate: article.pubdateFormatted,
      likeText: article.likeFormatted,
      commentText: article.commentFormatted,
      commentOid: int.tryParse(article.id) ?? 0,
      commentType: 12,
    );
  }

  @override
  State<DynamicDetailScreen> createState() => _DynamicDetailScreenState();
}

class _DynamicDetailScreenState extends State<DynamicDetailScreen> {
  bool _showComments = false;
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool get _isArticleMode => widget.commentType == 12;

  // ── 专栏模式状态 ──
  String _articleHtml = '';
  bool _isLoadingArticle = false;

  // ── 图文模式状态 ──
  final FocusNode _commentBtnFocusNode = FocusNode();
  final FocusNode _closeBtnFocusNode = FocusNode();
  final Map<int, FocusNode> _imageFocusNodes = {};
  int _selectedImageIndex = 0;

  static bool _isBackKey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.browserBack;
  }

  @override
  void initState() {
    super.initState();
    if (_isArticleMode) {
      _fetchArticleContent();
    }
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _commentBtnFocusNode.dispose();
    _closeBtnFocusNode.dispose();
    _scrollController.dispose();
    for (final node in _imageFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchArticleContent() async {
    setState(() => _isLoadingArticle = true);
    final html = await BilibiliApi.getArticleContent(widget.commentOid);
    if (!mounted) return;
    setState(() {
      _articleHtml = _preprocessHtml(html);
      _isLoadingArticle = false;
    });
  }

  /// 预处理 HTML：修复协议
  static String _preprocessHtml(String html) {
    if (html.isEmpty) return html;
    // 协议相对 URL -> https（B站文章图片均使用 // 前缀）
    html = html.replaceAll('src="//', 'src="https://');
    html = html.replaceAll("src='//", "src='https://");
    // http -> https
    html = html.replaceAll('src="http://', 'src="https://');
    html = html.replaceAll("src='http://", "src='https://");
    return html;
  }

  FocusNode _getImageFocusNode(int index) {
    return _imageFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  // ─────────────────────────────────────────────────────────────
  // Key handling
  // ─────────────────────────────────────────────────────────────

  /// 系统级返回由 PopScope 处理，Focus 层不拦截
  KeyEventResult _handleMainKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && _isBackKey(event)) {
      return KeyEventResult.ignored;
    }

    // Article mode scrolling (only when comments are hidden)
    if (_isArticleMode && !_showComments) {
      return _handleArticleKeyEvent(event);
    }

    return KeyEventResult.ignored;
  }

  /// PopScope 回调：评论打开时先关评论，否则退出页面
  void _handlePopInvoked(bool didPop, dynamic _) {
    if (didPop) return;
    if (_showComments) {
      setState(() => _showComments = false);
      if (!_isArticleMode) _commentBtnFocusNode.requestFocus();
    } else {
      Navigator.of(context).pop();
    }
  }

  KeyEventResult _handleArticleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      _scrollPage(down: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _scrollPage(down: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      setState(() => _showComments = true);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollPage({required bool down}) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final step = pos.viewportDimension * 0.65;
    final target = (down ? pos.pixels + step : pos.pixels - step)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 1.0) return;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        backgroundColor: AppColors.headerBackground,
        body: Focus(
          focusNode: _mainFocusNode,
          autofocus: true,
          onKeyEvent: _handleMainKeyEvent,
          child: Stack(
            children: [
              _isArticleMode ? _buildArticleContent() : _buildDrawContent(),
              if (_showComments) _buildCommentOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ── 专栏模式 ────────────────────────────────────────────────

  Widget _buildArticleContent() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          Divider(color: AppColors.navItemSelectedBackground, height: 1),
          const SizedBox(height: 24),
          if (_isLoadingArticle)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_articleHtml.isNotEmpty)
            ..._buildArticleWidgets()
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  widget.desc.isNotEmpty ? widget.desc : '无法加载文章内容',
                  style: TextStyle(
                    color: AppColors.inactiveText,
                    fontSize: AppFonts.sizeMD,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),
          Divider(color: AppColors.navItemSelectedBackground, height: 1),
          const SizedBox(height: 16),
          _buildArticleFooter(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── 手动 HTML → Widget 渲染 ───────────────────────────────

  static TextStyle get _articleBodyStyle => TextStyle(
        color: AppColors.secondaryText,
        fontSize: 16,
        height: 1.8,
      );

  /// 将预处理后的 HTML 解析为原生 Flutter Widget 列表
  List<Widget> _buildArticleWidgets() {
    final doc = html_parser.parse(_articleHtml);
    final body = doc.body;
    if (body == null) return [];
    final out = <Widget>[];
    _walkBlockNodes(body.nodes, out);
    return out;
  }

  /// 遍历块级节点，分派到对应的渲染方法
  void _walkBlockNodes(dom.NodeList nodes, List<Widget> out) {
    for (final node in nodes) {
      if (node is dom.Text) {
        final t = node.text.trim();
        if (t.isNotEmpty) {
          out.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(t, style: _articleBodyStyle),
          ));
        }
        continue;
      }
      if (node is! dom.Element) continue;
      switch (node.localName) {
        case 'p':
          _addParagraphWidgets(node, out);
        case 'figure':
          _addFigureWidget(node, out);
        case 'img':
          _addImageWidget(node, out);
        case 'h1' || 'h2' || 'h3':
          _addHeadingWidget(node, out);
        case 'blockquote':
          _addBlockquoteWidget(node, out);
        case 'br':
          out.add(const SizedBox(height: 8));
        default:
          _walkBlockNodes(node.nodes, out);
      }
    }
  }

  /// <p> 段落：提取文本（含内联元素），同时处理嵌套的 <figure>
  void _addParagraphWidgets(dom.Element p, List<Widget> out) {
    // B站 HTML 有时把 <figure> 嵌在 <p> 中（虽然不合规范）
    for (final child in p.children) {
      if (child.localName == 'figure') {
        _addFigureWidget(child, out);
      } else if (child.localName == 'img') {
        _addImageWidget(child, out);
      }
    }
    final spans = <TextSpan>[];
    _collectInlineSpans(p.nodes, spans);
    if (_spansHaveVisibleText(spans)) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(
          TextSpan(children: spans),
          style: _articleBodyStyle,
        ),
      ));
    }
  }

  /// 递归收集行内元素为 TextSpan 列表
  void _collectInlineSpans(dom.NodeList nodes, List<TextSpan> out) {
    for (final node in nodes) {
      if (node is dom.Text) {
        final t = node.text;
        if (t.isNotEmpty) out.add(TextSpan(text: t));
        continue;
      }
      if (node is! dom.Element) continue;
      switch (node.localName) {
        case 'br':
          out.add(const TextSpan(text: '\n'));
        case 'b' || 'strong':
          final children = <TextSpan>[];
          _collectInlineSpans(node.nodes, children);
          out.add(TextSpan(
            children: children,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.primaryText),
          ));
        case 'a':
          out.add(TextSpan(
            text: node.text,
            style: const TextStyle(color: Color(0xFF00aeec)),
          ));
        case 'figure' || 'img':
          break; // 由块级渲染处理
        default:
          _collectInlineSpans(node.nodes, out);
      }
    }
  }

  bool _spansHaveVisibleText(List<TextSpan> spans) {
    for (final s in spans) {
      if (s.text != null && s.text!.trim().isNotEmpty) return true;
      if (s.children != null) {
        for (final c in s.children!) {
          if (c is TextSpan &&
              c.text != null &&
              c.text!.trim().isNotEmpty) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// <figure> 含 <img> + <figcaption>
  void _addFigureWidget(dom.Element figure, List<Widget> out) {
    final img = figure.querySelector('img');
    if (img != null) _addImageWidget(img, out);
    final caption = figure.querySelector('figcaption');
    if (caption != null && caption.text.trim().isNotEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Center(
          child: Text(
            caption.text.trim(),
            style: TextStyle(color: AppColors.inactiveText, fontSize: 13),
          ),
        ),
      ));
    }
  }

  /// 单独的 <img> 标签
  ///
  /// 横图撑满宽度（限高 420），竖图居中（限高 360、限宽 300）。
  /// 通过 CDN 缩放 + memCacheWidth 控制内存。
  void _addImageWidget(dom.Element img, List<Widget> out) {
    var src = img.attributes['src'] ?? '';
    if (src.isEmpty) return;
    if (src.startsWith('//')) src = 'https:$src';
    src = src.replaceFirst('http://', 'https://');

    final natW = double.tryParse(img.attributes['width'] ?? '') ?? 0;
    final natH = double.tryParse(img.attributes['height'] ?? '') ?? 0;
    final isPortrait = natW > 0 && natH > 0 && natH > natW * 1.2;

    // CDN 缩放：确保 URL 有 @xxxw.webp 后缀
    if (!src.contains('@') && src.contains('hdslb.com')) {
      src = '$src@800w.webp';
    }

    out.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: isPortrait ? 360 : 420,
            maxWidth: isPortrait ? 300 : double.infinity,
          ),
          child: CachedNetworkImage(
            imageUrl: src,
            fit: isPortrait ? BoxFit.contain : BoxFit.fitWidth,
            memCacheWidth: isPortrait ? 300 : 800,
            cacheManager: BiliCacheManager.instance,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => Container(
              height: 120,
              color: const Color(0xFF2d2d2d),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              height: 80,
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.broken_image,
                    size: 28, color: Colors.white24),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  /// <h1>, <h2>, <h3>
  void _addHeadingWidget(dom.Element h, List<Widget> out) {
    final text = h.text.trim();
    if (text.isEmpty) return;
    final size = switch (h.localName) {
      'h1' => 22.0,
      'h2' => 20.0,
      _ => 18.0,
    };
    out.add(Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.primaryText,
          fontSize: size,
          fontWeight: FontWeight.bold,
        ),
      ),
    ));
  }

  /// <blockquote>
  void _addBlockquoteWidget(dom.Element bq, List<Widget> out) {
    final text = bq.text.trim();
    if (text.isEmpty) return;
    out.add(Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
            left: BorderSide(
                color: AppColors.isLight
                    ? const Color(0xFFcccccc)
                    : const Color(0xFF444444),
                width: 3)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: AppColors.inactiveText, fontSize: 16, height: 1.6),
      ),
    ));
  }

  Widget _buildArticleFooter() {
    return Row(
      children: [
        Icon(Icons.chat_bubble_outline,
            size: 14, color: AppColors.inactiveText),
        const SizedBox(width: 6),
        Text(
          '按确认键查看评论 (${widget.commentText})',
          style: TextStyle(
            color: AppColors.inactiveText,
            fontSize: AppFonts.sizeSM,
          ),
        ),
      ],
    );
  }

  // ── 图文模式（保持原有逻辑不变） ─────────────────────────────

  Widget _buildDrawContent() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),

          if (widget.desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                widget.desc,
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: AppFonts.sizeMD,
                  height: 1.6,
                ),
              ),
            ),

          if (widget.images.isNotEmpty) ...[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: ImageUrlUtils.getResizedUrl(
                      widget.images[_selectedImageIndex],
                      width: 960,
                      height: 540),
                  fit: BoxFit.contain,
                  memCacheWidth: 960,
                  memCacheHeight: 540,
                  cacheManager: BiliCacheManager.instance,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) =>
                      Container(color: const Color(0xFF2d2d2d)),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey[900],
                    child: Icon(Icons.broken_image,
                        size: 40, color: Colors.white24),
                  ),
                ),
              ),
            ),
            if (widget.images.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return Focus(
                      focusNode: _getImageFocusNode(index),
                      onFocusChange: (f) {
                        if (f) setState(() => _selectedImageIndex = index);
                      },
                      onKeyEvent: (node, event) {
                        return TvKeyHandler.handleSinglePress(
                          event,
                          onLeft: index > 0
                              ? () => _getImageFocusNode(index - 1)
                                  .requestFocus()
                              : null,
                          onRight: index < widget.images.length - 1
                              ? () => _getImageFocusNode(index + 1)
                                  .requestFocus()
                              : null,
                          onDown: () =>
                              _commentBtnFocusNode.requestFocus(),
                        );
                      },
                      child: Builder(
                        builder: (ctx) {
                          final focused = Focus.of(ctx).hasFocus;
                          final selected = _selectedImageIndex == index;
                          return GestureDetector(
                            onTap: () {
                              _getImageFocusNode(index).requestFocus();
                              setState(
                                  () => _selectedImageIndex = index);
                            },
                            child: Container(
                              width: 108,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(6),
                                border: Border.all(
                                  color: focused
                                      ? SettingsService.themeColor
                                      : (selected
                                          ? SettingsService.themeColor
                                              .withValues(alpha: 0.5)
                                          : Colors.transparent),
                                  width: 2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(4),
                                child: CachedNetworkImage(
                                  imageUrl:
                                      ImageUrlUtils.getResizedUrl(
                                          widget.images[index],
                                          width: 216,
                                          height: 144),
                                  fit: BoxFit.cover,
                                  memCacheWidth: 216,
                                  memCacheHeight: 144,
                                  cacheManager:
                                      BiliCacheManager.instance,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_selectedImageIndex + 1} / ${widget.images.length}',
                style: TextStyle(
                  color: AppColors.inactiveText,
                  fontSize: AppFonts.sizeSM,
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],

          Row(
            children: [
              _ActionButton(
                icon: Icons.comment_outlined,
                label: '评论 ${widget.commentText}',
                focusNode: _commentBtnFocusNode,
                autofocus: widget.images.isEmpty,
                onTap: () => setState(() => _showComments = true),
                onMoveUp: widget.images.length > 1
                    ? () => _getImageFocusNode(_selectedImageIndex)
                        .requestFocus()
                    : null,
                onMoveRight: () => _closeBtnFocusNode.requestFocus(),
              ),
              const SizedBox(width: 16),
              _ActionButton(
                icon: Icons.close,
                label: '返回',
                focusNode: _closeBtnFocusNode,
                onTap: () => Navigator.of(context).pop(),
                onMoveLeft: () => _commentBtnFocusNode.requestFocus(),
                onMoveUp: widget.images.length > 1
                    ? () => _getImageFocusNode(_selectedImageIndex)
                        .requestFocus()
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 共享组件 ──────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            color: AppColors.primaryText,
            fontSize: AppFonts.sizeXXL,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (widget.authorFace.isNotEmpty)
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: ImageUrlUtils.getResizedUrl(
                      widget.authorFace,
                      width: 48,
                      height: 48),
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  memCacheWidth: 48,
                  memCacheHeight: 48,
                  cacheManager: BiliCacheManager.instance,
                ),
              ),
            if (widget.authorFace.isNotEmpty) const SizedBox(width: 10),
            Text(
              widget.authorName,
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: AppFonts.sizeMD,
                fontWeight: AppFonts.semibold,
              ),
            ),
            if (widget.pubdate.isNotEmpty) ...[
              const SizedBox(width: 16),
              Text(
                widget.pubdate,
                style: TextStyle(
                  color: AppColors.inactiveText,
                  fontSize: AppFonts.sizeSM,
                ),
              ),
            ],
            const SizedBox(width: 20),
            Icon(Icons.favorite_outline,
                size: 14, color: AppColors.inactiveText),
            const SizedBox(width: 4),
            Text(
              widget.likeText,
              style: TextStyle(
                  color: AppColors.inactiveText, fontSize: AppFonts.sizeSM),
            ),
            const SizedBox(width: 16),
            Icon(Icons.chat_bubble_outline,
                size: 13, color: AppColors.inactiveText),
            const SizedBox(width: 4),
            Text(
              widget.commentText,
              style: TextStyle(
                  color: AppColors.inactiveText, fontSize: AppFonts.sizeSM),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentOverlay() {
    final screenSize = MediaQuery.of(context).size;
    final popupWidth = (screenSize.width * 0.78).clamp(900.0, 1500.0);
    final popupHeight = (screenSize.height * 0.82).clamp(560.0, 980.0);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _showComments = false),
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
              border: Border.all(
                  color: AppColors.navItemSelectedBackground, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: CommentListView(
              aid: widget.commentOid,
              commentType: widget.commentType,
              onClose: () => setState(() => _showComments = false),
            ),
          ),
        ),
      ],
    );
  }
}

/// 操作按钮（图文模式使用）
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final bool autofocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.focusNode,
    required this.onTap,
    this.autofocus = false,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: (node, event) {
        return TvKeyHandler.handleSinglePress(
          event,
          onSelect: onTap,
          onLeft: onMoveLeft,
          onRight: onMoveRight,
          onUp: onMoveUp,
          blockDown: true,
        );
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? SettingsService.themeColor
                        .withValues(alpha: AppColors.focusAlpha)
                    : AppColors.navItemSelectedBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 18,
                      color: focused
                          ? AppColors.primaryText
                          : AppColors.inactiveText),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: focused
                          ? AppColors.primaryText
                          : AppColors.inactiveText,
                      fontSize: AppFonts.sizeMD,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
