import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/updates/domain/update_service.dart';

void main() {
  group('版本号比较', () {
    test('主版本更新', () {
      expect(UpdateService.compareVersions('4.3.0', '4.2.0'), greaterThan(0));
    });

    test('段落数不同按 0 补齐', () {
      expect(UpdateService.compareVersions('4.2', '4.2.0'), 0);
      expect(UpdateService.compareVersions('4.2.1', '4.2'), greaterThan(0));
    });

    test('补丁号更新', () {
      expect(UpdateService.compareVersions('4.2.1', '4.2.0'), greaterThan(0));
      expect(UpdateService.compareVersions('4.1.9', '4.2.0'), lessThan(0));
    });
  });
}
