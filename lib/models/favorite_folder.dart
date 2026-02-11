class FavoriteFolder {
  final int id;
  final String title;
  final int mediaCount;
  final bool isDefault;

  const FavoriteFolder({
    required this.id,
    required this.title,
    this.mediaCount = 0,
    this.isDefault = false,
  });

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) {
    return FavoriteFolder(
      id: _toInt(json['id']),
      title: (json['title'] ?? '').toString(),
      mediaCount: _toInt(json['media_count']),
      isDefault: (json['fav_state'] ?? 0) == 0,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
