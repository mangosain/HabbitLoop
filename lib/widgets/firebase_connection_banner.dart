import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

enum FirebaseAvailability { unknown, connected, unavailable }

final firebaseAvailability = FirebaseAvailabilityMonitor();

class FirebaseAvailabilityMonitor extends ValueNotifier<FirebaseAvailability> {
  FirebaseAvailabilityMonitor() : super(FirebaseAvailability.unknown);

  static const cacheGrace = Duration(milliseconds: 800);
  Timer? _cacheTimer;

  void observeSnapshot({required bool fromCache}) {
    if (!fromCache) {
      _set(FirebaseAvailability.connected);
      return;
    }
    if (value == FirebaseAvailability.unavailable || _cacheTimer != null) {
      return;
    }
    // Firestore often emits cached data before the first server response.
    _cacheTimer = Timer(cacheGrace, reportUnavailable);
  }

  void observeAuthError(Object error) {
    if (error is FirebaseException &&
        const {
          'network-request-failed',
          'unavailable',
          'deadline-exceeded',
          'internal-error',
        }.contains(error.code)) {
      reportUnavailable();
    }
  }

  void reportUnavailable() => _set(FirebaseAvailability.unavailable);

  void reset() => _set(FirebaseAvailability.unknown);

  void _set(FirebaseAvailability status) {
    _cacheTimer?.cancel();
    _cacheTimer = null;
    value = status;
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    super.dispose();
  }
}

class FirebaseConnectionBanner extends StatelessWidget {
  const FirebaseConnectionBanner({
    super.key,
    required this.monitor,
    required this.child,
  });

  final ValueListenable<FirebaseAvailability> monitor;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: monitor,
    child: child,
    builder: (context, availability, child) {
      final show = availability == FirebaseAvailability.unavailable;
      final colors = Theme.of(context).colorScheme;
      return Column(
        children: [
          if (show)
            Material(
              color: colors.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 17,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Firebase connection unavailable',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: colors.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: show,
              child: child!,
            ),
          ),
        ],
      );
    },
  );
}
