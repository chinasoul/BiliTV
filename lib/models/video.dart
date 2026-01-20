/// 视频数据模型
class Video {
  final String bvid;
  final String title;
  final String pic; // 封面图 URL
  final String ownerName;
  final String ownerFace;
  final int ownerMid;
  final int view; // 播放量
  final int danmaku; // 弹幕数
  final int duration; // 时长(秒)
  final int pubdate; // 发布时间戳
  final int progress; // 观看进度(秒), -1表示未观看
  final int viewAt; // 最后观看时间戳
  final int cid; // 历史记录中的 CID
  final int historyPage; // 历史记录中的分P序号 (如 1)
  final String historyPart; // 历史记录中的分P标题 (如 "第一话")
  final int historyVideos; // 历史记录中的总分P数 (多P视频 > 1)
  final String badge; // 角标 (如 "付费", "充电专属")
  final bool isLive; // 是否是直播

  Video({
    required this.bvid,
    required this.title,
    required this.pic,
    this.ownerName = '',
    this.ownerFace = '',
    this.ownerMid = 0,
    this.view = 0,
    this.danmaku = 0,
    this.duration = 0,
    this.pubdate = 0,
    this.progress = -1,
    this.viewAt = 0,
    this.cid = 0,
    this.historyPage = 0,
    this.historyPart = '',
    this.historyVideos = 0,
    String badge = '',
    this.isLive = false,
  }) : badge = _filterBadge(badge);

  static String _filterBadge(String badge) {
    if (badge == '投稿视频' || badge == '投稿') return '';
    return badge;
  }

  /// 从推荐/热门 API 响应解析
  factory Video.fromRecommend(Map<String, dynamic> json) {
    final owner = json['owner'] as Map<String, dynamic>? ?? {};
    final stat = json['stat'] as Map<String, dynamic>? ?? {};

    return Video(
      bvid: json['bvid'] ?? '',
      title: json['title'] ?? '',
      pic: _fixPicUrl(json['pic'] ?? ''),
      ownerName: owner['name'] ?? '',
      ownerFace: _fixPicUrl(owner['face'] ?? ''),
      ownerMid: owner['mid'] ?? 0,
      view: _toInt(stat['view']),
      danmaku: _toInt(stat['danmaku']),
      duration: json['duration'] ?? 0,
      pubdate: json['pubdate'] ?? 0,
      // 推荐流中可能有 badge 信息，如 "充电专属"
      badge: json['badge'] ?? '',
    );
  }

  /// 从历史记录 API 响应解析
  factory Video.fromHistory(Map<String, dynamic> json) {
    final history = json['history'] as Map<String, dynamic>? ?? {};

    // 封面优先使用 cover，其次 pic
    String cover = json['cover'] ?? '';
    if (cover.isEmpty) cover = json['pic'] ?? '';

    final videos = json['videos'] ?? 0;
    final duration = json['duration'] ?? 0;

    return Video(
      bvid: history['bvid'] ?? '',
      title: json['title'] ?? '',
      pic: _fixPicUrl(cover),
      ownerName: json['author_name'] ?? '',
      ownerFace: _fixPicUrl(json['author_face'] ?? ''),
      ownerMid: json['author_mid'] ?? 0,
      view: _toInt(json['stat']?['view']),
      danmaku: _toInt(json['stat']?['danmaku']),
      duration: duration,
      progress: json['progress'] ?? -1,
      viewAt: json['view_at'] ?? 0,
      cid: (history['cid'] != null && history['cid'] != 0)
          ? history['cid']
          : (history['oid'] ?? 0),
      historyPage: history['page'] ?? 0,
      historyPart: history['part'] ?? '',
      historyVideos: videos, // 分P总数 (多P > 1)
      badge: json['badge'] ?? '',
      // live_status: 0:未直播, 1:直播中
      isLive:
          (json['live_status'] ?? 0) == 1 ||
          (json['badge'] ?? '').toString().contains('直播') ||
          (json['badge'] == '未开播'),
    );
  }

  /// 从搜索结果解析
  factory Video.fromSearch(Map<String, dynamic> json) {
    // 搜索结果的标题可能包含 <em> 高亮标签，需要清理
    String title = json['title'] ?? '';
    title = title.replaceAll(RegExp(r'<[^>]*>'), '');

    return Video(
      bvid: json['bvid'] ?? '',
      title: title,
      pic: _fixPicUrl(json['pic'] ?? ''),
      ownerName: json['author'] ?? '',
      view: _toInt(json['play']),
      danmaku: _toInt(json['danmaku']),
      duration: _parseDuration(json['duration'] ?? ''),
      pubdate: json['pubdate'] ?? 0,
      badge: json['badge'] ?? '',
    );
  }

  /// 从 UP主空间视频列表解析
  factory Video.fromSpaceVideo(Map<String, dynamic> json) {
    return Video(
      bvid: json['bvid'] ?? '',
      title: json['title'] ?? '',
      pic: _fixPicUrl(json['pic'] ?? ''),
      ownerName: json['author'] ?? '',
      ownerMid: _toInt(json['mid']),
      view: _toInt(json['play']),
      danmaku: _toInt(json['video_review']),
      duration: _parseDuration(json['length'] ?? ''),
      pubdate: json['created'] ?? 0,
      badge: json['badge'] ?? '',
    );
  }

  /// 格式化播放量
  String get viewFormatted {
    if (view >= 100000000) return '${(view / 100000000).toStringAsFixed(1)}亿';
    if (view >= 10000) return '${(view / 10000).toStringAsFixed(1)}万';
    return view.toString();
  }

  /// 格式化弹幕数
  String get danmakuFormatted {
    if (danmaku >= 100000000) {
      return '${(danmaku / 100000000).toStringAsFixed(1)}亿';
    }
    if (danmaku >= 10000) {
      return '${(danmaku / 10000).toStringAsFixed(1)}万';
    }
    return danmaku.toString();
  }

  /// 格式化发布时间
  String get pubdateFormatted {
    if (pubdate == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(pubdate * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      return '${diff.inDays ~/ 365}年前';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    }
    return '刚刚';
  }

  /// 格式化最后观看时间
  String get viewAtFormatted {
    if (viewAt == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(viewAt * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      return '${diff.inDays ~/ 365}年前看过';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}月前看过';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前看过';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前看过';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前看过';
    }
    return '刚刚看过';
  }

  /// 格式化时长
  String get durationFormatted {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // 修复图片 URL (处理 //xxx 格式)
  static String _fixPicUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  // 安全转换为 int
  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // 解析时长字符串 (如 "12:34" 或 "1:23:45")
  static int _parseDuration(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        return (int.tryParse(parts[0]) ?? 0) * 60 +
            (int.tryParse(parts[1]) ?? 0);
      }
      if (parts.length == 3) {
        return (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (int.tryParse(parts[2]) ?? 0);
      }
    }
    return 0;
  }
}
