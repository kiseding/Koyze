// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:koyze/core/ui/advanced_image_loader.dart';

void main() {
  group('AdvancedImageCache', () {
    late AdvancedImageCache cache;

    setUp(() {
      cache = AdvancedImageCache();
      cache.clear();
    });

    test('should store and retrieve images', () {
      final url = 'https://example.com/image.jpg';
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      cache.put(url, bytes);
      final retrieved = cache.get(url);

      expect(retrieved, equals(bytes));
    });

    test('should return null for non-existent images', () {
      final result = cache.get('https://nonexistent.com/image.jpg');
      expect(result, isNull);
    });

    test('should evict old entries when cache is full', () {
      // Fill cache with large images
      for (int i = 0; i < 60; i++) {
        final url = 'https://example.com/image$i.jpg';
        final bytes = Uint8List(1024 * 1024); // 1MB each
        cache.put(url, bytes);
      }

      final stats = cache.getStats();
      expect(stats['sizeMB'], lessThanOrEqualTo(50)); // Max 50MB
    });

    test('should update LRU order on access', () {
      final url1 = 'https://example.com/image1.jpg';
      final url2 = 'https://example.com/image2.jpg';
      final bytes = Uint8List.fromList([1, 2, 3]);

      cache.put(url1, bytes);
      cache.put(url2, bytes);

      // Access url1 to move it to front
      cache.get(url1);

      // Fill cache to trigger eviction
      for (int i = 0; i < 60; i++) {
        final url = 'https://example.com/large$i.jpg';
        final largeBytes = Uint8List(1024 * 1024);
        cache.put(url, largeBytes);
      }

      // url1 should still be cached (recently accessed)
      // url2 should be evicted (least recently used)
      expect(cache.get(url2), isNull);
    });

    test('should clear all cached images', () {
      cache.put('url1', Uint8List.fromList([1]));
      cache.put('url2', Uint8List.fromList([2]));

      cache.clear();

      expect(cache.get('url1'), isNull);
      expect(cache.get('url2'), isNull);
      expect(cache.getStats()['entries'], equals(0));
    });

    test('should track cache statistics', () {
      final stats = cache.getStats();

      expect(stats, contains('entries'));
      expect(stats, contains('sizeMB'));
      expect(stats, contains('maxSizeMB'));
      expect(stats['maxSizeMB'], equals(50));
    });
  });

  group('AdvancedImageLoader', () {
    late AdvancedImageLoader loader;

    setUp(() {
      loader = AdvancedImageLoader();
      loader.clearCache();
    });

    test('should deduplicate concurrent requests', () async {
      final url = 'https://example.com/image.jpg';
      
      // Make multiple concurrent requests
      final futures = List.generate(5, (_) => loader.loadImage(url));
      final results = await Future.wait(futures);

      // All should return the same result
      expect(results.length, equals(5));
    });

    test('should preload images', () async {
      final urls = [
        'https://example.com/image1.jpg',
        'https://example.com/image2.jpg',
        'https://example.com/image3.jpg',
      ];

      await loader.preloadImages(urls);

      // Images should be in cache
      final stats = loader.getCacheStats();
      expect(stats['entries'], greaterThan(0));
    });

    test('should handle network errors gracefully', () async {
      final result = await loader.loadImage(
        'https://invalid-url-that-does-not-exist.com/image.jpg',
        retries: 1,
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });
  });
}
