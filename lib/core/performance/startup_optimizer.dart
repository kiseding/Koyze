// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// App startup performance optimizer.
/// 
/// Features:
/// - Lazy initialization
/// - Resource preloading
/// - Splash screen optimization
/// - Cold start time tracking
/// - Warm start optimization

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Startup metrics
class StartupMetrics {
  final DateTime startTime;
  DateTime? splashEndTime;
  DateTime? initCompleteTime;
  DateTime? firstFrameTime;

  StartupMetrics({required this.startTime});

  Duration? get splashDuration =>
      splashEndTime?.difference(startTime);

  Duration? get initDuration =>
      initCompleteTime?.difference(startTime);

  Duration? get timeToFirstFrame =>
      firstFrameTime?.difference(startTime);

  Map<String, dynamic> toJson() {
    return {
      'splashDuration': splashDuration?.inMilliseconds,
      'initDuration': initDuration?.inMilliseconds,
      'timeToFirstFrame': timeToFirstFrame?.inMilliseconds,
    };
  }
}

/// Startup optimizer
class StartupOptimizer {
  static final StartupOptimizer _instance = StartupOptimizer._internal();
  factory StartupOptimizer() => _instance;
  StartupOptimizer._internal();

  final StartupMetrics metrics = StartupMetrics(startTime: DateTime.now());
  final List<Future<void> Function()> _deferredTasks = [];

  /// Mark splash screen ended
  void markSplashEnd() {
    metrics.splashEndTime = DateTime.now();
    debugPrint('⏱️ Splash duration: ${metrics.splashDuration?.inMilliseconds}ms');
  }

  /// Mark initialization complete
  void markInitComplete() {
    metrics.initCompleteTime = DateTime.now();
    debugPrint('⏱️ Init duration: ${metrics.initDuration?.inMilliseconds}ms');
  }

  /// Mark first frame rendered
  void markFirstFrame() {
    metrics.firstFrameTime = DateTime.now();
    debugPrint('⏱️ Time to first frame: ${metrics.timeToFirstFrame?.inMilliseconds}ms');
  }

  /// Register deferred initialization task
  void registerDeferredTask(Future<void> Function() task) {
    _deferredTasks.add(task);
  }

  /// Run all deferred tasks after UI is ready
  Future<void> runDeferredTasks() async {
    debugPrint('🚀 Running ${_deferredTasks.length} deferred tasks...');
    
    for (final task in _deferredTasks) {
      try {
        await task();
      } catch (e) {
        debugPrint('❌ Deferred task failed: $e');
      }
    }
    
    _deferredTasks.clear();
    debugPrint('✅ All deferred tasks completed');
  }

  /// Preload essential resources
  Future<void> preloadResources(BuildContext context) async {
    // Preload images
    await Future.wait([
      precacheImage(AssetImage('assets/images/logo.png'), context),
      precacheImage(AssetImage('assets/images/placeholder.png'), context),
    ]);

    debugPrint('✅ Resources preloaded');
  }

  /// Get startup report
  Map<String, dynamic> getReport() {
    return metrics.toJson();
  }
}

/// Optimized splash screen
class OptimizedSplashScreen extends StatefulWidget {
  final Future<void> Function() onInitialize;
  final Widget Function(BuildContext) builder;
  final Duration minDuration;

  const OptimizedSplashScreen({
    Key? key,
    required this.onInitialize,
    required this.builder,
    this.minDuration = const Duration(milliseconds: 1500),
  }) : super(key: key);

  @override
  State<OptimizedSplashScreen> createState() => _OptimizedSplashScreenState();
}

class _OptimizedSplashScreenState extends State<OptimizedSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _initialize();
  }

  Future<void> _initialize() async {
    final startTime = DateTime.now();

    // Run initialization
    await widget.onInitialize();

    // Ensure minimum splash duration
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < widget.minDuration) {
      await Future.delayed(widget.minDuration - elapsed);
    }

    StartupOptimizer().markSplashEnd();

    if (mounted) {
      setState(() => _initialized = true);
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return _buildSplash();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: widget.builder(context),
    );
  }

  Widget _buildSplash() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6750A4),
              Color(0xFF7D5260),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Icon(
                Icons.music_note_rounded,
                size: 120,
                color: Colors.white,
              ),
              SizedBox(height: 24),
              
              // App name
              Text(
                'Koyze',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 48),
              
              // Loading indicator
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lazy widget loader
class LazyWidget extends StatefulWidget {
  final Future<Widget> Function() builder;
  final Widget placeholder;

  const LazyWidget({
    Key? key,
    required this.builder,
    required this.placeholder,
  }) : super(key: key);

  @override
  State<LazyWidget> createState() => _LazyWidgetState();
}

class _LazyWidgetState extends State<LazyWidget> {
  Widget? _child;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    
    setState(() => _loading = true);
    
    try {
      final child = await widget.builder();
      if (mounted) {
        setState(() => _child = child);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _child ?? widget.placeholder;
  }
}

/// Resource preloader
class ResourcePreloader {
  static Future<void> preloadImages(
    BuildContext context,
    List<String> assetPaths,
  ) async {
    await Future.wait(
      assetPaths.map((path) => precacheImage(AssetImage(path), context)),
    );
  }

  static Future<void> preloadNetworkImages(
    BuildContext context,
    List<String> urls,
  ) async {
    await Future.wait(
      urls.map((url) => precacheImage(NetworkImage(url), context)),
    );
  }

  static Future<void> warmUpShaders(BuildContext context) async {
    // Warm up common shaders
    await Future.wait([
      _warmUpShader(context, ShaderWarmUp.defaultShader()),
    ]);
  }

  static Future<void> _warmUpShader(
    BuildContext context,
    ShaderWarmUp shader,
  ) async {
    final view = View.of(context);
    await shader.warmUpOnCanvas(Size(
      view.physicalSize.width / view.devicePixelRatio,
      view.physicalSize.height / view.devicePixelRatio,
    ));
  }
}

class ShaderWarmUp {
  static ShaderWarmUp defaultShader() => ShaderWarmUp();

  Future<void> warmUpOnCanvas(Size size) async {
    // Implement shader warm-up logic
    await Future.delayed(Duration(milliseconds: 100));
  }
}

/// Performance budget monitor
class PerformanceBudget {
  static const int targetStartupTime = 2000; // 2 seconds
  static const int targetFrameTime = 16; // 16ms for 60fps
  static const int maxMemoryMB = 500;

  static bool checkStartupBudget(StartupMetrics metrics) {
    final duration = metrics.timeToFirstFrame?.inMilliseconds ?? 0;
    final withinBudget = duration <= targetStartupTime;
    
    if (!withinBudget) {
      debugPrint('⚠️ Startup time exceeded budget: ${duration}ms > ${targetStartupTime}ms');
    }
    
    return withinBudget;
  }

  static bool checkFrameBudget(Duration frameTime) {
    final withinBudget = frameTime.inMilliseconds <= targetFrameTime;
    
    if (!withinBudget) {
      debugPrint('⚠️ Frame time exceeded budget: ${frameTime.inMilliseconds}ms > ${targetFrameTime}ms');
    }
    
    return withinBudget;
  }
}

/// Memory-efficient image cache
class MemoryEfficientImageCache extends ImageCache {
  @override
  void clear() {
    super.clear();
    debugPrint('🗑️ Image cache cleared');
  }

  @override
  void clearLiveImages() {
    super.clearLiveImages();
    debugPrint('🗑️ Live images cleared');
  }

  /// Trim cache to target size
  void trimToSize(int targetSizeMB) {
    final currentSize = currentSizeBytes / (1024 * 1024);
    if (currentSize > targetSizeMB) {
      clear();
      debugPrint('🗑️ Cache trimmed: ${currentSize.toStringAsFixed(1)}MB → 0MB');
    }
  }
}
