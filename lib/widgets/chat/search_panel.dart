import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';

String? _formatSourceDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final dt = DateTime.tryParse(raw);
  if (dt != null) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }
  return raw.length > 16 ? raw.substring(0, 16) : raw;
}

/// Circular 16/18px site favicon with fallback link icon.
class DsSiteLogo extends StatelessWidget {
  final String? iconUrl;
  final double size;

  const DsSiteLogo({super.key, this.iconUrl, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ds.citationHoverBg,
        shape: BoxShape.circle,
        border: Border.all(color: ds.bgBase, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: (iconUrl != null && iconUrl!.startsWith('http'))
          ? Image.network(
              iconUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => DsIcons.svg(
                DsIcons.link,
                size: size * 0.6,
                color: ds.labelTertiary,
              ),
            )
          : DsIcons.svg(
              DsIcons.link,
              size: size * 0.6,
              color: ds.labelTertiary,
            ),
    );
  }
}

/// Up to 4 overlapping circular 16x16 site favicons (`SiteThumbnails`).
class DsSiteThumbnails extends StatelessWidget {
  final List<ReplySource> sources;
  final double size;

  const DsSiteThumbnails({
    super.key,
    required this.sources,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final items = sources.take(4).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final step = size - 4;
    final totalW = size + (items.length - 1) * step;

    return SizedBox(
      width: totalW,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * step,
              child: DsSiteLogo(iconUrl: items[i].siteIcon, size: size),
            ),
        ],
      ),
    );
  }
}

/// Full-screen search results panel (`SearchPanel.tsx`).
class SearchResultsSheet extends StatelessWidget {
  final List<ReplySource> sources;
  final AppStrings strings;
  final VoidCallback onClose;

  const SearchResultsSheet({
    super.key,
    required this.sources,
    required this.strings,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Material(
      color: ds.bgBase,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ds.borderL2)),
              ),
              child: Row(
                children: [
                  Text(
                    strings.searchResults,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ds.labelPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: DsIcons.svg(
                      DsIcons.close,
                      size: 16,
                      color: ds.labelSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (ctx, i) => _SourceCard(source: sources[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final ReplySource source;

  const _SourceCard({required this.source});

  Future<void> _open() async {
    final uri = Uri.tryParse(source.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final dateStr = _formatSourceDate(source.publishedAt);

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: ds.bgBase,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DsSiteLogo(iconUrl: source.siteIcon, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    source.siteName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: ds.labelTertiary,
                    ),
                  ),
                ),
                if (dateStr != null) ...[
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: ds.borderL2,
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: ds.labelTertiary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              source.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 21 / 14,
                fontWeight: FontWeight.w500,
                color: ds.labelPrimary,
              ),
            ),
            if (source.snippet.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                source.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 19 / 13,
                  color: ds.labelTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact citation preview bottom sheet shown when tapping an inline `[citation:N]` badge.
void showCitationPreviewSheet(BuildContext context, ReplySource source) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: _SourceCard(source: source),
      ),
    ),
  );
}
