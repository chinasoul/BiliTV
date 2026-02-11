import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../auth_service.dart';
import '../../models/following_user.dart';

/// 用户互动相关 API (点赞/投币/收藏/关注)
class InteractionApi {
  /// 点赞/取消点赞
  static Future<bool> likeVideo({required int aid, required bool like}) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return false;

      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/web-interface/archive/like'),
        headers: {
          ...BaseApi.getHeaders(withCookie: true),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'aid=$aid&like=${like ? 1 : 2}&csrf=$csrf',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0;
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 检查是否已点赞
  static Future<bool> checkLikeStatus(int aid) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/archive/has/like',
      ).replace(queryParameters: {'aid': aid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0 && json['data'] == 1;
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 投币 (APP接口，需签名)
  static Future<String?> coinVideo({required int aid, int count = 1}) async {
    if (!AuthService.isLoggedIn) return '请先登录';
    try {
      final accessKey = AuthService.accessToken;
      if (accessKey == null || accessKey.isEmpty) {
        return 'Access Token 为空';
      }

      final params = {
        'access_key': accessKey,
        'aid': aid.toString(),
        'multiply': count.toString(),
        'select_like': '0',
      };

      final signedParams = SignUtils.signForTvLogin(params);

      final queryString = signedParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final uri = Uri.parse('https://app.bilibili.com/x/v2/view/coin/add');

      final response = await http.post(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: queryString,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return null; // 成功
        } else {
          return json['message'] ?? '投币失败 (${json['code']})';
        }
      }
      return 'HTTP ${response.statusCode}';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  /// 检查已投币数
  static Future<int> checkCoinStatus(int aid) async {
    if (!AuthService.isLoggedIn) return 0;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/archive/coins',
      ).replace(queryParameters: {'aid': aid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data']['multiply'] ?? 0;
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return 0;
  }

  /// 收藏/取消收藏
  static Future<bool> favoriteVideo({
    required int aid,
    required bool favorite,
  }) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return false;

      final folderId = await _getDefaultFolderId();
      if (folderId == null) return false;

      final addIds = favorite ? folderId.toString() : '';
      final delIds = favorite ? '' : folderId.toString();

      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/v3/fav/resource/deal'),
        headers: {
          ...BaseApi.getHeaders(withCookie: true),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body:
            'rid=$aid&type=2&add_media_ids=$addIds&del_media_ids=$delIds&csrf=$csrf',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0;
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 获取默认收藏夹 ID
  static Future<int?> _getDefaultFolderId() async {
    try {
      final mid = AuthService.mid;
      if (mid == null) return null;

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
          final list = json['data']['list'] as List?;
          if (list != null && list.isNotEmpty) {
            return list[0]['id'];
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }

  /// 检查是否已收藏
  static Future<bool> checkFavoriteStatus(int aid) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v2/fav/video/favoured',
      ).replace(queryParameters: {'aid': aid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data']['favoured'] == true;
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 关注/取消关注 UP主
  static Future<bool> followUser({
    required int mid,
    required bool follow,
  }) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return false;

      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/relation/modify'),
        headers: {
          ...BaseApi.getHeaders(withCookie: true),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'fid=$mid&act=${follow ? 1 : 2}&csrf=$csrf',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0;
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 检查是否已关注
  static Future<bool> checkFollowStatus(int mid) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/relation',
      ).replace(queryParameters: {'fid': mid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final attribute = json['data']['attribute'] ?? 0;
          return attribute == 2 || attribute == 6;
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 获取关注列表
  /// 返回 { 'list': List<FollowingUser>, 'hasMore': bool }
  static Future<Map<String, dynamic>> getFollowingUsers({
    int page = 1,
    int pageSize = 30,
  }) async {
    if (!AuthService.isLoggedIn) {
      return {'list': <FollowingUser>[], 'hasMore': false};
    }

    try {
      final mid = AuthService.mid;
      if (mid == null || mid == 0) {
        return {'list': <FollowingUser>[], 'hasMore': false};
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/relation/followings',
      ).replace(
        queryParameters: {
          'vmid': mid.toString(),
          'pn': page.toString(),
          'ps': pageSize.toString(),
          'order': 'desc',
          'order_type': 'attention',
        },
      );

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          final listData = data['list'] as List? ?? [];
          final total = _toInt(data['total']);
          final list = listData
              .whereType<Map<String, dynamic>>()
              .map(FollowingUser.fromJson)
              .toList();
          final hasMore = page * pageSize < total;
          return {'list': list, 'hasMore': hasMore};
        }
      }
    } catch (e) {
      // 忽略错误
    }

    return {'list': <FollowingUser>[], 'hasMore': false};
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
