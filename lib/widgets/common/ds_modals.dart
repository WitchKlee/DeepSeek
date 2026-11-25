import 'package:flutter/material.dart';

import '../../theme/ds_theme.dart';

/// DeepSeek confirmation dialog (`border-radius: 24px`, pill buttons).
Future<bool> showDsConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String cancelText,
  required String confirmText,
  bool danger = false,
  bool dangerOutlined = false,
}) async {
  final ds = context.ds;
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: ds.isDark ? 0.60 : 0.36),
    builder: (ctx) {
      final c = ctx.ds;
      return Dialog(
        backgroundColor: c.bgLayer2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: c.isDark
              ? BorderSide(color: Colors.white.withValues(alpha: 0.06))
              : BorderSide.none,
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  height: 24 / 17,
                  fontWeight: FontWeight.w600,
                  color: c.labelPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  color: c.labelSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.labelPrimary,
                      side: BorderSide(color: c.borderL2),
                      shape: const StadiumBorder(),
                      minimumSize: const Size(76, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text(
                      cancelText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (dangerOutlined)
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.errorPrimary,
                        side: BorderSide(color: c.errorPrimary),
                        shape: const StadiumBorder(),
                        minimumSize: const Size(76, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: Text(
                        confirmText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            danger ? c.errorPrimary : c.buttonPrimaryFill,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        minimumSize: const Size(76, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: Text(
                        confirmText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
