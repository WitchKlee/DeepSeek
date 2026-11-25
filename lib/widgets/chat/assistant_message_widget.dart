import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../providers/speech_provider.dart';
import '../../services/chat/reply_logic.dart';
import '../../services/chat/reply_view.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';
import '../common/ds_toast.dart';
import '../markdown/ds_markdown.dart';
import 'search_panel.dart';
import 'user_message_widget.dart';

/// Full-width DeepSeek assistant message matching `AssistantMessage.tsx` & `ReplyArea.tsx`.
class AssistantMessageWidget extends StatefulWidget {
  final AssistantMessage message;
  final MessageVersionInfo? version;
  final bool isLast;
  final bool busy;
  final AppStrings strings;
  final VoidCallback onRegenerate;
  final VoidCallback onContinue;
  final void Function(String messageId) onSelectVersion;
  final void Function(List<ReplySource> sources) onOpenSearchPanel;
  final VoidCallback onOpenApiKeySettings;

  const AssistantMessageWidget({
    super.key,
    required this.message,
    required this.version,
    required this.isLast,
    required this.busy,
    required this.strings,
    required this.onRegenerate,
    required this.onContinue,
    required this.onSelectVersion,
    required this.onOpenSearchPanel,
    required this.onOpenApiKeySettings,
  });

  @override
  State<AssistantMessageWidget> createState() => _AssistantMessageWidgetState();
}

class _AssistantMessageWidgetState extends State<AssistantMessageWidget> {
  bool _thinkingOpen = true;
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _thinkingHeaderTitle(ReplyView view, bool streaming, AppStrings s) {
    final hasAnswer = view.answer.trim().isNotEmpty;
    if (streaming && !hasAnswer) {
      if (view.steps.isNotEmpty) {
        final last = view.steps.last;
        if (last is SearchStep && last.status == StepStatus.wip) {
          return last.isImage ? s.searchingByImage : s.searchingWeb;
        }
        if (last is OpenStep && last.status == StepStatus.wip) {
          return s.browsingWeb;
        }
        if (last is ReadLinkStep && last.status == StepStatus.wip) {
          return s.readingLink;
        }
      }
      return s.thinking;
    }
    if (!streaming && !hasAnswer && widget.message.status == ReplyStatus.stopped) {
      return s.stopped;
    }
    final secs = getTotalThinkingSeconds(widget.message);
    if (secs != null) return s.thoughtForSeconds(secs);
    return s.deepThinkDoneFallback;
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final s = widget.strings;
    final msg = widget.message;
    final streaming = msg.isStreaming;
    final refused = msg.stopReason == 'refusal';
    final view = buildReplyView(msg);
    final notice = describeReply(msg, s);
    final speech = context.watch<SpeechProvider>();
    final ttsStatus = speech.statusForMessage(msg.id);

    final hasThinkHeader = !refused &&
        (msg.thinking || view.steps.any((st) => st is ThinkingStep));
    final showWaitingDots =
        streaming && view.steps.isEmpty && view.answer.isEmpty && !msg.thinking;

    final copyableText = view.answer.isNotEmpty
        ? view.answer.replaceAll(RegExp(r'\[citation:\d+\]'), '')
        : (notice?.text ?? '');
    final showContinue =
        !streaming && widget.isLast && canContinueReply(msg);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Thinking & Tool Timeline (ReplyArea)
          if (hasThinkHeader) ...[
            GestureDetector(
              onTap: () => setState(() => _thinkingOpen = !_thinkingOpen),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    DsIcons.svg(
                      DsIcons.think,
                      size: 16,
                      color: (!streaming &&
                              view.answer.isEmpty &&
                              msg.status == ReplyStatus.stopped)
                          ? ds.labelTertiary
                          : ds.brandPrimary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: _ShimmerText(
                        text: _thinkingHeaderTitle(view, streaming, s),
                        active: streaming && view.answer.trim().isEmpty,
                        style: TextStyle(
                          fontSize: 15,
                          height: 24 / 15,
                          fontWeight: FontWeight.w500,
                          color: ds.labelSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _thinkingOpen
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 18,
                      color: ds.labelTertiary,
                    ),
                  ],
                ),
              ),
            ),
            if (_thinkingOpen && view.steps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: _TimelineSteps(
                  steps: view.steps,
                  sources: view.sourcesByIndex,
                  allSearchResults: view.searchResults,
                  streaming: streaming,
                  strings: s,
                  onOpenSearchPanel: widget.onOpenSearchPanel,
                ),
              ),
          ] else if (!refused && view.steps.isNotEmpty) ...[
            // Standalone tool rows (Search / ReadLink without DeepThink)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TimelineSteps(
                steps: view.steps,
                sources: view.sourcesByIndex,
                allSearchResults: view.searchResults,
                streaming: streaming,
                strings: s,
                onOpenSearchPanel: widget.onOpenSearchPanel,
              ),
            ),
          ],

          // 2. Waiting dots
          if (showWaitingDots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: _WaitingDots(),
            ),

          // 3. Main Markdown Answer
          if (!refused && view.answer.isNotEmpty)
            DsMarkdown(
              data: view.answer,
              strings: s,
              isStreaming: streaming,
              sources: view.sourcesByIndex,
              onTapCitation: (src) => showCitationPreviewSheet(context, src),
            ),

          // 4. Template response (e.g. refusal) or Error Notice Banner
          if (!streaming && notice != null)
            if (notice.asResponse)
              DsMarkdown(
                data: notice.text,
                strings: s,
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: DsIcons.svg(
                        DsIcons.warning,
                        size: 14,
                        color: ds.errorPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            notice.text,
                            style: TextStyle(
                              fontSize: 14,
                              height: 22 / 14,
                              color: ds.errorPrimary,
                            ),
                          ),
                          if (notice.action == NoticeAction.apiKey)
                            GestureDetector(
                              onTap: widget.onOpenApiKeySettings,
                              child: Text(
                                s.changeApiKey,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 22 / 14,
                                  fontWeight: FontWeight.w500,
                                  color: ds.brandText,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            )
                          else if (notice.action == NoticeAction.topUp)
                            GestureDetector(
                              onTap: () => launchUrl(
                                Uri.parse('https://platform.deepseek.com/top_up'),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: Text(
                                s.topUp,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 22 / 14,
                                  fontWeight: FontWeight.w500,
                                  color: ds.brandText,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

          // 5. Search Summary Pill
          if (!streaming && !refused && view.searchResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => widget.onOpenSearchPanel(view.searchResults),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                    decoration: BoxDecoration(
                      color: ds.bgBase,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: ds.borderL2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DsSiteThumbnails(sources: view.searchResults, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          s.webPagesCount(view.searchResults.length),
                          style: TextStyle(
                            fontSize: 13,
                            color: ds.labelSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 6. Bottom Action Bar
          if (!streaming)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  if (widget.version != null && widget.version!.hasMultiple) ...[
                    DsBranchSwitcher(
                      version: widget.version!,
                      disabled: widget.busy,
                      onSelect: widget.onSelectVersion,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (copyableText.isNotEmpty)
                    _ActionIconBtn(
                      onTap: () => _copyText(copyableText),
                      child: DsIcons.svg(
                        _copied ? DsIcons.check : DsIcons.copy,
                        size: 16,
                        color: ds.labelTertiary,
                      ),
                    ),
                  if (view.answer.isNotEmpty && !refused)
                    _ActionIconBtn(
                      onTap: () => speech.toggleReadAloud(
                        messageId: msg.id,
                        text: copyableText,
                        onToast: (m) => DsToast.show(context, m, isError: true),
                        onNeedApiKey: widget.onOpenApiKeySettings,
                      ),
                      child: ttsStatus == ReadAloudStatus.idle
                          ? DsIcons.svg(
                              DsIcons.speaker,
                              size: 16,
                              color: ds.labelTertiary,
                            )
                          : _ReadingBars(
                              playing: ttsStatus == ReadAloudStatus.playing,
                            ),
                    ),
                  if (!refused)
                    _ActionIconBtn(
                      onTap: widget.busy ? null : widget.onRegenerate,
                      child: DsIcons.svg(
                        DsIcons.refresh,
                        size: 15,
                        color: widget.busy ? ds.labelCaption : ds.labelTertiary,
                      ),
                    ),
                  const Spacer(),
                  if (showContinue)
                    OutlinedButton(
                      onPressed: widget.busy ? null : widget.onContinue,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ds.labelPrimary,
                        side: BorderSide(color: ds.borderL2),
                        shape: const StadiumBorder(),
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(
                        s.continueGenerating,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionIconBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _ActionIconBtn({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thinking & Tool Timeline Steps (matching ReplyArea.tsx)
// ---------------------------------------------------------------------------

class _TimelineSteps extends StatelessWidget {
  final List<ReplyStep> steps;
  final Map<int, ReplySource> sources;
  final List<ReplySource> allSearchResults;
  final bool streaming;
  final AppStrings strings;
  final void Function(List<ReplySource>) onOpenSearchPanel;

  const _TimelineSteps({
    required this.steps,
    required this.sources,
    required this.allSearchResults,
    required this.streaming,
    required this.strings,
    required this.onOpenSearchPanel,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Stack(
      children: [
        if (steps.length > 1 || (steps.length == 1 && steps.first is ThinkingStep))
          Positioned(
            left: 7.5,
            top: 10,
            bottom: 10,
            child: Container(width: 1, color: ds.labelDimmed),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final step in steps) _buildStep(context, step),
          ],
        ),
      ],
    );
  }

  Widget _buildStep(BuildContext context, ReplyStep step) {
    final ds = context.ds;
    switch (step) {
      case ThinkingStep():
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5, top: 9, right: 12),
                child: _StepDot(active: step.active),
              ),
              Expanded(
                child: DsMarkdown(
                  data: step.markdown,
                  strings: strings,
                  isSmall: true,
                  disableLinks: true,
                  isStreaming: streaming,
                ),
              ),
            ],
          ),
        );

      case PreambleTextStep():
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5, top: 9, right: 12),
                child: _StepDot(active: false),
              ),
              Expanded(
                child: DsMarkdown(
                  data: step.markdown,
                  strings: strings,
                  isSmall: true,
                  sources: sources,
                  onTapCitation: (src) => showCitationPreviewSheet(context, src),
                ),
              ),
            ],
          ),
        );

      case SearchStep():
        return _SearchStepRow(
          step: step,
          strings: strings,
          onTapResults: step.results.isNotEmpty
              ? () => onOpenSearchPanel(
                    allSearchResults.isNotEmpty ? allSearchResults : step.results,
                  )
              : null,
        );

      case OpenStep():
        final shown = step.pages.take(5).toList();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 22,
                color: ds.bgBase,
                alignment: Alignment.center,
                child: DsIcons.svg(
                  DsIcons.browse,
                  size: 14,
                  color: ds.labelTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      strings.readPages(step.pages.length),
                      style: TextStyle(fontSize: 13, color: ds.labelTertiary),
                    ),
                    for (final page in shown)
                      GestureDetector(
                        onTap: () {
                          final u = Uri.tryParse(page.url);
                          if (u != null) {
                            launchUrl(u, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(
                          '${page.title} ↗',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: ds.labelSecondary,
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                          ),
                        ),
                      ),
                    if (step.pages.length > 5 && allSearchResults.isNotEmpty)
                      GestureDetector(
                        onTap: () => onOpenSearchPanel(allSearchResults),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ds.tagBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            strings.viewAll,
                            style: TextStyle(
                              fontSize: 12,
                              color: ds.labelSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case FindStep():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 22,
                color: ds.bgBase,
                alignment: Alignment.center,
                child: DsIcons.svg(
                  DsIcons.browse,
                  size: 14,
                  color: ds.labelTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      strings.findKeyword,
                      style: TextStyle(fontSize: 13, color: ds.labelTertiary),
                    ),
                    for (final item in step.items)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: ds.tagBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.pattern,
                          style: TextStyle(
                            fontSize: 12,
                            color: ds.labelSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case ReadLinkStep():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 22,
                color: ds.bgBase,
                alignment: Alignment.center,
                child: DsIcons.svg(
                  DsIcons.link,
                  size: 14,
                  color: ds.labelTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ShimmerText(
                  text:
                      '${strings.readingLink} ${step.pages.map((p) => p.title).join(', ')}',
                  active: true,
                  style: TextStyle(fontSize: 13, color: ds.labelTertiary),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _SearchStepRow extends StatelessWidget {
  final SearchStep step;
  final AppStrings strings;
  final VoidCallback? onTapResults;

  const _SearchStepRow({
    required this.step,
    required this.strings,
    this.onTapResults,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    String label;
    if (step.status == StepStatus.wip) {
      if (step.isImage) {
        label = strings.searchingByImage;
      } else if (step.queries.isNotEmpty) {
        label = '${strings.searchingFor} ${step.queries.last}';
      } else {
        label = strings.searchingEllipsis;
      }
    } else if (step.status == StepStatus.failed) {
      label = strings.searchUnavailable;
    } else if (step.results.isEmpty) {
      label = step.isDeep
          ? strings.noSuitableResults
          : strings.noRelevantResults;
    } else {
      label = step.isDeep
          ? strings.foundWebPages(step.results.length)
          : strings.readWebPages(step.results.length);
    }

    return GestureDetector(
      onTap: onTapResults,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 20,
              color: ds.bgBase,
              alignment: Alignment.center,
              child: DsIcons.svg(
                DsIcons.search,
                size: 14,
                color: step.status == StepStatus.failed
                    ? ds.errorSecondary
                    : ds.labelTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: _ShimmerText(
                text: label,
                active: step.status == StepStatus.wip,
                style: TextStyle(
                  fontSize: 13,
                  color: ds.labelSecondary,
                ),
              ),
            ),
            if (step.status == StepStatus.done && step.results.isNotEmpty) ...[
              const SizedBox(width: 8),
              DsSiteThumbnails(sources: step.results, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatefulWidget {
  final bool active;
  const _StepDot({required this.active});

  @override
  State<_StepDot> createState() => _StepDotState();
}

class _StepDotState extends State<_StepDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StepDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    if (!widget.active) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: ds.labelTertiary,
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: 1.0 + _ctrl.value * 0.35,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: ds.brandPrimary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _ShimmerText extends StatefulWidget {
  final String text;
  final bool active;
  final TextStyle style;

  const _ShimmerText({
    required this.text,
    required this.active,
    required this.style,
  });

  @override
  State<_ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<_ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _ShimmerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }
    final baseColor = widget.style.color ?? context.ds.labelSecondary;
    final highlightColor = context.ds.labelPrimary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final pos = _ctrl.value * 2 - 0.5;
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [
              (pos - 0.25).clamp(0.0, 1.0),
              pos.clamp(0.0, 1.0),
              (pos + 0.25).clamp(0.0, 1.0),
            ],
            colors: [baseColor, highlightColor, baseColor],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style.copyWith(color: Colors.white),
          ),
        );
      },
    );
  }
}

class _WaitingDots extends StatefulWidget {
  const _WaitingDots();

  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: ds.labelTertiary.withValues(
                    alpha: 0.25 +
                        0.75 *
                            (((1 - ((_ctrl.value - i * 0.15) % 1.0).abs())
                                .clamp(0.0, 1.0))),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 4 animated vertical bars matching `ReadingBars.tsx` for TTS loading & playing states.
class _ReadingBars extends StatefulWidget {
  final bool playing;
  const _ReadingBars({required this.playing});

  @override
  State<_ReadingBars> createState() => _ReadingBarsState();
}

class _ReadingBarsState extends State<_ReadingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return SizedBox(
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                _buildBar(i, ds),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBar(int index, DsColors ds) {
    final phase = (_ctrl.value + index * 0.25) % 1.0;
    final wave = (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
    if (widget.playing) {
      return Container(
        width: 2,
        height: 4 + wave * 10,
        decoration: BoxDecoration(
          color: ds.brandPrimary,
          borderRadius: BorderRadius.circular(1),
        ),
      );
    }
    return Container(
      width: 2,
      height: 4,
      decoration: BoxDecoration(
        color: ds.labelTertiary.withValues(alpha: 0.35 + wave * 0.65),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
