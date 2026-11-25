import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/speech_provider.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';
import '../common/ds_toast.dart';
import '../common/file_widgets.dart';

/// DeepSeek 24px rounded chat input composer matching `ChatInput.tsx`,
/// `DraftAttachments.tsx`, `VoiceButton.tsx`, and `Spectrum.tsx`.
class ChatComposer extends StatefulWidget {
  final bool isWelcome;
  final VoidCallback onNeedApiKey;

  const ChatComposer({
    super.key,
    required this.isWelcome,
    required this.onNeedApiKey,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  late final AnimationController _haloAnim;
  String? _lastSessionKey;

  @override
  void initState() {
    super.initState();
    _haloAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      context.read<ChatProvider>().setDraftText(_controller.text);
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = context.read<ChatProvider>();
    final key = chat.activeSession?.id ?? '';
    if (_lastSessionKey != key) {
      _lastSessionKey = key;
      final saved = chat.currentDraftText;
      if (_controller.text != saved) {
        _controller.text = saved;
        _controller.selection = TextSelection.collapsed(offset: saved.length);
      }
    }
  }

  @override
  void dispose() {
    _haloAnim.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _insertTextAtCursor(String text) {
    final current = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : current.length;
    final end = sel.isValid ? sel.end : current.length;
    final updated = current.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  Future<void> _handleSend() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.hasApiKey) {
      widget.onNeedApiKey();
      return;
    }

    final chat = context.read<ChatProvider>();
    if (chat.hasUploadingDrafts) {
      DsToast.show(context, settings.strings.waitUploads);
      return;
    }
    if (chat.hasFailedDrafts) {
      DsToast.show(context, settings.strings.uploadFailed, isError: true);
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty && chat.currentDraftAttachments.isEmpty) return;

    await context.read<SpeechProvider>().stopReadAloud();
    _focusNode.unfocus();
    _controller.clear();
    await chat.sendMessage(text);
  }

  Future<void> _showAttachmentSheet() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.hasApiKey) {
      widget.onNeedApiKey();
      return;
    }
    final s = settings.strings;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PickerOption(
                icon: Icons.photo_library_outlined,
                label: s.pickImage,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickGalleryImages();
                },
              ),
              _PickerOption(
                icon: Icons.camera_alt_outlined,
                label: s.takePhoto,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickCameraPhoto();
                },
              ),
              _PickerOption(
                icon: Icons.folder_open_outlined,
                label: s.pickFile,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickGalleryImages() async {
    try {
      final images = await _imagePicker.pickMultiImage();
      if (images.isEmpty || !mounted) return;
      final items = <({String name, Uint8List bytes, String? mimeType})>[];
      for (final x in images) {
        final bytes = await x.readAsBytes();
        items.add((name: x.name, bytes: bytes, mimeType: x.mimeType));
      }
      if (!mounted) return;
      final err = await context.read<ChatProvider>().addDraftFiles(items);
      if (err != null && mounted) {
        DsToast.show(context, err, isError: true);
      }
    } catch (_) {}
  }

  Future<void> _pickCameraPhoto() async {
    try {
      final photo = await _imagePicker.pickImage(source: ImageSource.camera);
      if (photo == null || !mounted) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      final err = await context.read<ChatProvider>().addDraftFiles([
        (name: photo.name, bytes: bytes, mimeType: photo.mimeType),
      ]);
      if (err != null && mounted) {
        DsToast.show(context, err, isError: true);
      }
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty || !mounted) return;
      final picked = <({String name, Uint8List bytes, String? mimeType})>[];
      for (final f in files) {
        final bytes = await f.readAsBytes();
        picked.add((name: f.name, bytes: bytes, mimeType: null));
      }
      if (picked.isEmpty || !mounted) return;
      final err = await context.read<ChatProvider>().addDraftFiles(picked);
      if (err != null && mounted) {
        DsToast.show(context, err, isError: true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final settingsProv = context.watch<SettingsProvider>();
    final settings = settingsProv.settings;
    final s = settingsProv.strings;
    final chat = context.watch<ChatProvider>();
    final speech = context.watch<SpeechProvider>();

    final drafts = chat.currentDraftAttachments;
    final isStreaming = chat.isActiveSessionStreaming;
    final isRecording = speech.voiceStatus == VoiceInputStatus.recording;
    final isTranscribing = speech.voiceStatus == VoiceInputStatus.transcribing;

    final canSend = !isStreaming &&
        !speech.isVoiceBusy &&
        !chat.hasUploadingDrafts &&
        !chat.hasFailedDrafts &&
        (_controller.text.trim().isNotEmpty || drafts.isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: ds.inputMajor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ds.borderL2Thin),
        boxShadow: ds.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: widget.isWelcome ? 16 : 10,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: const Color(0xFF4868B2).withValues(alpha: 0.03),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Draft attachments horizontal strip
          if (drafts.isNotEmpty)
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
                itemCount: drafts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final d = drafts[i];
                  if (d.file.isImage) {
                    return DsImageAttachmentTile(
                      file: d.file,
                      size: 64,
                      uploadStatus: d.status,
                      errorMessage: d.errorMessage,
                      retryable: d.retryable,
                      onRemove: () => chat.removeDraftAttachment(d.file.id),
                      onRetry: () => chat.retryDraftAttachment(d.file.id),
                    );
                  }
                  return DsFileCard(
                    file: d.file,
                    uploadStatus: d.status,
                    errorMessage: d.errorMessage,
                    retryable: d.retryable,
                    onRemove: () => chat.removeDraftAttachment(d.file.id),
                    onRetry: () => chat.retryDraftAttachment(d.file.id),
                  );
                },
              ),
            ),

          // Multiline text input OR Live Audio Spectrum overlay
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: isRecording ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: isRecording,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 42,
                        maxHeight: 160,
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(
                          fontSize: 16,
                          height: 24 / 16,
                          color: ds.labelPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: s.inputPlaceholder,
                          hintStyle: TextStyle(
                            fontSize: 16,
                            height: 24 / 16,
                            color: ds.labelCaption,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.only(bottom: 4),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isRecording)
                  _LiveSpectrumBar(
                    bars: speech.spectrumBars,
                    seconds: speech.recordingSeconds,
                  ),
              ],
            ),
          ),

          // Bottom function row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final compact = constraints.maxWidth < 310;
                return Row(
                  children: [
                    // DeepThink toggle chip
                    _ModeToggleChip(
                      iconSvg: DsIcons.think,
                      label: compact ? null : s.deepThink,
                      active: settings.thinking,
                      onTap: () => settingsProv.setThinking(!settings.thinking),
                    ),
                    const SizedBox(width: 8),
                    // Smart Search toggle chip
                    _ModeToggleChip(
                      iconSvg: DsIcons.globe,
                      label: compact ? null : s.smartSearch,
                      active: settings.search,
                      onTap: () => settingsProv.setSearch(!settings.search),
                    ),
                    const Spacer(),

                    // Voice Input Button (ASR)
                    _VoiceInputButton(
                      status: speech.voiceStatus,
                      haloAnimation: _haloAnim,
                      onTap: () => speech.toggleVoiceInput(
                        onTranscribed: _insertTextAtCursor,
                        onToast: (msg) =>
                            DsToast.show(context, msg, isError: true),
                        onNeedApiKey: widget.onNeedApiKey,
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Attachment Picker Button
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: IconButton(
                        onPressed:
                            isRecording || isTranscribing ? null : _showAttachmentSheet,
                        padding: EdgeInsets.zero,
                        icon: DsIcons.svg(
                          DsIcons.paperclip,
                          size: 17,
                          color: (isRecording || isTranscribing)
                              ? ds.labelCaption
                              : ds.labelPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Send / Stop circle button
                    GestureDetector(
                      onTap: isStreaming
                          ? () {
                              chat.stopStreaming();
                              speech.stopReadAloud();
                            }
                          : (canSend ? _handleSend : null),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: (isStreaming || canSend) ? 1.0 : 0.4,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: ds.buttonPrimaryFill,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: DsIcons.svg(
                            isStreaming ? DsIcons.stop : DsIcons.send,
                            size: isStreaming ? 14 : 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggleChip extends StatelessWidget {
  final String iconSvg;
  final String? label;
  final bool active;
  final VoidCallback onTap;

  const _ModeToggleChip({
    required this.iconSvg,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 12),
        decoration: BoxDecoration(
          color: active ? ds.ghostActiveFill : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? ds.ghostActiveBorder : ds.borderL2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsIcons.svg(
              iconSvg,
              size: 14,
              color: active ? ds.brandText : ds.labelPrimary,
            ),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(
                label!,
                style: TextStyle(
                  fontSize: 13,
                  height: 20 / 13,
                  fontWeight: FontWeight.w500,
                  color: active ? ds.brandText : ds.labelPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceInputButton extends StatelessWidget {
  final VoiceInputStatus status;
  final Animation<double> haloAnimation;
  final VoidCallback onTap;

  const _VoiceInputButton({
    required this.status,
    required this.haloAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;

    if (status == VoiceInputStatus.transcribing) {
      return GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ds.brandPrimary,
              ),
            ),
          ),
        ),
      );
    }

    if (status == VoiceInputStatus.recording) {
      return GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: AnimatedBuilder(
            animation: haloAnimation,
            builder: (_, __) {
              final scale = 1.0 + haloAnimation.value * 0.14;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: ds.brandPrimary.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ds.brandPrimary.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: DsIcons.svg(
                      DsIcons.micFill,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: DsIcons.svg(
          DsIcons.mic,
          size: 16,
          color: ds.labelPrimary,
        ),
      ),
    );
  }
}

/// Live frequency spectrum bar matching `Spectrum.tsx` (`#679EFE`, height 5..36px).
class _LiveSpectrumBar extends StatelessWidget {
  final List<double> bars;
  final double seconds;

  const _LiveSpectrumBar({required this.bars, required this.seconds});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final count = min(bars.length, (constraints.maxWidth / 5).floor())
                    .clamp(8, 40);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < count; i++)
                      Container(
                        width: 2.2,
                        height: 5 + bars[i % bars.length] * 31,
                        margin: const EdgeInsets.symmetric(horizontal: 1.4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF679EFE).withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(1.1),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${seconds.floor()}s',
            style: TextStyle(
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ds.labelTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: ds.selectorFill,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: ds.labelPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: ds.labelPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
