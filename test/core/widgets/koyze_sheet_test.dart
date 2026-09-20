import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';

void main() {
  testWidgets('sheet max height stays below the status bar', (tester) async {
    late double height;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(top: 59, bottom: 34),
          viewPadding: EdgeInsets.only(top: 59, bottom: 34),
        ),
        child: Builder(
          builder: (context) {
            height = koyzeSheetMaxHeight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(height, 852 - 59 - 16);
  });
}
