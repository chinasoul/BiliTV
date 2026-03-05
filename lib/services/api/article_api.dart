import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'base_api.dart';

/// 专栏文章 API
class ArticleApi {
  /// 获取专栏文章全文 HTML
  ///
  /// [cvid] 专栏文章 ID (cv号)
  /// 返回 HTML 字符串，失败返回空字符串
  ///
  /// 新版文章使用 opus 格式（结构化 paragraphs），旧版返回 HTML。
  /// 此方法统一返回 HTML 字符串。
  static Future<String> getArticleContent(int cvid) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/article/view',
      ).replace(queryParameters: {
        'id': cvid.toString(),
      });

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;

          // 优先使用 opus 格式（新版文章）
          final opus = data['opus'] as Map<String, dynamic>?;
          if (opus != null) {
            final html = _opusToHtml(opus);
            if (html.isNotEmpty) return html;
          }

          // 回退到旧版 HTML content
          return data['content'] as String? ?? '';
        }
      }
    } catch (e) {
      debugPrint('[ArticleApi] getArticleContent error: $e');
    }
    return '';
  }

  /// 将 opus 格式转换为 HTML
  ///
  /// opus.content.paragraphs 包含:
  ///   para_type=1: 文本段落 (text.nodes[].word.words)
  ///   para_type=2: 图片段落 (pic.pics[].url)
  static String _opusToHtml(Map<String, dynamic> opus) {
    final paragraphs = (opus['content'] as Map<String, dynamic>?)
            ?['paragraphs'] as List? ??
        [];

    if (paragraphs.isEmpty) return '';

    final sb = StringBuffer();

    for (final p in paragraphs) {
      final type = p['para_type'] as int? ?? 0;

      if (type == 1) {
        // 文本段落
        final nodes = (p['text'] as Map<String, dynamic>?)
                ?['nodes'] as List? ??
            [];
        if (nodes.isEmpty) continue;

        final format = p['format'] as Map<String, dynamic>?;
        final align = format?['align'] as int? ?? 0;
        final alignAttr = align == 1
            ? ' style="text-align:center"'
            : align == 2
                ? ' style="text-align:right"'
                : '';

        sb.write('<p$alignAttr>');
        for (final node in nodes) {
          final word = node['word'] as Map<String, dynamic>?;
          if (word == null) continue;
          final words = word['words'] as String? ?? '';
          if (words.isEmpty) continue;

          final fontLevel = word['font_level'] as String? ?? '';
          final style = word['style'] as Map<String, dynamic>?;
          final bold = style?['bold'] == true;

          final escaped = _escapeHtml(words);

          if (fontLevel == 'title' || fontLevel == 'heading') {
            sb.write('<strong>$escaped</strong>');
          } else if (bold) {
            sb.write('<b>$escaped</b>');
          } else {
            sb.write(escaped);
          }
        }
        sb.write('</p>');
      } else if (type == 2) {
        // 图片段落
        final pics = (p['pic'] as Map<String, dynamic>?)?['pics'] as List? ??
            [];
        for (final pic in pics) {
          var url = pic['url'] as String? ?? '';
          if (url.isEmpty) continue;
          url = url.replaceFirst('http://', 'https://');
          if (url.startsWith('//')) url = 'https:$url';
          final w = pic['width'] as num? ?? 0;
          final h = pic['height'] as num? ?? 0;

          // 对超大图片做 CDN 缩放
          if (w > 800) {
            url = '$url@800w.webp';
          }

          sb.write('<figure><img src="$url"');
          if (w > 0 && h > 0) {
            sb.write(' width="$w" height="$h"');
          }
          sb.write('></figure>');
        }
      }
    }

    return sb.toString();
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
