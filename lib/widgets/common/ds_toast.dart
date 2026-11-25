import 'dart:async';
import 'package:flutter/material.dart';

import '../../theme/ds_theme.dart';

class DsToast {
  static OverlayEntry? _current;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    _timer?.cancel();
    _current?.remove();
    _current = null;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final ds = context.ds;
    final entry = OverlayEntry(
      builder: (ctx) {
        final topPad = MediaQuery.of(ctx).padding.top + 40;
        return Positioned(
          top: topPad,
          left: 24,
          right: 24,
          child: IgnorePointer(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: ds.toastBg,
                    borderRadius: BorderRadius.circular(12),
                    border: ds.isDark
                        ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isError) ...[
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: ds.errorSecondary,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _current = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () {
      entry.remove();
      if (_current == entry) _current = null;
    });
  }
}
