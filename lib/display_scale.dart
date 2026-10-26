import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Scales the navigator as well as its overlays, so dialogs, hit testing and
/// menus use the same coordinate system. Font scaling remains independent.
class DisplayScale extends StatelessWidget {
  const DisplayScale({
    super.key,
    required this.fontScale,
    required this.viewScale,
    required this.child,
  });
  final double fontScale;
  final double viewScale;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final width = math.max(1200.0, constraints.maxWidth / viewScale);
      final height = constraints.maxHeight / viewScale;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width * viewScale,
          height: constraints.maxHeight,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: height,
              child: MediaQuery(
                data: media.copyWith(
                  size: Size(width, height),
                  devicePixelRatio: media.devicePixelRatio * viewScale,
                  padding: media.padding / viewScale,
                  viewPadding: media.viewPadding / viewScale,
                  viewInsets: media.viewInsets / viewScale,
                  textScaler: _CombinedTextScaler(media.textScaler, fontScale),
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CombinedTextScaler extends TextScaler {
  const _CombinedTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
}
