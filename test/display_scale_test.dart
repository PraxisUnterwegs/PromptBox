import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_box/display_scale.dart';

void main() {
  testWidgets('字体缩放保留控件尺寸，界面缩放同步坐标和点击位置', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var taps = 0;
    Widget app(double font, double view) => MaterialApp(
      builder:
          (_, child) =>
              DisplayScale(fontScale: font, viewScale: view, child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: const ValueKey('box'),
            width: 200,
            height: 100,
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('缩放样例'),
            ),
          ),
        ),
      ),
    );
    final text = find.text('缩放样例');
    final box = find.byKey(const ValueKey('box'));
    await tester.pumpWidget(app(1, 1));
    final initialHeight = tester.getSize(text).height;
    expect(tester.getSize(box).width, 200);
    await tester.pumpWidget(app(1.5, 1));
    await tester.pumpAndSettle();
    expect(tester.getSize(text).height, greaterThan(initialHeight * 1.4));
    expect(tester.getSize(box).width, 200);
    await tester.pumpWidget(app(1.5, 1.5));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(box).dx - tester.getTopLeft(box).dx,
      closeTo(300, .01),
    );
    await tester.tap(find.byType(TextButton));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
