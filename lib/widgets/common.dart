import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(17),
    this.onTap,
  });
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).cardColor,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.background,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? background;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: background ?? Theme.of(context).cardColor,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.color,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color ?? AppPalette.green,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 19,
              width: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 19),
                ],
              ],
            ),
    ),
  );
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.center,
    this.subtitle,
    this.size = 132,
    this.color = AppPalette.green,
    this.stroke = 12,
  });
  final double progress;
  final String center;
  final String? subtitle;
  final double size;
  final double stroke;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(v, color, stroke),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              center,
              style: TextStyle(
                fontSize: size * .21,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: size * .085,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : AppPalette.muted,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.color, this.stroke);
  final double fraction, stroke;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = color.withValues(alpha: .16)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}

IconData taskCategoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'health':
      return Icons.fitness_center_rounded;
    case 'study':
      return Icons.menu_book_rounded;
    case 'work':
      return Icons.laptop_mac_rounded;
    case 'mindfulness':
      return Icons.spa_rounded;
    default:
      return Icons.wb_sunny_outlined;
  }
}

Color taskCategoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'health':
      return const Color(0xFFE8DFFD);
    case 'study':
      return const Color(0xFFFFEDD9);
    case 'work':
      return const Color(0xFFE2F1FF);
    case 'mindfulness':
      return const Color(0xFFFBE4F3);
    default:
      return AppPalette.mint;
  }
}

void toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
  });
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 25),
    child: Column(
      children: [
        Icon(icon, size: 44, color: AppPalette.green),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppPalette.muted),
        ),
      ],
    ),
  );
}
