import '../../models/api_types.dart';
import '../../models/chat_models.dart';

bool _isWebUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

String _defaultSiteName(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  return uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
}

class _SourceRegistry {
  final Map<String, ReplySource> _byUrl = {};
  final Map<int, ReplySource> byIndex = {};
  int _nextIndex = 1;

  ReplySource? register({
    required String url,
    String? title,
    String? siteName,
    String? publishedAt,
    String? snippet,
    String? siteIcon,
  }) {
    if (!_isWebUrl(url)) return null;
    final existing = _byUrl[url];
    if (existing != null) {
      if (existing.title.isEmpty && title != null && title.isNotEmpty) {
        existing.title = title;
      }
      if ((existing.siteName.isEmpty ||
              existing.siteName == _defaultSiteName(url)) &&
          siteName != null &&
          siteName.isNotEmpty) {
        existing.siteName = siteName;
      }
      if (existing.publishedAt == null &&
          publishedAt != null &&
          publishedAt.isNotEmpty) {
        existing.publishedAt = publishedAt;
      }
      if (existing.snippet.isEmpty && snippet != null && snippet.isNotEmpty) {
        existing.snippet = snippet;
      }
      if (existing.siteIcon == null &&
          siteIcon != null &&
          siteIcon.isNotEmpty) {
        existing.siteIcon = siteIcon;
      }
      return existing;
    }

    final src = ReplySource(
      index: _nextIndex++,
      url: url,
      title: (title != null && title.isNotEmpty) ? title : _defaultSiteName(url),
      siteName: (siteName != null && siteName.isNotEmpty)
          ? siteName
          : _defaultSiteName(url),
      publishedAt: publishedAt,
      snippet: snippet ?? '',
      siteIcon: siteIcon,
    );
    _byUrl[url] = src;
    byIndex[src.index] = src;
    return src;
  }
}

StepStatus _mergeStatuses(List<StepStatus> statuses) {
  if (statuses.any((s) => s == StepStatus.wip)) return StepStatus.wip;
  if (statuses.isNotEmpty && statuses.every((s) => s == StepStatus.failed)) {
    return StepStatus.failed;
  }
  return StepStatus.done;
}

/// Pure derivation from [AssistantMessage] blocks to [ReplyView]
/// ported 1:1 from `src/services/chat/view.ts`.
ReplyView buildReplyView(AssistantMessage reply) {
  final streaming = reply.isStreaming;
  final registry = _SourceRegistry();
  final searchResults = <ReplySource>[];
  final seenSearchUrls = <String>{};

  // Index tool results by tool_use_id
  final searchResultById = <String, WebSearchToolResultBlock>{};
  final fetchResultById = <String, WebFetchToolResultBlock>{};

  // Pre-pass: register sources in order of appearance
  for (final b in reply.blocks) {
    if (b is WebSearchToolResultBlock) {
      searchResultById[b.toolUseId] = b;
      for (final item in b.content) {
        if (!item.isError) {
          final src = registry.register(
            url: item.url,
            title: item.title,
            siteName: item.siteName,
            publishedAt: item.pageAge,
            snippet: item.snippet,
            siteIcon: item.siteIcon,
          );
          if (src != null && seenSearchUrls.add(src.url)) {
            searchResults.add(src);
          }
        }
      }
    } else if (b is WebFetchToolResultBlock) {
      fetchResultById[b.toolUseId] = b;
      if (b.kind == 'deep_search' && b.isFetchResult && b.url != null) {
        registry.register(
          url: b.url!,
          title: b.title,
          publishedAt: b.publishedAt,
        );
      }
    }
  }

  String formatTextWithCitations(List<TextPart> parts) {
    final buf = StringBuffer();
    for (final part in parts) {
      final indices = <int>[];
      final seen = <int>{};
      for (final c in part.citations) {
        final src = registry.register(url: c.url, title: c.title);
        if (src != null && seen.add(src.index)) {
          indices.add(src.index);
        }
      }
      if (indices.isEmpty) {
        buf.write(part.text);
      } else {
        final trimmedEnd = part.text.trimRight();
        final trailing = part.text.substring(trimmedEnd.length);
        final markers = indices.map((i) => '[citation:$i]').join();
        buf.write(trimmedEnd);
        buf.write(markers);
        buf.write(trailing);
      }
    }
    return buf.toString();
  }

  // Find index of last thinking or server_tool block to separate preamble text from final answer
  var lastStepBlockIdx = -1;
  for (var i = 0; i < reply.blocks.length; i++) {
    final b = reply.blocks[i];
    if (b is ThinkingPart ||
        b is ServerToolUseBlock ||
        b is WebSearchToolResultBlock ||
        b is WebFetchToolResultBlock) {
      lastStepBlockIdx = i;
    }
  }

  final steps = <ReplyStep>[];
  final answerParts = <TextPart>[];
  final preambleBuffer = <TextPart>[];
  final nonDeepSearchStepIdx = <String, int>{};

  void flushPreamble(int keyIndex) {
    if (preambleBuffer.isEmpty) return;
    final md = formatTextWithCitations(preambleBuffer).trim();
    preambleBuffer.clear();
    if (md.isNotEmpty) {
      steps.add(PreambleTextStep(key: 'preamble-$keyIndex', markdown: md));
    }
  }

  for (var i = 0; i < reply.blocks.length; i++) {
    final b = reply.blocks[i];
    if (b is TextPart) {
      if (b.isTemplate) continue;
      if (i > lastStepBlockIdx) {
        answerParts.add(b);
      } else {
        preambleBuffer.add(b);
      }
      continue;
    }

    flushPreamble(i);

    if (b is ThinkingPart) {
      final isActive = streaming && b.endedAt == null;
      if (steps.isNotEmpty && steps.last is ThinkingStep) {
        final prev = steps.last as ThinkingStep;
        final merged = prev.markdown.isEmpty
            ? b.thinking
            : (b.thinking.isEmpty ? prev.markdown : '${prev.markdown}\n\n${b.thinking}');
        steps[steps.length - 1] = ThinkingStep(
          key: prev.key,
          markdown: merged,
          active: prev.active || isActive,
        );
      } else if (b.thinking.isNotEmpty || isActive) {
        steps.add(ThinkingStep(
          key: 'think-$i',
          markdown: b.thinking,
          active: isActive,
        ));
      }
      continue;
    }

    if (b is ServerToolUseBlock) {
      final action = b.action;
      if (action == 'search') {
        final res = searchResultById[b.id];
        final StepStatus status;
        final List<ReplySource> resList = [];
        if (res == null) {
          status = streaming ? StepStatus.wip : StepStatus.failed;
        } else if (res.hasError) {
          status = StepStatus.failed;
        } else {
          status = StepStatus.done;
          for (final item in res.content) {
            if (!item.isError) {
              final src = registry.register(
                url: item.url,
                title: item.title,
                siteName: item.siteName,
                publishedAt: item.pageAge,
                snippet: item.snippet,
                siteIcon: item.siteIcon,
              );
              if (src != null) resList.add(src);
            }
          }
        }

        final isDeep = b.kind == 'deep_search' || b.kind == 'deep_image_search';
        if (!isDeep && nonDeepSearchStepIdx.containsKey(b.kind)) {
          final idx = nonDeepSearchStepIdx[b.kind]!;
          final prev = steps[idx] as SearchStep;
          final combinedUrls = prev.results.map((r) => r.url).toSet();
          final mergedRes = [...prev.results];
          for (final r in resList) {
            if (combinedUrls.add(r.url)) mergedRes.add(r);
          }
          steps[idx] = SearchStep(
            key: prev.key,
            kind: prev.kind,
            queries: [...prev.queries, ...b.queries],
            results: mergedRes,
            status: _mergeStatuses([prev.status, status]),
          );
        } else if (isDeep &&
            steps.isNotEmpty &&
            steps.last is SearchStep &&
            (steps.last as SearchStep).kind == b.kind) {
          final prev = steps.last as SearchStep;
          final combinedUrls = prev.results.map((r) => r.url).toSet();
          final mergedRes = [...prev.results];
          for (final r in resList) {
            if (combinedUrls.add(r.url)) mergedRes.add(r);
          }
          steps[steps.length - 1] = SearchStep(
            key: prev.key,
            kind: prev.kind,
            queries: [...prev.queries, ...b.queries],
            results: mergedRes,
            status: _mergeStatuses([prev.status, status]),
          );
        } else {
          if (!isDeep) {
            nonDeepSearchStepIdx[b.kind] = steps.length;
          }
          steps.add(SearchStep(
            key: 'search-${b.id}',
            kind: b.kind,
            queries: b.queries,
            results: resList,
            status: status,
          ));
        }
      } else if (action == 'open_page') {
        final res = fetchResultById[b.id];
        final status = res == null
            ? (streaming ? StepStatus.wip : StepStatus.failed)
            : (res.isFetchResult ? StepStatus.done : StepStatus.failed);
        final pageUrl = res?.url ?? b.url;
        final pageTitle = (res?.title != null && res!.title!.isNotEmpty)
            ? res.title!
            : _defaultSiteName(pageUrl);
        final pageItem = OpenPageItem(
          url: pageUrl,
          title: pageTitle,
          status: status,
        );
        if (steps.isNotEmpty && steps.last is OpenStep) {
          final prev = steps.last as OpenStep;
          steps[steps.length - 1] = OpenStep(
            key: prev.key,
            pages: [...prev.pages, pageItem],
            status: _mergeStatuses([prev.status, status]),
          );
        } else {
          steps.add(OpenStep(
            key: 'open-${b.id}',
            pages: [pageItem],
            status: status,
          ));
        }
      } else if (action == 'find_in_page') {
        final res = fetchResultById[b.id];
        final status = res == null
            ? (streaming ? StepStatus.wip : StepStatus.failed)
            : (res.isFetchResult ? StepStatus.done : StepStatus.failed);
        final item = FindItem(pattern: b.pattern, status: status);
        if (steps.isNotEmpty && steps.last is FindStep) {
          final prev = steps.last as FindStep;
          steps[steps.length - 1] = FindStep(
            key: prev.key,
            items: [...prev.items, item],
            status: _mergeStatuses([prev.status, status]),
          );
        } else {
          steps.add(FindStep(
            key: 'find-${b.id}',
            items: [item],
            status: status,
          ));
        }
      } else if (action == 'read_link') {
        final res = fetchResultById[b.id];
        final status = res == null
            ? (streaming ? StepStatus.wip : StepStatus.failed)
            : (res.isFetchResult ? StepStatus.done : StepStatus.failed);
        final pageUrl = res?.url ?? b.url;
        // Per chat-demo spec: read_link is only displayed while wip
        if (status == StepStatus.wip && pageUrl.isNotEmpty) {
          final item = OpenPageItem(
            url: pageUrl,
            title: _defaultSiteName(pageUrl),
            status: status,
          );
          if (steps.isNotEmpty && steps.last is ReadLinkStep) {
            final prev = steps.last as ReadLinkStep;
            steps[steps.length - 1] = ReadLinkStep(
              key: prev.key,
              pages: [...prev.pages, item],
              status: status,
            );
          } else {
            steps.add(ReadLinkStep(
              key: 'readlink-${b.id}',
              pages: [item],
              status: status,
            ));
          }
        }
      }
    }
  }

  flushPreamble(reply.blocks.length);

  final answer = formatTextWithCitations(answerParts);

  return ReplyView(
    steps: steps,
    answer: answer,
    sourcesByIndex: registry.byIndex,
    searchResults: searchResults,
  );
}

/// Sums total thinking duration in seconds (minimum 1s), or null if timing unavailable.
int? getTotalThinkingSeconds(AssistantMessage reply, {int? nowMs}) {
  final thinkingBlocks = reply.blocks.whereType<ThinkingPart>().toList();
  if (thinkingBlocks.isEmpty) return null;

  double totalMs = 0;
  for (final b in thinkingBlocks) {
    if (b.elapsedSeconds != null) {
      totalMs += b.elapsedSeconds! * 1000;
    } else if (b.startedAt != null) {
      final end = b.endedAt ?? nowMs ?? DateTime.now().millisecondsSinceEpoch;
      totalMs += (end - b.startedAt!).clamp(0, 86400000);
    } else {
      return null;
    }
  }
  final secs = (totalMs / 1000).round();
  return secs < 1 ? 1 : secs;
}
