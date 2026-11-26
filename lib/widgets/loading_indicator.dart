import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';

class HabitLoadingIndicator extends StatefulWidget {
  const HabitLoadingIndicator({super.key, required this.label});

  final String label;

  @override
  State<HabitLoadingIndicator> createState() => _HabitLoadingIndicatorState();
}

class _HabitLoadingIndicatorState extends State<HabitLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _bounce.reset();
    } else if (!_bounce.isAnimating) {
      _bounce.repeat();
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: RepaintBoundary(
      child: SizedBox(
        width: 48,
        height: 20,
        child: CustomPaint(
          painter: _ThreeDotLoader(
            _bounce,
            Theme.of(context).brightness == Brightness.dark
                ? AppPalette.green
                : AppPalette.deepGreen,
          ),
        ),
      ),
    ),
  );
}

class _ThreeDotLoader extends CustomPainter {
  _ThreeDotLoader(this.controller, this.color)
    : _dot = (Paint()..color = color),
      super(repaint: controller);
  final AnimationController controller;
  final Color color;
  final Paint _dot;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < 3; index++) {
      final phase = (controller.value - index * .16) % 1;
      final lift = 6 * math.sin(math.pi * (phase / .56).clamp(0, 1));
      canvas.drawCircle(
        Offset(size.width / 2 + (index - 1) * 16, size.height / 2 - lift),
        4,
        _dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThreeDotLoader oldDelegate) =>
      oldDelegate.controller != controller || oldDelegate.color != color;
}
