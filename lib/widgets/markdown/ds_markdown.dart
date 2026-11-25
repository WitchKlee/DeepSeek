import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';
import '../../theme/ds_icons.dart';
import '../../theme/ds_theme.dart';

/// DeepSeek custom Markdown renderer matching `chat-demo/src/services/markdown/*`:
/// - Disables 4-space indented code blocks (prevents accidental LLM code blocks)
/// - Disables `~` strikethrough (prevents `10~20` breaking)
/// - Soft line breaks render as visual breaks
/// - Supports `$...$`, `$$...$$`, `\(...\)`, `\[...\]` via `flutter_math_fork`
/// - Inline `[citation:N]` teardrop pills linked to [sources]
/// - Syntax-highlighted CodeBlock with DeepSeek Light/Dark themes + Copy button
/// - MermaidDiagram with Diagram|Code toggle + WebView SVG rendering
/// - GFM tables (horizontally scrollable) & task lists (`☑` / `□`)
class DsMarkdown extends StatelessWidget {
  final String data;
  final bool isSmall; // true inside Thinking block (14/24, secondary color)
  final bool disableLinks;
  final bool isStreaming;
  final Map<int, ReplySource> sources;
  final AppStrings strings;
  final void Function(ReplySource source)? onTapCitation;

  const DsMarkdown({
    super.key,
    required this.data,
    required this.strings,
    this.isSmall = false,
    this.disableLinks = false,
    this.isStreaming = false,
    this.sources = const {},
    this.onTapCitation,
  });

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) return const SizedBox.shrink();

    final normalized = _preprocessMathBlocks(data);
    final document = md.Document(
      encodeHtml: false,
      blockSyntaxes: [
        const _BlockMathSyntax(),
        const md.FencedCodeBlockSyntax(),
        const md.HeaderSyntax(),
        const md.BlockquoteSyntax(),
        const md.HorizontalRuleSyntax(),
        const md.TableSyntax(),
        const md.UnorderedListWithCheckboxSyntax(),
        const md.OrderedListWithCheckboxSyntax(),
        const md.UnorderedListSyntax(),
        const md.OrderedListSyntax(),
        // Intentionally omit CodeBlockSyntax (4-space indent) matching chat-demo!
      ],
      inlineSyntaxes: [
        _CitationSyntax(),
        _InlineMathSyntax(),
        md.CodeSyntax(),
        md.AutolinkExtensionSyntax(),
        md.LinkSyntax(),
        md.ImageSyntax(),
        md.EmphasisSyntax.asterisk(),
        md.EmphasisSyntax.underscore(),
        md.LineBreakSyntax(),
        // Intentionally omit StrikethroughSyntax matching chat-demo!
      ],
    );

    final nodes = document.parse(normalized);
    return _BlockListWidget(
      nodes: nodes,
      isSmall: isSmall,
      disableLinks: disableLinks,
      isStreaming: isStreaming,
      sources: sources,
      strings: strings,
      onTapCitation: onTapCitation,
    );
  }

  /// Normalizes `\[ ... \]` display math into `$$ ... $$` on its own lines
  /// while leaving fenced code blocks untouched.
  String _preprocessMathBlocks(String input) {
    final lines = input.split('\n');
    final out = StringBuffer();
    var inFence = false;
    var fenceMarker = '';

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (!inFence && (trimmed.startsWith('```') || trimmed.startsWith('~~~'))) {
        inFence = true;
        fenceMarker = trimmed.substring(0, 3);
        out.writeln(line);
        continue;
      } else if (inFence && trimmed.startsWith(fenceMarker)) {
        inFence = false;
        out.writeln(line);
        continue;
      }
      if (inFence) {
        out.writeln(line);
        continue;
      }
      // Replace standalone \[ and \] with $$
      var processed = line;
      if (trimmed == r'\[') {
        processed = r'$$';
      } else if (trimmed == r'\]') {
        processed = r'$$';
      } else {
        processed = processed.replaceAllMapped(
          RegExp(r'\\\[(.+?)\\\]'),
          (m) => '\n\$\$\n${m.group(1)!.trim()}\n\$\$\n',
        );
      }
      out.writeln(processed);
    }
    return out.toString();
  }
}

// ---------------------------------------------------------------------------
// Custom Markdown Syntaxes (Block Math, Inline Math, Citations)
// ---------------------------------------------------------------------------

class _BlockMathSyntax extends md.BlockSyntax {
  const _BlockMathSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  md.Node? parse(md.BlockParser parser) {
    final firstLine = parser.current.content.trim();
    // Single-line $$ ... $$
    if (firstLine.length > 4 &&
        firstLine.startsWith(r'$$') &&
        firstLine.endsWith(r'$$')) {
      final tex = firstLine.substring(2, firstLine.length - 2).trim();
      parser.advance();
      return md.Element.text('math_block', tex);
    }

    final buf = StringBuffer();
    final restOfFirst = firstLine.substring(2);
    if (restOfFirst.trim().isNotEmpty) {
      buf.writeln(restOfFirst);
    }
    parser.advance();

    while (!parser.isDone) {
      final line = parser.current.content;
      final endIdx = line.indexOf(r'$$');
      if (endIdx != -1) {
        final before = line.substring(0, endIdx);
        if (before.trim().isNotEmpty) buf.writeln(before);
        parser.advance();
        break;
      }
      buf.writeln(line);
      parser.advance();
    }
    return md.Element.text('math_block', buf.toString().trim());
  }
}

class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax()
      : super(r'(?:\\\((.+?)\\\))|(?:\$\$(.+?)\$\$)|(?:\$([^\$\n]+?)\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final paren = match.group(1);
    final dbl = match.group(2);
    final single = match.group(3);
    if (dbl != null) {
      parser.addNode(md.Element.text('math_inline', dbl.trim()));
      return true;
    }
    final tex = (paren ?? single ?? '').trim();
    if (tex.isEmpty) return false;
    parser.addNode(md.Element.text('math_inline', tex));
    return true;
  }
}

class _CitationSyntax extends md.InlineSyntax {
  _CitationSyntax() : super(r'\[citation:(\d+)\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final idx = match.group(1);
    if (idx == null) return false;
    parser.addNode(md.Element.text('citation', idx));
    return true;
  }
}

// ---------------------------------------------------------------------------
// Block Renderer
// ---------------------------------------------------------------------------

class _BlockListWidget extends StatelessWidget {
  final List<md.Node> nodes;
  final bool isSmall;
  final bool disableLinks;
  final bool isStreaming;
  final Map<int, ReplySource> sources;
  final AppStrings strings;
  final void Function(ReplySource source)? onTapCitation;

  const _BlockListWidget({
    required this.nodes,
    required this.isSmall,
    required this.disableLinks,
    required this.isStreaming,
    required this.sources,
    required this.strings,
    this.onTapCitation,
  });

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      final w = _buildBlock(context, nodes[i], i == 0);
      if (w != null) widgets.add(w);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget? _buildBlock(BuildContext context, md.Node node, bool isFirst) {
    final ds = context.ds;
    final baseStyle = TextStyle(
      fontSize: isSmall ? 14 : 16,
      height: isSmall ? 24 / 14 : 28 / 16,
      color: isSmall ? ds.labelSecondary : ds.labelPrimary,
      fontWeight: FontWeight.w400,
    );

    if (node is md.Text) {
      if (node.text.trim().isEmpty) return null;
      return SelectableText(node.text, style: baseStyle);
    }

    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final headingStyle = _headingStyle(node.tag, ds);
        final topPad = isFirst
            ? 0.0
            : (isSmall
                ? 10.0
                : (node.tag == 'h1' || node.tag == 'h2' || node.tag == 'h3'
                    ? 24.0
                    : 14.0));
        return Padding(
          padding: EdgeInsets.only(top: topPad, bottom: isSmall ? 6 : 10),
          child: _buildRichText(context, node.children ?? const [], headingStyle),
        );

      case 'p':
        return Padding(
          padding: EdgeInsets.only(
            top: isFirst ? 0 : (isSmall ? 6 : 8),
            bottom: isSmall ? 6 : 8,
          ),
          child: _buildRichText(context, node.children ?? const [], baseStyle),
        );

      case 'math_block':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _MathFormulaWidget(
            tex: node.textContent,
            displayMode: true,
            textStyle: baseStyle,
          ),
        );

      case 'pre':
        String code = node.textContent;
        String lang = '';
        if (node.children != null && node.children!.isNotEmpty) {
          final child = node.children!.first;
          if (child is md.Element && child.tag == 'code') {
            code = child.textContent;
            final cls = child.attributes['class'] ?? '';
            if (cls.startsWith('language-')) {
              lang = cls.substring('language-'.length).trim();
            }
          }
        }
        if (code.endsWith('\n')) {
          code = code.substring(0, code.length - 1);
        }
        if (lang.toLowerCase() == 'mermaid') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _MermaidCodeBlock(
              code: code,
              isStreaming: isStreaming,
              strings: strings,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _DsCodeBlock(
            code: code,
            language: lang,
            strings: strings,
          ),
        );

      case 'blockquote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: ds.labelCaption, width: 2),
            ),
          ),
          child: _BlockListWidget(
            nodes: node.children ?? const [],
            isSmall: isSmall,
            disableLinks: disableLinks,
            isStreaming: isStreaming,
            sources: sources,
            strings: strings,
            onTapCitation: onTapCitation,
          ),
        );

      case 'ul':
      case 'ol':
        final ordered = node.tag == 'ol';
        final start = int.tryParse(node.attributes['start'] ?? '1') ?? 1;
        final items = (node.children ?? const []).whereType<md.Element>().toList();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                _buildListItem(context, items[i], ordered, start + i, baseStyle),
            ],
          ),
        );

      case 'hr':
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 24),
          color: ds.borderL2,
        );

      case 'table':
        return _buildTable(context, node, ds);

      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildRichText(context, node.children ?? const [], baseStyle),
        );
    }
  }

  TextStyle _headingStyle(String tag, DsColors ds) {
    if (isSmall) {
      return TextStyle(
        fontSize: 14,
        height: 24 / 14,
        fontWeight: FontWeight.w600,
        color: ds.labelSecondary,
      );
    }
    switch (tag) {
      case 'h1':
        return TextStyle(
          fontSize: 22,
          height: 32 / 22,
          fontWeight: FontWeight.w700,
          color: ds.labelPrimary,
        );
      case 'h2':
        return TextStyle(
          fontSize: 20,
          height: 30 / 20,
          fontWeight: FontWeight.w700,
          color: ds.labelPrimary,
        );
      case 'h3':
        return TextStyle(
          fontSize: 18,
          height: 28 / 18,
          fontWeight: FontWeight.w700,
          color: ds.labelPrimary,
        );
      default:
        return TextStyle(
          fontSize: 16,
          height: 28 / 16,
          fontWeight: FontWeight.w600,
          color: ds.labelPrimary,
        );
    }
  }

  Widget _buildListItem(
    BuildContext context,
    md.Element item,
    bool ordered,
    int number,
    TextStyle baseStyle,
  ) {
    final ds = context.ds;
    final children = item.children ?? const [];
    bool? checked;
    final filtered = <md.Node>[];

    for (final c in children) {
      if (c is md.Element && c.tag == 'input' && c.attributes['type'] == 'checkbox') {
        checked = c.attributes.containsKey('checked');
      } else {
        filtered.add(c);
      }
    }

    final bullet = checked != null
        ? (checked ? '☑' : '□')
        : (ordered ? '$number.' : '•');

    // Separate inline children from nested block children
    final hasBlockChildren = filtered.any(
      (n) =>
          n is md.Element &&
          const {'p', 'ul', 'ol', 'pre', 'blockquote', 'table', 'math_block'}
              .contains(n.tag),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ordered ? 26 : 20,
            child: Text(
              bullet,
              style: baseStyle.copyWith(
                color: checked != null ? ds.labelSecondary : baseStyle.color,
                fontWeight: ordered ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            child: hasBlockChildren
                ? _BlockListWidget(
                    nodes: filtered,
                    isSmall: isSmall,
                    disableLinks: disableLinks,
                    isStreaming: isStreaming,
                    sources: sources,
                    strings: strings,
                    onTapCitation: onTapCitation,
                  )
                : _buildRichText(context, filtered, baseStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, md.Element table, DsColors ds) {
    final headRows = <List<md.Element>>[];
    final bodyRows = <List<md.Element>>[];

    for (final section in (table.children ?? const []).whereType<md.Element>()) {
      final rows = (section.children ?? const []).whereType<md.Element>();
      for (final tr in rows) {
        final cells = (tr.children ?? const []).whereType<md.Element>().toList();
        if (section.tag == 'thead') {
          headRows.add(cells);
        } else {
          bodyRows.add(cells);
        }
      }
    }

    var colCount = 0;
    for (final r in [...headRows, ...bodyRows]) {
      if (r.length > colCount) colCount = r.length;
    }
    if (colCount == 0) return const SizedBox.shrink();

    final headStyle = TextStyle(
      fontSize: 15,
      height: 24 / 15,
      fontWeight: FontWeight.w600,
      color: ds.labelPrimary,
    );
    final cellStyle = TextStyle(
      fontSize: 15,
      height: 24 / 15,
      fontWeight: FontWeight.w400,
      color: ds.labelPrimary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            horizontalInside: BorderSide(color: ds.borderL2, width: 1),
            bottom: BorderSide(color: ds.borderL2, width: 1),
          ),
          children: [
            for (final row in headRows)
              TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: ds.borderL3, width: 1),
                  ),
                ),
                children: [
                  for (var c = 0; c < colCount; c++)
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 88,
                        maxWidth: 260,
                      ),
                      padding: EdgeInsets.fromLTRB(c == 0 ? 0 : 14, 10, 14, 10),
                      child: c < row.length
                          ? _buildRichText(
                              context,
                              row[c].children ?? const [],
                              headStyle,
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            for (final row in bodyRows)
              TableRow(
                children: [
                  for (var c = 0; c < colCount; c++)
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 88,
                        maxWidth: 260,
                      ),
                      padding: EdgeInsets.fromLTRB(c == 0 ? 0 : 14, 10, 14, 10),
                      child: c < row.length
                          ? _buildRichText(
                              context,
                              row[c].children ?? const [],
                              cellStyle,
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRichText(
    BuildContext context,
    List<md.Node> nodes,
    TextStyle baseStyle,
  ) {
    final spans = _buildSpans(context, nodes, baseStyle);
    return Text.rich(TextSpan(children: spans, style: baseStyle));
  }

  List<InlineSpan> _buildSpans(
    BuildContext context,
    List<md.Node> nodes,
    TextStyle style,
  ) {
    final ds = context.ds;
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: style));
        continue;
      }
      if (node is! md.Element) continue;

      switch (node.tag) {
        case 'strong':
          spans.addAll(_buildSpans(
            context,
            node.children ?? const [],
            style.copyWith(fontWeight: FontWeight.w600),
          ));
          break;
        case 'em':
          spans.addAll(_buildSpans(
            context,
            node.children ?? const [],
            style.copyWith(fontStyle: FontStyle.italic),
          ));
          break;
        case 'br':
          spans.add(const TextSpan(text: '\n'));
          break;
        case 'code':
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: ds.inlineCodeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                node.textContent,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: (style.fontSize ?? 16) * 0.875,
                  height: 1.35,
                  color: style.color,
                ),
              ),
            ),
          ));
          break;
        case 'math_inline':
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _MathFormulaWidget(
              tex: node.textContent,
              displayMode: false,
              textStyle: style,
            ),
          ));
          break;
        case 'citation':
          final idx = int.tryParse(node.textContent);
          final src = idx == null ? null : sources[idx];
          if (idx != null && src != null) {
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 2, right: 1),
                child: GestureDetector(
                  onTap: () {
                    if (onTapCitation != null) {
                      onTapCitation!(src);
                    } else {
                      _launchUrlSafe(src.url);
                    }
                  },
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: ds.citationBg,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: Text(
                      '$idx',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        height: 14 / 9,
                        fontWeight: FontWeight.w500,
                        color: ds.labelTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ));
          }
          break;
        case 'a':
          final href = node.attributes['href'] ?? '';
          final validHref = _normalizeHref(href);
          if (disableLinks || validHref == null) {
            spans.addAll(_buildSpans(context, node.children ?? const [], style));
          } else {
            final label = node.textContent;
            spans.add(TextSpan(
              text: label.isEmpty ? validHref : label,
              style: style.copyWith(
                color: ds.brandText,
                decoration: TextDecoration.underline,
                decorationColor: ds.brandText.withValues(alpha: 0.4),
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchUrlSafe(validHref),
            ));
          }
          break;
        case 'img':
          // Per chat-demo ImageAsLink: render markdown images as safe clickable URLs
          final src = node.attributes['src'] ?? '';
          final alt = node.attributes['alt'] ?? '';
          final validHref = _normalizeHref(src);
          final label = alt.isNotEmpty ? alt : (validHref ?? src);
          if (disableLinks || validHref == null) {
            spans.add(TextSpan(text: label, style: style));
          } else {
            spans.add(TextSpan(
              text: label,
              style: style.copyWith(
                color: ds.brandText,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _launchUrlSafe(validHref),
            ));
          }
          break;
        default:
          spans.addAll(_buildSpans(context, node.children ?? const [], style));
          break;
      }
    }
    return spans;
  }

  String? _normalizeHref(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('mailto:')) {
      return null;
    }
    final withScheme =
        trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  Future<void> _launchUrlSafe(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ---------------------------------------------------------------------------
// KaTeX Math Renderer with Streaming Error Resilience
// ---------------------------------------------------------------------------

class _MathFormulaWidget extends StatelessWidget {
  final String tex;
  final bool displayMode;
  final TextStyle textStyle;

  const _MathFormulaWidget({
    required this.tex,
    required this.displayMode,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final mathWidget = Math.tex(
      tex,
      mathStyle: displayMode ? MathStyle.display : MathStyle.text,
      textStyle: textStyle,
      onErrorFallback: (_) => Text(
        displayMode ? '\$\$$tex\$\$' : '\$$tex\$',
        style: textStyle.copyWith(fontFamily: 'monospace'),
      ),
    );

    if (!displayMode) return mathWidget;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(child: mathWidget),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Syntax Highlighted Code Block (DeepSeek Light & Dark Token Themes)
// ---------------------------------------------------------------------------

class _DsCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  final AppStrings strings;

  const _DsCodeBlock({
    required this.code,
    required this.language,
    required this.strings,
  });

  @override
  State<_DsCodeBlock> createState() => _DsCodeBlockState();
}

class _DsCodeBlockState extends State<_DsCodeBlock> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _normalizeLang(String raw) {
    switch (raw.toLowerCase()) {
      case 'js':
        return 'javascript';
      case 'ts':
        return 'typescript';
      case 'py':
        return 'python';
      case 'sh':
      case 'zsh':
      case 'shell':
        return 'bash';
      case 'c++':
      case 'cc':
        return 'cpp';
      case 'c#':
      case 'cs':
        return 'cs';
      case 'yml':
        return 'yaml';
      case 'kt':
        return 'kotlin';
      case 'rs':
        return 'rust';
      case 'rb':
        return 'ruby';
      case 'html':
      case 'vue':
        return 'xml';
      default:
        return raw.toLowerCase();
    }
  }

  List<TextSpan> _highlightCode(DsColors ds) {
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 22 / 13,
      color: ds.isDark ? const Color(0xFFE3EAF2) : const Color(0xFF383A42),
    );

    final lang = _normalizeLang(widget.language);
    if (lang.isEmpty) {
      return [TextSpan(text: widget.code, style: baseStyle)];
    }

    try {
      final result = hl.highlight.parse(widget.code, language: lang);
      if (result.nodes == null) {
        return [TextSpan(text: widget.code, style: baseStyle)];
      }
      return _convertNodes(result.nodes!, baseStyle, ds.isDark);
    } catch (_) {
      return [TextSpan(text: widget.code, style: baseStyle)];
    }
  }

  List<TextSpan> _convertNodes(
    List<hl.Node> nodes,
    TextStyle base,
    bool isDark,
  ) {
    final spans = <TextSpan>[];
    for (final n in nodes) {
      final color = _tokenColor(n.className, isDark);
      final st = color != null ? base.copyWith(color: color) : base;
      if (n.value != null) {
        spans.add(TextSpan(text: n.value, style: st));
      } else if (n.children != null) {
        spans.add(TextSpan(
          style: st,
          children: _convertNodes(n.children!, st, isDark),
        ));
      }
    }
    return spans;
  }

  /// Atom One Light & Coldark Dark palettes matching `chat-demo/highlight.css`.
  Color? _tokenColor(String? className, bool isDark) {
    if (className == null) return null;
    if (isDark) {
      switch (className) {
        case 'comment':
        case 'quote':
          return const Color(0xFF8DA1B9);
        case 'keyword':
        case 'selector-tag':
        case 'operator':
          return const Color(0xFFE9AE7E);
        case 'string':
        case 'addition':
          return const Color(0xFF91D076);
        case 'number':
        case 'literal':
        case 'attr':
        case 'attribute':
          return const Color(0xFFE6D37A);
        case 'title':
        case 'function':
        case 'section':
          return const Color(0xFFC699E3);
        case 'built_in':
        case 'regexp':
          return const Color(0xFFF4ADF4);
        case 'type':
        case 'class':
        case 'variable':
        case 'params':
          return const Color(0xFF6CB8E6);
        case 'tag':
        case 'name':
          return const Color(0xFF66CCCC);
        case 'deletion':
          return const Color(0xFFCD6660);
        default:
          return null;
      }
    } else {
      switch (className) {
        case 'comment':
        case 'quote':
          return const Color(0xFF9FA1A7);
        case 'keyword':
        case 'selector-tag':
          return const Color(0xFFA626A4);
        case 'string':
        case 'addition':
          return const Color(0xFF50A14F);
        case 'number':
        case 'literal':
        case 'attr':
        case 'attribute':
          return const Color(0xFFB76B01);
        case 'title':
        case 'function':
        case 'variable':
        case 'operator':
          return const Color(0xFF4078F2);
        case 'tag':
        case 'name':
        case 'deletion':
          return const Color(0xFFE45649);
        case 'built_in':
        case 'type':
        case 'class':
          return const Color(0xFF0184BC);
        default:
          return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Container(
      decoration: BoxDecoration(
        color: ds.codeBlockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderL1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: ds.codeBlockBanner,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Text(
                  widget.language.isEmpty ? 'text' : widget.language,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 18 / 12,
                    color: ds.labelTertiary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copy,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DsIcons.svg(
                          _copied ? DsIcons.check : DsIcons.copy,
                          size: 14,
                          color: ds.labelSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? widget.strings.copied : widget.strings.copy,
                          style: TextStyle(
                            fontSize: 12,
                            color: ds.labelSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText.rich(
              TextSpan(children: _highlightCode(ds)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mermaid Diagram Block (Diagram | Code segmented toggle + WebView SVG)
// ---------------------------------------------------------------------------

class _MermaidCodeBlock extends StatefulWidget {
  final String code;
  final bool isStreaming;
  final AppStrings strings;

  const _MermaidCodeBlock({
    required this.code,
    required this.isStreaming,
    required this.strings,
  });

  @override
  State<_MermaidCodeBlock> createState() => _MermaidCodeBlockState();
}

class _MermaidCodeBlockState extends State<_MermaidCodeBlock> {
  bool _showDiagram = true;
  bool _copied = false;
  bool _hasError = false;
  double _webHeight = 220;
  WebViewController? _controller;
  String _renderedCode = '';
  bool? _renderedDark;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _ensureWebView(bool isDark) {
    if (_controller != null &&
        _renderedCode == widget.code &&
        _renderedDark == isDark) {
      return;
    }
    if (widget.isStreaming && _controller != null) return;

    _renderedCode = widget.code;
    _renderedDark = isDark;

    final sanitized = widget.code
        .replaceAll(RegExp(r'<img', caseSensitive: false), '&lt;img')
        .replaceAll(RegExp(r'<image', caseSensitive: false), '&lt;image');
    final escapedJson = jsonEncode(sanitized);
    final bgHex = isDark ? '#1B1B1C' : '#F9FAFB';
    final theme = isDark ? 'dark' : 'default';

    final html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  html, body { margin: 0; padding: 8px; background: $bgHex; overflow-x: auto; }
  #out { display: flex; justify-content: center; }
  #out svg { max-width: 100%; height: auto; }
</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
</head>
<body>
<div id="out"></div>
<script>
  async function run() {
    try {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: '$theme' });
      const code = $escapedJson;
      const { svg } = await mermaid.render('ds-mermaid', code);
      document.getElementById('out').innerHTML = svg;
      const h = Math.ceil(document.body.scrollHeight);
      MermaidBridge.postMessage(JSON.stringify({ ok: true, height: h }));
    } catch (e) {
      MermaidBridge.postMessage(JSON.stringify({ ok: false }));
    }
  }
  window.addEventListener('load', run);
</script>
</body>
</html>
''';

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(isDark ? const Color(0xFF1B1B1C) : const Color(0xFFF9FAFB))
      ..addJavaScriptChannel(
        'MermaidBridge',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (mounted) {
              setState(() {
                if (data['ok'] == true) {
                  _hasError = false;
                  final h = (data['height'] as num?)?.toDouble() ?? 220;
                  _webHeight = h.clamp(120, 600);
                } else {
                  _hasError = true;
                }
              });
            }
          } catch (_) {}
        },
      )
      ..loadHtmlString(html);

    _controller = ctrl;
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    if (_showDiagram && widget.code.trim().isNotEmpty && !widget.isStreaming) {
      _ensureWebView(ds.isDark);
    }

    return Container(
      decoration: BoxDecoration(
        color: ds.codeBlockBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderL1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: ds.codeBlockBanner,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                _SegmentPill(
                  label: widget.strings.diagram,
                  active: _showDiagram,
                  onTap: () => setState(() => _showDiagram = true),
                ),
                const SizedBox(width: 4),
                _SegmentPill(
                  label: widget.strings.code,
                  active: !_showDiagram,
                  onTap: () => setState(() => _showDiagram = false),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copy,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DsIcons.svg(
                          _copied ? DsIcons.check : DsIcons.copy,
                          size: 14,
                          color: ds.labelSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? widget.strings.copied : widget.strings.copy,
                          style: TextStyle(
                            fontSize: 12,
                            color: ds.labelSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_showDiagram)
            Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                widget.code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 22 / 13,
                  color: ds.labelPrimary,
                ),
              ),
            )
          else if (widget.code.trim().isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  widget.strings.emptyDiagram,
                  style: TextStyle(fontSize: 13, color: ds.labelTertiary),
                ),
              ),
            )
          else if (widget.isStreaming)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  widget.strings.renderingDiagram,
                  style: TextStyle(fontSize: 13, color: ds.labelTertiary),
                ),
              ),
            )
          else if (_hasError)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  widget.strings.mermaidFailed,
                  style: TextStyle(fontSize: 13, color: ds.labelTertiary),
                ),
              ),
            )
          else if (_controller != null)
            SizedBox(
              height: _webHeight,
              child: WebViewWidget(controller: _controller!),
            ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegmentPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? ds.codeBlockBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? ds.labelPrimary : ds.labelTertiary,
          ),
        ),
      ),
    );
  }
}
