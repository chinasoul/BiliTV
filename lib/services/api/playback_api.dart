import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../../models/danmaku_item.dart';
import '../../models/subtitle_item.dart';
import '../auth_service.dart';
import '../codec_service.dart';
import '../settings_service.dart';

/// 播放相关 API (视频详情、播放地址、弹幕、进度上报)
class PlaybackApi {
  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _parseFrameRate(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final s = value.toString().trim();
    if (s.isEmpty) return 0;
    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 2) {
        final n = double.tryParse(parts[0]) ?? 0;
        final d = double.tryParse(parts[1]) ?? 1;
        if (d > 0) return n / d;
      }
    }
    return double.tryParse(s) ?? 0;
  }

  static String _toQueryString(Map<String, String> params) {
    return params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// 获取视频详情（包含分P信息和播放历史）
  static Future<Map<String, dynamic>?> getVideoInfo(String bvid) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url =
          'https://api.bilibili.com/x/web-interface/view?bvid=$bvid&_=$timestamp';
      final headers = BaseApi.getHeaders(withCookie: true);
      debugPrint(
        '🎬 [API] getVideoInfo headers: ${headers['Cookie'] != null ? 'Cookie present' : 'NO COOKIE'}',
      );

      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return json['data'];
        }
      }
    } catch (e) {
      // print('getVideoInfo error: $e');
    }
    return null;
  }

  /// 获取视频的 cid (用于播放和弹幕)
  static Future<int?> getVideoCid(String bvid) async {
    try {
      final url = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';

      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data']['cid'];
        }
      }
    } catch (e) {
      // print('getVideoCid error: $e');
    }
    return null;
  }

  static List<BiliSubtitleTrack> _parseSubtitleTracks(dynamic subtitleData) {
    if (subtitleData is! Map) return const [];
    final subtitles = subtitleData['subtitles'] ?? subtitleData['list'];
    if (subtitles is! List) return const [];
    return subtitles
        .whereType<Map>()
        .map((raw) => BiliSubtitleTrack.fromJson(Map<String, dynamic>.from(raw)))
        .where((e) => e.subtitleUrl.isNotEmpty)
        .toList();
  }

  static Future<BiliSubtitleTracksResult?> _fetchSubtitleTracksFromUrl(
    String url,
  ) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        ...BaseApi.getHeaders(withCookie: true),
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
      },
    );
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    if (json['code'] != 0 || json['data'] == null) return null;
    final data = json['data'] as Map<String, dynamic>;
    return BiliSubtitleTracksResult(
      tracks: _parseSubtitleTracks(data['subtitle']),
      needLoginSubtitle: data['need_login_subtitle'] == true,
    );
  }

  static Future<List<BiliSubtitleTrack>> _fetchSubtitleTracksFromView(
    String bvid,
    int cid,
  ) async {
    final url = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        ...BaseApi.getHeaders(withCookie: true),
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
      },
    );
    if (response.statusCode != 200) return const [];
    final json = jsonDecode(response.body);
    if (json['code'] != 0 || json['data'] == null) return const [];
    final data = json['data'] as Map<String, dynamic>;
    final viewCid = _toInt(data['cid']);
    // 仅在 cid 一致时使用 view 接口字幕，避免跨分P误取。
    if (viewCid > 0 && viewCid != cid) return const [];
    return _parseSubtitleTracks(data['subtitle']);
  }

  /// 获取字幕轨道列表（仅返回轨道）
  static Future<List<BiliSubtitleTrack>> getSubtitleTracks({
    required String bvid,
    required int cid,
    int? aid,
  }) async {
    final result = await getSubtitleTracksWithMeta(bvid: bvid, cid: cid, aid: aid);
    return result.tracks;
  }

  /// 获取字幕轨道列表（含是否需登录）
  static Future<BiliSubtitleTracksResult> getSubtitleTracksWithMeta({
    required String bvid,
    required int cid,
    int? aid,
  }) async {
    try {
      final aidQuery = aid != null ? '&aid=$aid' : '';
      final v2Url =
          'https://api.bilibili.com/x/player/v2?bvid=$bvid&cid=$cid$aidQuery';
      final primary = await _fetchSubtitleTracksFromUrl(v2Url);
      if (primary != null &&
          (primary.tracks.isNotEmpty || primary.needLoginSubtitle)) {
        return primary;
      }

      await BaseApi.ensureWbiKeys();
      final hasWbiKey =
          (BaseApi.imgKey?.isNotEmpty ?? false) &&
          (BaseApi.subKey?.isNotEmpty ?? false);
      if (!hasWbiKey) {
        return primary ??
            const BiliSubtitleTracksResult(
              tracks: [],
              needLoginSubtitle: false,
            );
      }

      final params = <String, String>{'bvid': bvid, 'cid': cid.toString()};
      if (aid != null) {
        params['aid'] = aid.toString();
      }
      final signedParams = SignUtils.signWithWbi(
        params,
        BaseApi.imgKey!,
        BaseApi.subKey!,
      );
      final wbiUrl =
          'https://api.bilibili.com/x/player/wbi/v2?${_toQueryString(signedParams)}';
      final fallback = await _fetchSubtitleTracksFromUrl(wbiUrl);
      if (fallback != null && fallback.tracks.isNotEmpty) return fallback;

      final viewTracks = await _fetchSubtitleTracksFromView(bvid, cid);
      if (viewTracks.isNotEmpty) {
        return BiliSubtitleTracksResult(
          tracks: viewTracks,
          needLoginSubtitle:
              fallback?.needLoginSubtitle ?? primary?.needLoginSubtitle ?? false,
        );
      }

      return fallback ??
          primary ??
          const BiliSubtitleTracksResult(
            tracks: [],
            needLoginSubtitle: false,
          );
    } catch (_) {
      return const BiliSubtitleTracksResult(
        tracks: [],
        needLoginSubtitle: false,
      );
    }
  }

  /// 下载并解析字幕 JSON
  static Future<List<BiliSubtitleItem>> getSubtitleItems(String subtitleUrl) async {
    if (subtitleUrl.isEmpty) return const [];
    try {
      final normalizedUrl = subtitleUrl.startsWith('//')
          ? 'https:$subtitleUrl'
          : subtitleUrl.startsWith('/')
          ? 'https://api.bilibili.com$subtitleUrl'
          : subtitleUrl;
      final response = await http.get(
        Uri.parse(normalizedUrl),
        headers: {
          ...BaseApi.getHeaders(withCookie: true),
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
        },
      );
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(response.body);
      final body = json['body'];
      if (body is! List) return const [];
      final items = body
          .whereType<Map>()
          .map((raw) => BiliSubtitleItem.fromJson(Map<String, dynamic>.from(raw)))
          .where((e) => e.content.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => a.from.compareTo(b.from));
      return items;
    } catch (_) {
      return const [];
    }
  }

  /// 获取视频播放地址
  /// 返回 {'url': String, 'audioUrl': String?, 'qualities': List<Map>, 'currentQuality': int, 'isDash': bool}
  /// [forceCodec] 强制指定编码器 (用于失败重试)
  static Future<Map<String, dynamic>?> getVideoPlayUrl({
    required String bvid,
    required int cid,
    int qn = 80,
    VideoCodec? forceCodec,
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      final params = {
        'bvid': bvid,
        'cid': cid.toString(),
        'qn': qn.toString(),
        'fnval': '4048', // 请求 DASH + HEVC + AV1 + HDR 等全格式
        'fnver': '0',
        'fourk': '1',
      };

      final hasWbiKey =
          (BaseApi.imgKey?.isNotEmpty ?? false) &&
          (BaseApi.subKey?.isNotEmpty ?? false);
      final queryParams = hasWbiKey
          ? SignUtils.signWithWbi(params, BaseApi.imgKey!, BaseApi.subKey!)
          : params;
      final url =
          'https://api.bilibili.com/x/player/playurl?${_toQueryString(queryParams)}';

      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];

          final qualities = <Map<String, dynamic>>[];
          final acceptQuality = data['accept_quality'] as List? ?? [];
          final acceptDesc = data['accept_description'] as List? ?? [];
          for (int i = 0; i < acceptQuality.length; i++) {
            qualities.add({
              'qn': acceptQuality[i],
              'desc': i < acceptDesc.length
                  ? acceptDesc[i]
                  : '${acceptQuality[i]}P',
            });
          }

          String? videoUrl;
          String? audioUrl;
          bool isDash = false;

          if (data['dash'] != null) {
            isDash = true;
            final dash = data['dash'];
            final videos = dash['video'] as List? ?? [];
            final audios = dash['audio'] as List? ?? [];

            if (videos.isNotEmpty) {
              final videosByQuality = <int, List<dynamic>>{};
              for (final v in videos) {
                final id = v['id'] as int? ?? 0;
                videosByQuality.putIfAbsent(id, () => []).add(v);
              }

              final targetQn = qn;
              var candidateVideos = videosByQuality[targetQn];
              if (candidateVideos == null || candidateVideos.isEmpty) {
                final sortedQualities = videosByQuality.keys.toList()
                  ..sort(
                    (a, b) =>
                        (b - targetQn).abs().compareTo((a - targetQn).abs()),
                  );
                if (sortedQualities.isNotEmpty) {
                  candidateVideos = videosByQuality[sortedQualities.first];
                }
              }
              candidateVideos ??= videos;

              dynamic selectedVideo;

              // 获取硬件解码器支持列表
              final hwDecoders = await CodecService.getHardwareDecoders();
              final hasAv1Hw = hwDecoders.contains('av1');
              final hasHevcHw = hwDecoders.contains('hevc');
              final hasAvcHw = hwDecoders.contains('avc');

              // 1. 如果指定了 forceCodec（失败回退时），优先使用
              if (forceCodec != null && forceCodec != VideoCodec.auto) {
                selectedVideo = candidateVideos.firstWhere((v) {
                  final codecs = v['codecs'] as String? ?? '';
                  return codecs.startsWith(forceCodec.prefix);
                }, orElse: () => null);
              }

              // 2. 首次尝试（forceCodec==null），使用用户设置
              if (selectedVideo == null && forceCodec == null) {
                final userCodec = SettingsService.preferredCodec;

                if (userCodec != VideoCodec.auto) {
                  // 用户指定了具体编码器
                  selectedVideo = candidateVideos.firstWhere((v) {
                    final codecs = v['codecs'] as String? ?? '';
                    return codecs.startsWith(userCodec.prefix);
                  }, orElse: () => null);
                } else {
                  // 用户设置是"自动"，智能选硬解最优: AV1 > HEVC > AVC
                  if (hasAv1Hw) {
                    selectedVideo = candidateVideos.firstWhere((v) {
                      final codecs = v['codecs'] as String? ?? '';
                      return codecs.startsWith('av01');
                    }, orElse: () => null);
                  }

                  if (selectedVideo == null && hasHevcHw) {
                    selectedVideo = candidateVideos.firstWhere((v) {
                      final codecs = v['codecs'] as String? ?? '';
                      return codecs.startsWith('hev') ||
                          codecs.startsWith('hvc');
                    }, orElse: () => null);
                  }

                  if (selectedVideo == null && hasAvcHw) {
                    selectedVideo = candidateVideos.firstWhere((v) {
                      final codecs = v['codecs'] as String? ?? '';
                      return codecs.startsWith('avc');
                    }, orElse: () => null);
                  }
                }
              }

              // 3. 兜底：确保有视频（可能会用软解）
              selectedVideo ??= candidateVideos.first;

              videoUrl = selectedVideo['baseUrl'] ?? selectedVideo['base_url'];
              final selectedCodec = selectedVideo['codecs'] as String? ?? '';

              if (audios.isNotEmpty) {
                var sortedAudios = List.from(audios);
                sortedAudios.sort(
                  (a, b) =>
                      (b['bandwidth'] ?? 0).compareTo(a['bandwidth'] ?? 0),
                );
                audioUrl =
                    sortedAudios.first['baseUrl'] ??
                    sortedAudios.first['base_url'];
              }

              if (videoUrl != null) {
                final width = _toInt(selectedVideo['width']);
                final height = _toInt(selectedVideo['height']);
                final videoBandwidth = _toInt(
                  selectedVideo['bandwidth'],
                ); // bps
                final frameRate = _parseFrameRate(
                  selectedVideo['frameRate'] ?? selectedVideo['frame_rate'],
                );
                return {
                  'url': videoUrl,
                  'audioUrl': audioUrl,
                  'qualities': qualities,
                  'currentQuality': data['quality'] ?? qn,
                  'isDash': isDash,
                  'codec': selectedCodec,
                  'width': width,
                  'height': height,
                  'frameRate': frameRate,
                  'videoBandwidth': videoBandwidth,
                  'dashData': data['dash'],
                };
              }
            }
          } else if (data['durl'] != null) {
            final durls = data['durl'] as List;
            if (durls.isNotEmpty) {
              videoUrl = durls[0]['url'];
            }
          }
        } else {
          // API 返回错误码
          throw Exception(
            'API错误: ${json['code']} - ${json['message'] ?? '未知错误'}',
          );
        }
      } else {
        // HTTP 错误
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      // 返回错误信息而不是 null
      return {'error': e.toString()};
    }
    return null;
  }

  /// 兼容性兜底: 用 fnval=1 请求非 DASH 格式 (durl/mp4/flv)
  /// 部分设备的 MediaCodecVideoRenderer 在 DASH 流上崩溃，此方法绕过 DASH。
  static Future<Map<String, dynamic>?> getVideoPlayUrlCompat({
    required String bvid,
    required int cid,
    int qn = 32,
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      final params = {
        'bvid': bvid,
        'cid': cid.toString(),
        'qn': qn.toString(),
        'fnval': '1', // 不请求 DASH，只要 durl(mp4/flv)
        'fnver': '0',
        'fourk': '0',
      };

      final hasWbiKey =
          (BaseApi.imgKey?.isNotEmpty ?? false) &&
          (BaseApi.subKey?.isNotEmpty ?? false);
      final queryParams = hasWbiKey
          ? SignUtils.signWithWbi(params, BaseApi.imgKey!, BaseApi.subKey!)
          : params;
      final endpoint = hasWbiKey
          ? 'https://api.bilibili.com/x/player/wbi/playurl'
          : 'https://api.bilibili.com/x/player/playurl';
      final queryString = _toQueryString(queryParams);

      final response = await http.get(
        Uri.parse('$endpoint?$queryString'),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          final data = json['data'];
          final durls = data['durl'] as List? ?? [];
          if (durls.isNotEmpty) {
            final url = durls.first['url'] as String?;
            if (url != null && url.isNotEmpty) {
              // 提取画质列表
              final qualities = <Map<String, dynamic>>[];
              final acceptQuality = data['accept_quality'] as List? ?? [];
              final acceptDesc = data['accept_description'] as List? ?? [];
              for (int i = 0; i < acceptQuality.length; i++) {
                qualities.add({
                  'qn': acceptQuality[i],
                  'desc': i < acceptDesc.length ? acceptDesc[i] : '',
                });
              }

              return {
                'url': url,
                'audioUrl': null,
                'qualities': qualities,
                'currentQuality': data['quality'] ?? qn,
                'isDash': false,
                'codec': 'avc_compat',
                'width': 0,
                'height': 0,
                'frameRate': 0.0,
                'videoBandwidth': 0,
                'dashData': null,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('getVideoPlayUrlCompat error: $e');
    }
    return null;
  }

  /// 获取弹幕数据 (XML 格式，支持 deflate/gzip/raw)
  static Future<List<BiliDanmakuItem>> getDanmaku(int cid) async {
    try {
      final url = 'https://comment.bilibili.com/$cid.xml';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Accept-Encoding': 'gzip, deflate',
        },
      );

      if (response.statusCode == 200) {
        String xmlString;
        final bytes = response.bodyBytes;

        if (bytes.isEmpty) return [];

        try {
          if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
            final decompressed = gzip.decode(bytes);
            xmlString = utf8.decode(decompressed);
          } else if (bytes.length >= 2 && bytes[0] == 0x78) {
            final decompressed = zlib.decode(bytes);
            xmlString = utf8.decode(decompressed);
          } else if (bytes.isNotEmpty && bytes[0] == 0x3c) {
            xmlString = utf8.decode(bytes);
          } else {
            final decompressed = ZLibDecoder(raw: true).convert(bytes);
            xmlString = utf8.decode(decompressed);
          }
        } catch (e) {
          xmlString = utf8.decode(bytes, allowMalformed: true);
        }

        final danmakuList = <BiliDanmakuItem>[];

        final regex = RegExp(r'<d p="([^"]+)">([^<]*)</d>');
        for (final match in regex.allMatches(xmlString)) {
          final pAttr = match.group(1)!;
          final content = match.group(2)!;

          final parts = pAttr.split(',');
          if (parts.length >= 4) {
            danmakuList.add(
              BiliDanmakuItem(
                time: double.tryParse(parts[0]) ?? 0.0,
                type: int.tryParse(parts[1]) ?? 1,
                fontSize: double.tryParse(parts[2]) ?? 25.0,
                color: int.tryParse(parts[3]) ?? 0xFFFFFF,
                content: content,
              ),
            );
          }
        }

        return danmakuList;
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 上报播放进度 (Heartbeat)
  static Future<bool> reportProgress({
    required String bvid,
    required int cid,
    required int progress,
  }) async {
    if (!AuthService.isLoggedIn) return false;

    try {
      final startTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final queryParams = {
        'bvid': bvid,
        'cid': cid.toString(),
        'played_time': progress.toString(),
        'real_played_time': progress.toString(),
        'start_ts': startTs.toString(),
        'csrf': AuthService.biliJct ?? '',
      };

      final queryString = queryParams.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final url =
          'https://api.bilibili.com/x/click-interface/web/heartbeat?$queryString';

      final response = await http.post(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return true;
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return false;
  }

  /// 获取视频在线观看人数
  /// 返回 { 'total': 总人数字符串, 'count': 本视频在线人数字符串 }
  static Future<Map<String, String>?> getOnlineCount({
    required int aid,
    required int cid,
  }) async {
    try {
      final url =
          'https://api.bilibili.com/x/player/online/total?aid=$aid&cid=$cid';
      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          return {'total': data['total'] ?? '', 'count': data['count'] ?? ''};
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }
}
