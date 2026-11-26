import 'package:material_ui/material_ui.dart';

const _duration = Duration(milliseconds: 220);
const _reverseDuration = Duration(milliseconds: 160);

AnimationStyle appOverlayMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: _duration,
        reverseDuration: _reverseDuration,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

class MotionSwitcher extends StatelessWidget {
  const MotionSwitcher({super.key, required this.child});
  final Widget child;

  static final _offset = Tween<Offset>(
    begin: const Offset(0, .018),
    end: Offset.zero,
  );

  static Widget _transition(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: _offset.animate(animation),
          child: child,
        ),
      );

  static Widget _layout(Widget? current, List<Widget> previous) => Stack(
    alignment: Alignment.topCenter,
    children: [
      for (final child in previous)
        Positioned.fill(
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: HeroMode(enabled: false, child: child),
              ),
            ),
          ),
        ),
      ?current,
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSwitcher(
      duration: _duration,
      reverseDuration: _reverseDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: _layout,
      transitionBuilder: _transition,
      child: child,
    );
  }
}
