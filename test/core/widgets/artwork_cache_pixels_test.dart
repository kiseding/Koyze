import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/artwork_image.dart';

void main() {
  test('cover decode size follows the tile and stays capped', () {
    expect(
      artworkCachePixels(
        cacheWidth: 64,
        width: 400,
        maxConstraintWidth: 400,
        devicePixelRatio: 3,
      ),
      64,
    );
    expect(
      artworkCachePixels(
        cacheWidth: null,
        width: 48,
        maxConstraintWidth: double.infinity,
        devicePixelRatio: 3,
      ),
      144,
    );
    expect(
      artworkCachePixels(
        cacheWidth: null,
        width: null,
        maxConstraintWidth: 800,
        devicePixelRatio: 3,
      ),
      1080,
    );
  });
}
