import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';
import '../common/file_widgets.dart';

/// Shared `< 1 / N >` branch switcher widget matching `BranchSwitcher.tsx`.
class DsBranchSwitcher extends StatelessWidget {
  final MessageVersionInfo version;
  final bool disabled;
  final void Function(String messageId) onSelect;

  const DsBranchSwitcher({
    super.key,
    required this.version,
    required this.disabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (!version.hasMultiple) return const SizedBox.shrink();
    final ds = context.ds;
    final hasPrev = version.index > 0;
    final hasNext = version.index + 1 < version.total;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BranchArrow(
          icon: Icons.chevron_left,
          enabled: !disabled && hasPrev,
          onTap: () => onSelect(version.ids[version.index - 1]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '${version.index + 1} / ${version.total}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ds.labelTertiary,
            ),
          ),
        ),
        _BranchArrow(
          icon: Icons.chevron_right,
          enabled: !disabled && hasNext,
          onTap: () => onSelect(version.ids[version.index + 1]),
        ),
      ],
    );
  }
}

class _BranchArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _BranchArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? ds.labelTertiary : ds.labelCaption.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// Right-aligned DeepSeek user message bubble matching `UserMessage.tsx`.
class UserMessageWidget extends StatefulWidget {
  final UserMessage message;
  final MessageVersionInfo? version;
  final bool busy;
  final AppStrings strings;
  final void Function(String newContent) onEdit;
  final void Function(String messageId) onSelectVersion;

  const UserMessageWidget({
    super.key,
    required this.message,
    required this.version,
    required this.busy,
    required this.strings,
    required this.onEdit,
    required this.onSelectVersion,
  });

  @override
  State<UserMessageWidget> createState() => _UserMessageWidgetState();
}

class _UserMessageWidgetState extends State<UserMessageWidget> {
  bool _editing = false;
  bool _copied = false;
  Timer? _copyTimer;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    _editController.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _startEdit() {
    _editController.text = widget.message.content;
    setState(() => _editing = true);
  }

  void _submitEdit() {
    final trimmed = _editController.text.trim();
    if (trimmed.isEmpty && widget.message.files.isEmpty) return;
    setState(() => _editing = false);
    widget.onEdit(trimmed);
  }

  void _previewImage(BuildContext context, FileAttachment file) {
    if (file.localPath == null) return;
    final f = File(file.localPath!);
    if (!f.existsSync()) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: Center(child: Image.file(f)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final files = widget.message.files;
    final imageOnly = files.isNotEmpty && files.every((f) => f.isImage);
    final imageSize = imageOnly ? 120.0 : 64.0;
    final screenW = MediaQuery.of(context).size.width;
    final maxBubbleW = screenW - 76;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (files.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final f in files)
                  if (f.isImage)
                    DsImageAttachmentTile(
                      file: f,
                      size: imageSize,
                      onTap: () => _previewImage(context, f),
                    )
                  else
                    DsFileCard(file: f),
              ],
            ),
            const SizedBox(height: 8),
          ],

          if (_editing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              decoration: BoxDecoration(
                color: ds.bgBase,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: ds.brandPrimary, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 44,
                      maxHeight: 180,
                    ),
                    child: TextField(
                      controller: _editController,
                      autofocus: true,
                      maxLines: null,
                      style: TextStyle(
                        fontSize: 16,
                        height: 24 / 16,
                        color: ds.labelPrimary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() => _editing = false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ds.labelPrimary,
                          side: BorderSide(color: ds.borderL2),
                          shape: const StadiumBorder(),
                          minimumSize: const Size(64, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: Text(widget.strings.cancel,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submitEdit,
                        style: FilledButton.styleFrom(
                          backgroundColor: ds.buttonPrimaryFill,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          minimumSize: const Size(64, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: Text(widget.strings.send,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else if (widget.message.content.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxWidth: maxBubbleW),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: ds.userBubble,
                borderRadius: BorderRadius.circular(22),
              ),
              child: SelectableText(
                widget.message.content,
                style: TextStyle(
                  fontSize: 16,
                  height: 24 / 16,
                  color: ds.labelPrimary,
                ),
              ),
            ),

          if (!_editing) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.version != null && widget.version!.hasMultiple) ...[
                  DsBranchSwitcher(
                    version: widget.version!,
                    disabled: widget.busy,
                    onSelect: widget.onSelectVersion,
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.message.content.isNotEmpty)
                  _TinyIconBtn(
                    svg: _copied ? DsIcons.check : DsIcons.copy,
                    color: ds.labelTertiary,
                    onTap: _copy,
                  ),
                const SizedBox(width: 4),
                _TinyIconBtn(
                  svg: DsIcons.edit,
                  color: widget.busy ? ds.labelCaption : ds.labelTertiary,
                  onTap: widget.busy ? null : _startEdit,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TinyIconBtn extends StatelessWidget {
  final String svg;
  final Color color;
  final VoidCallback? onTap;

  const _TinyIconBtn({
    required this.svg,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: DsIcons.svg(svg, size: 15, color: color),
      ),
    );
  }
}
