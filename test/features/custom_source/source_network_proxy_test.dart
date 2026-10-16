// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/source_network_proxy.dart';

void main() {
  group('SourceNetworkProxy', () {
    late SourceNetworkProxy proxy;

    setUp(() {
      proxy = SourceNetworkProxy();
    });

    group('Domain Whitelist', () {
      test('should block non-whitelisted domain', () async {
        final url = 'https://attacker.com/steal';
        
        await expectLater(
          proxy.fetch(url, 'test-source'),
          throwsA(isA<SecurityException>().having(
            (e) => e.code,
            'code',
            'DOMAIN_NOT_ALLOWED',
          )),
        );
      });

      test('should block similar-looking malicious domain', () async {
        final url = 'https://music-163.com/api';
        
        await expectLater(
          proxy.fetch(url, 'test-source'),
          throwsA(isA<SecurityException>()),
        );
      });
    });

    group('Protocol Validation', () {
      test('should reject non-HTTP protocols', () async {
        final url = 'ftp://music.163.com/file';
        
        await expectLater(
          proxy.fetch(url, 'test-source'),
          throwsA(isA<SecurityException>().having(
            (e) => e.code,
            'code',
            'INVALID_PROTOCOL',
          )),
        );
      });

      test('should reject file:// URLs', () async {
        final url = 'file:///etc/passwd';
        
        await expectLater(
          proxy.fetch(url, 'test-source'),
          throwsA(isA<SecurityException>()),
        );
      });
    });

    group('Statistics', () {
      test('should track request counts', () {
        final stats = proxy.getStats('test-source');
        
        expect(stats.containsKey('totalRequests'), true);
        expect(stats.containsKey('successfulRequests'), true);
        expect(stats.containsKey('failedRequests'), true);
      });

      test('should show rate limit remaining', () {
        final stats = proxy.getStats('test-source');
        
        expect(stats.containsKey('rateLimitRemaining'), true);
        expect(stats['rateLimitRemaining'], lessThanOrEqualTo(30));
      });
    });
  });
}
