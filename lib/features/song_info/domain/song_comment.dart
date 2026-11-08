/// 一条歌曲评论。
class SongComment {
  const SongComment({
    required this.id,
    required this.userName,
    required this.content,
    required this.likedCount,
    required this.time,
    this.avatarUrl,
    this.replyTo,
    this.location,
  });

  final String id;
  final String userName;
  final String content;
  final int likedCount;
  final DateTime time;
  final String? avatarUrl;

  /// 楼中楼：这条评论回复的人。
  final String? replyTo;

  /// IP 属地。网易从 2022 年起返回，展示出来比"来自 iPhone"有用。
  final String? location;

  bool get hasReply => replyTo != null && replyTo!.isNotEmpty;
}

/// 一页评论：首屏同时给热门与最新，翻页只有最新。
class SongCommentsPage {
  const SongCommentsPage({
    required this.hot,
    required this.latest,
    required this.total,
    required this.hasMore,
  });

  static const SongCommentsPage empty = SongCommentsPage(
    hot: [],
    latest: [],
    total: 0,
    hasMore: false,
  );

  final List<SongComment> hot;
  final List<SongComment> latest;
  final int total;
  final bool hasMore;

  bool get isEmpty => hot.isEmpty && latest.isEmpty;
}
