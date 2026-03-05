/// 图文动态数据模型
class DynamicDraw {
  final String id;
  final String text;
  final List<String> images;
  final String authorName;
  final String authorFace;
  final int authorMid;
  final int pubTs;
  final int likeCount;
  final int commentCount;
  final int forwardCount;

  DynamicDraw({
    required this.id,
    this.text = '',
    this.images = const [],
    this.authorName = '',
    this.authorFace = '',
    this.authorMid = 0,
    this.pubTs = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.forwardCount = 0,
  });

  String get firstImage => images.isNotEmpty ? images.first : '';

  String get imageCountLabel => images.length > 1 ? '${images.length}图' : '';

  String get likeFormatted => _formatCount(likeCount);
  String get commentFormatted => _formatCount(commentCount);

  String get pubdateFormatted {
    if (pubTs == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(pubTs * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}年前';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}月前';
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'text': text,
    'images': images,
    'authorName': authorName,
    'authorFace': authorFace,
    'authorMid': authorMid,
    'pubTs': pubTs,
    'likeCount': likeCount,
    'commentCount': commentCount,
    'forwardCount': forwardCount,
  };

  factory DynamicDraw.fromMap(Map<String, dynamic> json) => DynamicDraw(
    id: json['id'] ?? '',
    text: json['text'] ?? '',
    images: (json['images'] as List?)?.cast<String>() ?? [],
    authorName: json['authorName'] ?? '',
    authorFace: json['authorFace'] ?? '',
    authorMid: json['authorMid'] ?? 0,
    pubTs: json['pubTs'] ?? 0,
    likeCount: json['likeCount'] ?? 0,
    commentCount: json['commentCount'] ?? 0,
    forwardCount: json['forwardCount'] ?? 0,
  );

  static String _formatCount(int count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }
}

/// 专栏动态数据模型
class DynamicArticle {
  final String id;
  final String title;
  final String desc;
  final String coverUrl;
  final String jumpUrl;
  final String label;
  final String authorName;
  final String authorFace;
  final int authorMid;
  final int pubTs;
  final int likeCount;
  final int commentCount;
  final int forwardCount;

  DynamicArticle({
    required this.id,
    this.title = '',
    this.desc = '',
    this.coverUrl = '',
    this.jumpUrl = '',
    this.label = '',
    this.authorName = '',
    this.authorFace = '',
    this.authorMid = 0,
    this.pubTs = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.forwardCount = 0,
  });

  String get likeFormatted => _formatCount(likeCount);
  String get commentFormatted => _formatCount(commentCount);

  String get pubdateFormatted {
    if (pubTs == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(pubTs * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}年前';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}月前';
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'desc': desc,
    'coverUrl': coverUrl,
    'jumpUrl': jumpUrl,
    'label': label,
    'authorName': authorName,
    'authorFace': authorFace,
    'authorMid': authorMid,
    'pubTs': pubTs,
    'likeCount': likeCount,
    'commentCount': commentCount,
    'forwardCount': forwardCount,
  };

  factory DynamicArticle.fromMap(Map<String, dynamic> json) => DynamicArticle(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    desc: json['desc'] ?? '',
    coverUrl: json['coverUrl'] ?? '',
    jumpUrl: json['jumpUrl'] ?? '',
    label: json['label'] ?? '',
    authorName: json['authorName'] ?? '',
    authorFace: json['authorFace'] ?? '',
    authorMid: json['authorMid'] ?? 0,
    pubTs: json['pubTs'] ?? 0,
    likeCount: json['likeCount'] ?? 0,
    commentCount: json['commentCount'] ?? 0,
    forwardCount: json['forwardCount'] ?? 0,
  );

  static String _formatCount(int count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }
}

/// 图文动态 Feed 数据结构
class DynamicDrawFeed {
  final List<DynamicDraw> items;
  final String offset;
  final bool hasMore;

  DynamicDrawFeed({
    required this.items,
    required this.offset,
    required this.hasMore,
  });
}

/// 专栏动态 Feed 数据结构
class DynamicArticleFeed {
  final List<DynamicArticle> items;
  final String offset;
  final bool hasMore;

  DynamicArticleFeed({
    required this.items,
    required this.offset,
    required this.hasMore,
  });
}
