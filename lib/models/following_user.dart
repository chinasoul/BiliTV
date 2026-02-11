class FollowingUser {
  final int mid;
  final String uname;
  final String face;
  final String sign;
  final bool isVip;
  final bool isOfficial;

  const FollowingUser({
    required this.mid,
    required this.uname,
    required this.face,
    this.sign = '',
    this.isVip = false,
    this.isOfficial = false,
  });

  factory FollowingUser.fromJson(Map<String, dynamic> json) {
    final vipInfo = json['vip'] as Map<String, dynamic>? ?? {};
    final official = json['official_verify'] as Map<String, dynamic>? ?? {};
    return FollowingUser(
      mid: _toInt(json['mid']),
      uname: (json['uname'] ?? '').toString(),
      face: _fixPicUrl((json['face'] ?? '').toString()),
      sign: (json['sign'] ?? '').toString(),
      isVip: _toInt(vipInfo['vipType']) > 0 || _toInt(vipInfo['type']) > 0,
      isOfficial: _toInt(official['type']) >= 0,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _fixPicUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }
}
