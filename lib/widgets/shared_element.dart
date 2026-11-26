import 'package:material_ui/material_ui.dart';

class SharedElement extends StatelessWidget {
  const SharedElement({
    super.key,
    required this.tag,
    required this.child,
    this.flightShuttleBuilder,
  });

  final Object tag;
  final Widget child;
  final HeroFlightShuttleBuilder? flightShuttleBuilder;

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: tag,
      createRectTween: (begin, end) =>
          MaterialRectArcTween(begin: begin, end: end),
      flightShuttleBuilder: flightShuttleBuilder,
      child: child,
    ),
  );
}

class SharedIcon extends StatelessWidget {
  const SharedIcon({
    super.key,
    required this.tag,
    required this.icon,
    required this.child,
  });

  final Object tag;
  final IconData icon;
  final Widget child;

  static Widget _flight(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext from,
    BuildContext to,
  ) {
    final fromIcon = (from.findAncestorWidgetOfExactType<SharedIcon>()!).icon;
    final toIcon = (to.findAncestorWidgetOfExactType<SharedIcon>()!).icon;
    if (fromIcon == toIcon) return _glyph(fromIcon);
    final incoming = direction == HeroFlightDirection.push
        ? animation
        : ReverseAnimation(animation);
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: ReverseAnimation(incoming),
          child: _glyph(fromIcon),
        ),
        FadeTransition(opacity: incoming, child: _glyph(toIcon)),
      ],
    );
  }

  static Widget _glyph(IconData icon) => Center(
    child: FractionallySizedBox(
      widthFactor: .58,
      heightFactor: .58,
      child: FittedBox(child: Icon(icon, color: const Color(0xFF247D44))),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      SharedElement(tag: tag, flightShuttleBuilder: _flight, child: child);
}

const remindersHeroTag = 'reminder-settings';
const activityHeroTag = 'activity-history';
const addTaskHeroTag = 'add-task-toolbar';
const addTaskFabHeroTag = 'add-task-fab';

Route<T> sharedRoute<T>(
  BuildContext context,
  Widget page, {
  bool overlay = false,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<T>(
    opaque: !overlay,
    barrierDismissible: overlay,
    barrierColor: overlay ? Colors.black54 : null,
    barrierLabel: overlay
        ? MaterialLocalizations.of(context).modalBarrierDismissLabel
        : null,
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 360),
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 290),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}
