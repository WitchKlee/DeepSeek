import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';

/// 60px mobile header matching `MobileHeader.tsx`:
/// - Welcome state (`showSessionControls == false`): left menu button only.
/// - Active session: left menu button + single-line title + right new chat button.
class MobileHeader extends StatelessWidget {
  final String? title;
  final bool showSessionControls;
  final AppStrings strings;
  final VoidCallback onOpenDrawer;
  final VoidCallback onNewChat;

  const MobileHeader({
    super.key,
    required this.title,
    required this.showSessionControls,
    required this.strings,
    required this.onOpenDrawer,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final displayTitle =
        (title == null || title!.trim().isEmpty) ? strings.untitledChat : title!;

    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      color: ds.bgBase,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: onOpenDrawer,
              padding: EdgeInsets.zero,
              icon: DsIcons.svg(
                DsIcons.menu,
                size: 20,
                color: ds.labelPrimary,
              ),
            ),
          ),
          if (showSessionControls) ...[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 22 / 15,
                    fontWeight: FontWeight.w500,
                    color: ds.labelPrimary,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: onNewChat,
                padding: EdgeInsets.zero,
                icon: DsIcons.svg(
                  DsIcons.newChat,
                  size: 20,
                  color: ds.labelPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
