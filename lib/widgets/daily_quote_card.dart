import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import 'common.dart';
import 'motion_switcher.dart';

class DailyQuoteCard extends StatelessWidget {
  const DailyQuoteCard(this.quote, {super.key, this.author});

  final String quote;
  final String? author;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Read the full quote',
    child: SoftCard(
      color: AppPalette.yellow,
      onTap: () => showDialog<void>(
        context: context,
        animationStyle: appOverlayMotion(context),
        builder: (context) => AlertDialog(
          title: const Text('Today’s quote'),
          scrollable: true,
          content: author == null
              ? Text(quote)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quote),
                    const SizedBox(height: 12),
                    Text('— $author'),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.format_quote_rounded,
            color: Color(0xFFB8893E),
            size: 23,
          ),
          const SizedBox(height: 7),
          Text(
            quote,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF665125),
              height: 1.35,
            ),
          ),
        ],
      ),
    ),
  );
}
