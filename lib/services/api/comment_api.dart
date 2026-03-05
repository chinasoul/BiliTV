import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../../models/comment.dart';

/// 评论区 API 返回结果
class CommentResult {
  final List<Comment> comments;
  final int totalCount; // 评论总数
  final String? nextOffset; // 下一页偏移 (pagination_str)
  final bool hasMore;

  CommentResult({
    required this.comments,
    this.totalCount = 0,
    this.nextOffset,
    this.hasMore = false,
  });
}

/// 评论相关 API
class CommentApi {
  /// 获取评论 (主楼)
  ///
  /// [oid] 资源 ID (视频=aid, 专栏=cvid, 图文=动态id)
  /// [type] 评论区类型: 1=视频, 11=图文动态, 12=专栏
  /// [mode] 排序: 2=按时间, 3=按热度
  /// [nextOffset] 翻页偏移 (首页传 null)
  static Future<CommentResult> getComments({
    required int oid,
    int type = 1,
    int mode = 3,
    String? nextOffset,
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      final paginationStr = nextOffset ??
          jsonEncode({
            "offset": "",
          });

      Map<String, String> params = {
        'oid': oid.toString(),
        'type': type.toString(),
        'mode': mode.toString(),
        'pagination_str': paginationStr,
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v2/reply/wbi/main',
      ).replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          final cursor = data['cursor'] as Map<String, dynamic>? ?? {};
          final repliesJson = data['replies'] as List? ?? [];
          final topReplies = data['top_replies'] as List? ?? [];

          final comments = <Comment>[];

          // 首页加入置顶评论
          if (nextOffset == null) {
            for (final item in topReplies) {
              comments.add(Comment.fromJson(item));
            }
          }

          // 普通评论 (去掉和置顶重复的)
          final topIds =
              comments.map((c) => c.rpid).toSet();
          for (final item in repliesJson) {
            final comment = Comment.fromJson(item);
            if (!topIds.contains(comment.rpid)) {
              comments.add(comment);
            }
          }

          // 下一页偏移
          final paginationReply =
              data['cursor']?['pagination_reply'] as Map<String, dynamic>?;
          String? nextOff;
          if (paginationReply != null &&
              paginationReply['next_offset'] != null) {
            nextOff = jsonEncode({
              "offset": paginationReply['next_offset'].toString(),
            });
          }

          return CommentResult(
            comments: comments,
            totalCount: cursor['all_count'] as int? ?? 0,
            nextOffset: nextOff,
            hasMore: !(cursor['is_end'] as bool? ?? true),
          );
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return CommentResult(comments: []);
  }

  /// 获取评论回复 (楼中楼)
  ///
  /// [oid] 资源 ID
  /// [type] 评论区类型: 1=视频, 11=图文动态, 12=专栏
  /// [root] 根评论 rpid
  /// [page] 页码 (从1开始)
  static Future<List<Comment>> getReplies({
    required int oid,
    int type = 1,
    required int root,
    int page = 1,
  }) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v2/reply/reply',
      ).replace(queryParameters: {
        'oid': oid.toString(),
        'type': type.toString(),
        'root': root.toString(),
        'pn': page.toString(),
        'ps': '10',
      });

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final repliesJson = json['data']['replies'] as List? ?? [];
          return repliesJson
              .map((e) => Comment.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }
}
