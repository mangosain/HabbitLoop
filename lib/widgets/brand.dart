import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import 'loading_indicator.dart';
import 'shared_element.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88});

  final double size;
  static const _art = AssetImage('assets/art/brand_tile.png');

  @override
  Widget build(BuildContext context) => SharedElement(
    tag: 'habitloop-brand-mark',
    flightShuttleBuilder: (_, _, _, _, _) => const Image(
      image: _art,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    ),
    child: SizedBox.square(
      dimension: size,
      child: const Image(image: _art, fit: BoxFit.fill),
    ),
  );
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(19, 8, 19, 0),
    child: Row(
      children: [
        const BrandMark(size: 34),
        const SizedBox(width: 9),
        Text(
          'HabitLoop',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class BrandLoading extends StatelessWidget {
  const BrandLoading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 280,
        height: 246,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: -31,
              child: SizedBox.square(
                dimension: 214,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Color(0xD6D9F2CB), Color(0x00D9F2CB)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 19,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(33)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x452B7643),
                      offset: Offset(0, 11),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: BrandMark(size: 114),
              ),
            ),
            Positioned(
              top: 146,
              child: Text(
                'HabitLoop',
                style: TextStyle(
                  color: AppPalette.ink,
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                ),
              ),
            ),
            Positioned(
              top: 185,
              child: Text(
                'Small steps, big changes.',
                style: TextStyle(
                  color: Color(0xFF566960),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              top: 217,
              child: HabitLoadingIndicator(label: 'Loading HabitLoop'),
            ),
          ],
        ),
      ),
    ),
  );
}
