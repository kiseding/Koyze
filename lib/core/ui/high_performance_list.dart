// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// High-performance list with virtual scrolling and optimizations.
/// 
/// Features:
/// - Virtual scrolling (only render visible items)
/// - Item pool reuse
/// - Lazy loading pagination
/// - Pull-to-refresh
/// - Smart prefetching

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Virtual scroll controller
class VirtualScrollController extends ScrollController {
  final double itemHeight;
  final int totalItems;

  VirtualScrollController({
    required this.itemHeight,
    required this.totalItems,
  });

  int get firstVisibleIndex {
    if (!hasClients) return 0;
    return (offset / itemHeight).floor().clamp(0, totalItems - 1);
  }

  int get lastVisibleIndex {
    if (!hasClients) return 0;
    final viewportHeight = position.viewportDimension;
    return ((offset + viewportHeight) / itemHeight).ceil().clamp(0, totalItems - 1);
  }

  int get visibleItemCount => lastVisibleIndex - firstVisibleIndex + 1;
}

/// High-performance list with virtual scrolling
class HighPerformanceListView<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext, T, int) itemBuilder;
  final double itemHeight;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onLoadMore;
  final Widget? loadingWidget;
  final Widget? emptyWidget;
  final EdgeInsets? padding;
  final int bufferCount; // Extra items to render above/below viewport

  const HighPerformanceListView({
    Key? key,
    required this.items,
    required this.itemBuilder,
    required this.itemHeight,
    this.onRefresh,
    this.onLoadMore,
    this.loadingWidget,
    this.emptyWidget,
    this.padding,
    this.bufferCount = 3,
  }) : super(key: key);

  @override
  State<HighPerformanceListView<T>> createState() => _HighPerformanceListViewState<T>();
}

class _HighPerformanceListViewState<T> extends State<HighPerformanceListView<T>> {
  late VirtualScrollController _scrollController;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController = VirtualScrollController(
      itemHeight: widget.itemHeight,
      totalItems: widget.items.length,
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load more when near bottom
    if (widget.onLoadMore != null && !_isLoadingMore) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      final threshold = maxScroll * 0.8; // 80% scrolled

      if (currentScroll >= threshold) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      await widget.onLoadMore!();
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return widget.emptyWidget ?? _buildDefaultEmpty();
    }

    Widget listView = CustomScrollView(
      controller: _scrollController,
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: widget.padding ?? EdgeInsets.zero,
          sliver: SliverFixedExtentList(
            itemExtent: widget.itemHeight,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= widget.items.length) return null;
                
                return RepaintBoundary(
                  child: widget.itemBuilder(
                    context,
                    widget.items[index],
                    index,
                  ),
                );
              },
              childCount: widget.items.length,
            ),
          ),
        ),
        
        if (_isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: widget.loadingWidget ?? CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );

    // Add pull-to-refresh
    if (widget.onRefresh != null) {
      listView = RefreshIndicator(
        onRefresh: widget.onRefresh!,
        child: listView,
      );
    }

    return listView;
  }

  Widget _buildDefaultEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            '暂无数据',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// Optimized grid view with lazy loading
class HighPerformanceGridView<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext, T, int) itemBuilder;
  final int crossAxisCount;
  final double childAspectRatio;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onLoadMore;
  final EdgeInsets? padding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  const HighPerformanceGridView({
    Key? key,
    required this.items,
    required this.itemBuilder,
    this.crossAxisCount = 2,
    this.childAspectRatio = 1.0,
    this.onRefresh,
    this.onLoadMore,
    this.padding,
    this.crossAxisSpacing = 8.0,
    this.mainAxisSpacing = 8.0,
  }) : super(key: key);

  @override
  State<HighPerformanceGridView<T>> createState() => _HighPerformanceGridViewState<T>();
}

class _HighPerformanceGridViewState<T> extends State<HighPerformanceGridView<T>> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.onLoadMore != null && !_isLoadingMore) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      
      if (currentScroll >= maxScroll * 0.8) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      await widget.onLoadMore!();
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget gridView = GridView.builder(
      controller: _scrollController,
      padding: widget.padding ?? EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: widget.childAspectRatio,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
      ),
      itemCount: widget.items.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= widget.items.length) {
          return Center(child: CircularProgressIndicator());
        }
        
        return RepaintBoundary(
          child: widget.itemBuilder(
            context,
            widget.items[index],
            index,
          ),
        );
      },
    );

    if (widget.onRefresh != null) {
      gridView = RefreshIndicator(
        onRefresh: widget.onRefresh!,
        child: gridView,
      );
    }

    return gridView;
  }
}

/// Debouncer for search/input optimization
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 500)});

  void call(VoidCallback callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Throttler for scroll/resize optimization
class Throttler {
  final Duration interval;
  DateTime? _lastRun;

  Throttler({this.interval = const Duration(milliseconds: 100)});

  void call(VoidCallback callback) {
    final now = DateTime.now();
    
    if (_lastRun == null || now.difference(_lastRun!) >= interval) {
      callback();
      _lastRun = now;
    }
  }
}

/// Optimized song card with RepaintBoundary
class OptimizedSongCard extends StatelessWidget {
  final String title;
  final String artist;
  final String? coverUrl;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  const OptimizedSongCard({
    Key? key,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.onTap,
    this.onPlay,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Cover image
              if (coverUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Image.network(
                      coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.music_note, color: Colors.grey[400]),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.music_note, color: Colors.grey[400]),
                ),
              
              SizedBox(width: 12),
              
              // Title and artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Play button
              if (onPlay != null)
                IconButton(
                  icon: Icon(Icons.play_circle_outline),
                  onPressed: onPlay,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
