import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/logging/app_log.dart';

void main() {
  test('keeps a bounded in-memory log and redacts credentials', () {
    final log = AppLog(maximumEntries: 3);

    log.record('network', 'Authorization: Bearer secret-value');
    log.record('network', 'GET https://example.test/play?access_token=secret');
    log.record(
      'network',
      'GET https://user:password@example.test/path?opaque=value#fragment '
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature',
    );
    expect(log.exportText(), isNot(contains('secret-value')));
    expect(log.exportText(), isNot(contains('access_token=secret')));
    expect(log.exportText(), contains('Authorization: ***'));
    expect(log.exportText(), contains('?redacted'));
    expect(log.exportText(), isNot(contains('password')));
    expect(log.exportText(), isNot(contains('opaque=value')));
    expect(log.exportText(), isNot(contains('eyJhbGci')));
    expect(log.exportText(), contains('?redacted'));
    expect(log.exportText(), contains('[JWT_REDACTED]'));

    log.record('playback', 'ready');

    expect(log.entries.value, hasLength(3));
    expect(
      log.entries.value.map((entry) => entry.message).join('\n'),
      isNot(contains('secret-value')),
    );

    log.clear();
    expect(log.entries.value, isEmpty);
  });
}
