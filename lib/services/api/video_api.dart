import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../auth_service.dart';
import '../../models/favorite_folder.dart';
import '../../models/video.dart';

/// 视频列表和搜索相关 API
class VideoApi {
  /// 获取热门视频 (无需登录)
  static Future<List<Video>> getPopularVideos({int page = 1}) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/popular',
      ).replace(queryParameters: {'pn': page.toString(), 'ps': '20'});

      final response = await http.get(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List? ?? [];
          return list.map((item) => Video.fromRecommend(item)).toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 获取推荐视频 (需要 WBI 签名)
  static Future<List<Video>> getRecommendVideos({int idx = 0}) async {
    try {
      await BaseApi.ensureWbiKeys();

      Map<String, String> params = {
        'fresh_idx': idx.toString(),
        'fresh_type': '4',
        'ps': '20',
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/wbi/index/top/feed/rcmd',
      ).replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final items = json['data']['item'] as List? ?? [];
          return items
              .where((item) => item['bvid'] != null)
              .map((item) => Video.fromRecommend(item))
              .toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 获取分区视频 (按 tid)
  static Future<List<Video>> getRegionVideos({
    required int tid,
    int page = 1,
  }) async {
    try {
      final uri = Uri.parse('${BaseApi.apiBase}/x/web-interface/dynamic/region')
          .replace(
            queryParameters: {
              'rid': tid.toString(),
              'pn': page.toString(),
              'ps': '20',
            },
          );

      final response = await http.get(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final archives = json['data']['archives'] as List? ?? [];
          return archives.map((item) => Video.fromRecommend(item)).toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 获取观看历史 (需要登录)
  /// 返回 { 'list': List<Video>, 'viewAt': int, 'max': int, 'hasMore': bool }
  static Future<Map<String, dynamic>> getHistory({
    int ps = 30,
    int viewAt = 0,
    int max = 0,
  }) async {
    if (!AuthService.isLoggedIn) {
      return {'list': <Video>[], 'hasMore': false};
    }

    try {
      final params = {'ps': ps.toString()};
      if (viewAt > 0) params['view_at'] = viewAt.toString();
      if (max > 0) params['max'] = max.toString();

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/history/cursor',
      ).replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final listData = json['data']['list'] as List? ?? [];
          final list = listData.map((item) => Video.fromHistory(item)).toList();

          final cursor = json['data']['cursor'];
          int nextViewAt = 0;
          int nextMax = 0;
          bool hasMore = false;

          if (cursor != null) {
            nextViewAt = cursor['view_at'] ?? 0;
            nextMax = cursor['max'] ?? 0;
            hasMore = list.isNotEmpty;
          }

          return {
            'list': list,
            'viewAt': nextViewAt,
            'max': nextMax,
            'hasMore': hasMore,
          };
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return {'list': <Video>[], 'hasMore': false};
  }

  /// 获取收藏夹列表
  static Future<List<FavoriteFolder>> getFavoriteFolders() async {
    if (!AuthService.isLoggedIn) return [];
    try {
      final mid = AuthService.mid;
      if (mid == null || mid == 0) return [];

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v3/fav/folder/created/list-all',
      ).replace(queryParameters: {'up_mid': mid.toString()});

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List? ?? [];
          return list
              .whereType<Map<String, dynamic>>()
              .map(FavoriteFolder.fromJson)
              .toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 获取收藏夹视频
  /// 返回 { 'list': List<Video>, 'hasMore': bool }
  static Future<Map<String, dynamic>> getFavoriteFolderVideos({
    required int mediaId,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (!AuthService.isLoggedIn || mediaId <= 0) {
      return {'list': <Video>[], 'hasMore': false};
    }

    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v3/fav/resource/list',
      ).replace(
        queryParameters: {
          'media_id': mediaId.toString(),
          'pn': page.toString(),
          'ps': pageSize.toString(),
          'order': 'mtime', // 最近收藏优先
          'type': '0',
          'tid': '0',
          'platform': 'web',
        },
      );

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final info = json['data']['info'] as Map<String, dynamic>? ?? {};
          final medias = json['data']['medias'] as List? ?? [];
          final list = medias
              .whereType<Map<String, dynamic>>()
              .map(_videoFromFavoriteMedia)
              .where((v) => v.bvid.isNotEmpty)
              .toList();
          final mediaCount = BaseApi.toInt(info['media_count']);
          final hasMore = page * pageSize < mediaCount;
          return {'list': list, 'hasMore': hasMore};
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return {'list': <Video>[], 'hasMore': false};
  }

  /// 获取稍后再看列表
  static Future<List<Video>> getWatchLaterVideos() async {
    if (!AuthService.isLoggedIn) return [];
    try {
      final uri = Uri.parse('${BaseApi.apiBase}/x/v2/history/toview/web');
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List? ?? [];
          return list
              .whereType<Map<String, dynamic>>()
              .map(_videoFromWatchLaterItem)
              .where((v) => v.bvid.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 获取搜索建议
  static Future<List<String>> getSearchSuggestions(String keyword) async {
    if (keyword.isEmpty) return [];

    try {
      final uri = Uri.parse('https://s.search.bilibili.com/main/suggest')
          .replace(
            queryParameters: {
              'term': keyword,
              'main_ver': 'v1',
              'highlight': '',
            },
          );

      final response = await http.get(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json['code'] == 0 && json['result'] != null) {
          final tags = json['result']['tag'] as List? ?? [];
          return tags
              .map((tag) => tag['value'] as String? ?? '')
              .where((v) => v.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  static Video _videoFromFavoriteMedia(Map<String, dynamic> item) {
    final upper = item['upper'] as Map<String, dynamic>? ?? {};
    final cnt = item['cnt_info'] as Map<String, dynamic>? ?? {};
    return Video(
      bvid: (item['bvid'] ?? '').toString(),
      title: (item['title'] ?? '').toString(),
      pic: BaseApi.fixPicUrl((item['cover'] ?? '').toString()),
      ownerName: (upper['name'] ?? '').toString(),
      ownerFace: BaseApi.fixPicUrl((upper['face'] ?? '').toString()),
      ownerMid: BaseApi.toInt(upper['mid']),
      view: BaseApi.toInt(cnt['play']),
      danmaku: BaseApi.toInt(cnt['danmaku']),
      duration: BaseApi.toInt(item['duration']),
      pubdate: BaseApi.toInt(item['pubtime']),
      badge: (item['badge'] ?? '').toString(),
    );
  }

  static Video _videoFromWatchLaterItem(Map<String, dynamic> item) {
    final owner = item['owner'] as Map<String, dynamic>? ?? {};
    final stat = item['stat'] as Map<String, dynamic>? ?? {};
    return Video(
      bvid: (item['bvid'] ?? '').toString(),
      title: (item['title'] ?? '').toString(),
      pic: BaseApi.fixPicUrl((item['pic'] ?? '').toString()),
      ownerName: (owner['name'] ?? '').toString(),
      ownerFace: BaseApi.fixPicUrl((owner['face'] ?? '').toString()),
      ownerMid: BaseApi.toInt(owner['mid']),
      view: BaseApi.toInt(stat['view']),
      danmaku: BaseApi.toInt(stat['danmaku']),
      duration: BaseApi.toInt(item['duration']),
      pubdate: BaseApi.toInt(item['pubdate']),
      badge: (item['badge'] ?? '').toString(),
    );
  }

  /// 搜索视频 (需要 WBI 签名)
  static Future<List<Video>> searchVideos(
    String keyword, {
    int page = 1,
    String order = 'totalrank',
  }) async {
    if (keyword.isEmpty) return [];

    try {
      await BaseApi.ensureWbiKeys();

      Map<String, String> params = {
        'keyword': keyword,
        'search_type': 'video',
        'page': page.toString(),
        'pagesize': '20',
        'order': order,
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/wbi/search/type',
      ).replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final result = json['data']['result'] as List? ?? [];
          return result.map((item) => Video.fromSearch(item)).toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 获取动态视频列表
  static Future<DynamicFeed> getDynamicFeed({String offset = ''}) async {
    try {
      await BaseApi.ensureWbiKeys();

      final response = await http.get(
        Uri.parse(
          '${BaseApi.apiBase}/x/polymer/web-dynamic/v1/feed/all?type=all&offset=$offset',
        ),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          final items = data['items'] as List? ?? [];
          final newOffset = data['offset'] as String? ?? '';
          final hasMore = data['has_more'] as bool? ?? false;

          final videos = <Video>[];

          for (final item in items) {
            try {
              if (item['visible'] != true) continue;

              final modules = item['modules'] as Map<String, dynamic>? ?? {};
              final dynamicModule =
                  modules['module_dynamic'] as Map<String, dynamic>? ?? {};
              final major =
                  dynamicModule['major'] as Map<String, dynamic>? ?? {};

              if (major['type'] != 'MAJOR_TYPE_ARCHIVE') continue;

              final archive = major['archive'] as Map<String, dynamic>? ?? {};
              final author =
                  modules['module_author'] as Map<String, dynamic>? ?? {};
              final stat = archive['stat'] as Map<String, dynamic>? ?? {};

              final viewValue = stat['play'] ?? stat['view'] ?? 0;
              final danmakuValue = stat['danmaku'] ?? 0;

              videos.add(
                Video(
                  bvid: archive['bvid'] ?? '',
                  title: archive['title'] ?? '',
                  pic: BaseApi.fixPicUrl(archive['cover'] ?? ''),
                  ownerName: author['name'] ?? '',
                  ownerFace: BaseApi.fixPicUrl(author['face'] ?? ''),
                  ownerMid: author['mid'] ?? 0,
                  view: BaseApi.toInt(viewValue),
                  danmaku: BaseApi.toInt(danmakuValue),
                  duration: BaseApi.parseDuration(
                    archive['duration_text'] ?? '',
                  ),
                  pubdate: author['pub_ts'] ?? 0,
                  badge:
                      (archive['badge'] as Map<String, dynamic>?)?['text'] ??
                      '',
                ),
              );
            } catch (e) {
              continue;
            }
          }

          return DynamicFeed(
            videos: videos,
            offset: newOffset,
            hasMore: hasMore,
          );
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return DynamicFeed(videos: [], offset: '', hasMore: false);
  }

  /// 获取相关视频
  static Future<List<Video>> getRelatedVideos(String bvid) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/archive/related',
      ).replace(queryParameters: {'bvid': bvid});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data'] as List? ?? [];
          return list.map((item) => Video.fromRecommend(item)).toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 获取 UP主 投稿视频列表 (需要 WBI 签名)
  static Future<List<Video>> getSpaceVideos({
    required int mid,
    int page = 1,
    String order = 'pubdate',
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      Map<String, String> params = {
        'mid': mid.toString(),
        'pn': page.toString(),
        'ps': '30',
        'order': order,
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/space/wbi/arc/search',
      ).replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list']?['vlist'] as List? ?? [];
          return list.map((item) => Video.fromSpaceVideo(item)).toList();
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }
}

/// 动态 Feed 数据结构
class DynamicFeed {
  final List<Video> videos;
  final String offset;
  final bool hasMore;

  DynamicFeed({
    required this.videos,
    required this.offset,
    required this.hasMore,
  });
}
