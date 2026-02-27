class BiliSubtitleTrack {
  final String id;
  final String lang;
  final String label;
  final String subtitleUrl;

  const BiliSubtitleTrack({
    required this.id,
    required this.lang,
    required this.label,
    required this.subtitleUrl,
  });

  factory BiliSubtitleTrack.fromJson(Map<String, dynamic> json) {
    return BiliSubtitleTrack(
      id: (json['id'] ?? '').toString(),
      lang: (json['lan'] ?? '').toString(),
      label: (json['lan_doc'] ?? json['lan'] ?? '').toString(),
      subtitleUrl: (json['subtitle_url'] ?? '').toString(),
    );
  }
}

class BiliSubtitleItem {
  final double from;
  final double to;
  final String content;

  const BiliSubtitleItem({
    required this.from,
    required this.to,
    required this.content,
  });

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  factory BiliSubtitleItem.fromJson(Map<String, dynamic> json) {
    final from = _toDouble(json['from']);
    final to = _toDouble(json['to']);
    return BiliSubtitleItem(
      from: from,
      to: to < from ? from : to,
      content: (json['content'] ?? '').toString(),
    );
  }
}

class BiliSubtitleTracksResult {
  final List<BiliSubtitleTrack> tracks;
  final bool needLoginSubtitle;

  const BiliSubtitleTracksResult({
    required this.tracks,
    required this.needLoginSubtitle,
  });
}
