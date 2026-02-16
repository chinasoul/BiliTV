/// 评论数据模型
class Comment {
  final int rpid; // 评论 ID
  final int mid; // 用户 UID
  final String uname; // 用户名
  final String avatar; // 头像 URL
  final String content; // 评论内容
  final int like; // 点赞数
  final int rcount; // 回复数
  final int ctime; // 评论时间戳 (秒)
  final List<Comment> replies; // 热门回复 (预加载前3条)

  Comment({
    required this.rpid,
    required this.mid,
    required this.uname,
    required this.avatar,
    required this.content,
    this.like = 0,
    this.rcount = 0,
    this.ctime = 0,
    this.replies = const [],
  });

  /// 从 API JSON 解析
  factory Comment.fromJson(Map<String, dynamic> json) {
    final member = json['member'] as Map<String, dynamic>? ?? {};
    final contentMap = json['content'] as Map<String, dynamic>? ?? {};

    List<Comment> replies = [];
    if (json['replies'] is List) {
      replies =
          (json['replies'] as List)
              .map((e) => Comment.fromJson(e as Map<String, dynamic>))
              .toList();
    }

    return Comment(
      rpid: json['rpid'] as int? ?? 0,
      mid: json['mid'] as int? ?? (member['mid'] as int? ?? 0),
      uname: member['uname'] as String? ?? '',
      avatar: member['avatar'] as String? ?? '',
      content: contentMap['message'] as String? ?? '',
      like: json['like'] as int? ?? 0,
      rcount: json['rcount'] as int? ?? 0,
      ctime: json['ctime'] as int? ?? 0,
      replies: replies,
    );
  }

  /// 格式化点赞数
  String get likeText {
    if (like >= 10000) {
      return '${(like / 10000).toStringAsFixed(1)}万';
    }
    return like.toString();
  }

  /// 格式化时间
  String get timeText {
    final dt = DateTime.fromMillisecondsSinceEpoch(ctime * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}个月前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
