import '../../l10n/app_strings.dart';
import '../../models/api_types.dart';
import '../../models/chat_models.dart';

/// Applies a single SSE [MessageEvent] into [reply] using a per-stream [blockIndexes] map.
void applyEvent(
  AssistantMessage reply,
  MessageEvent event,
  int nowMs,
  Map<int, int> blockIndexes,
) {
  switch (event) {
    case MessageStartEvent():
      if (event.usage != null) {
        reply.usage = event.usage;
      }
      break;

    case ContentBlockStartEvent():
      if (event.isClientToolUse) {
        reply.prefix = false;
        return;
      }
      final b = event.block;
      if (b == null) return;
      if (b is ThinkingPart) {
        b.startedAt = nowMs;
      }
      final localIdx = reply.blocks.length;
      reply.blocks.add(b);
      blockIndexes[event.index] = localIdx;
      break;

    case ContentBlockDeltaEvent():
      final localIdx = blockIndexes[event.index];
      if (localIdx == null || localIdx >= reply.blocks.length) return;
      final block = reply.blocks[localIdx];
      switch (event.deltaType) {
        case 'text_delta':
          if (block is TextPart && event.text != null) {
            block.text += event.text!;
          }
          break;
        case 'thinking_delta':
          if (block is ThinkingPart && event.thinking != null) {
            block.thinking += event.thinking!;
          }
          break;
        case 'signature_delta':
          if (block is ThinkingPart && event.signature != null) {
            block.signature = (block.signature ?? '') + event.signature!;
          }
          break;
        case 'citations_delta':
          if (block is TextPart && event.citation != null) {
            block.citations.add(event.citation!);
          }
          break;
      }
      break;

    case ContentBlockStopEvent():
      final localIdx = blockIndexes.remove(event.index);
      if (localIdx != null && localIdx < reply.blocks.length) {
        final block = reply.blocks[localIdx];
        if (block is ThinkingPart && block.endedAt == null) {
          block.endedAt = nowMs;
        }
      }
      break;

    case MessageDeltaEvent():
      reply.stopReason = event.stopReason;
      reply.stopDetails = event.stopDetails;
      if (event.usage != null) {
        reply.usage = event.usage;
      }
      break;

    case MessageStopEvent():
      break;
  }
}

/// Finalizes a reply when streaming completes, stops, or errors.
void settleReply(
  AssistantMessage reply,
  ReplyStatus status,
  int nowMs, {
  ReplyError? error,
}) {
  reply.status = status;
  if (error != null) {
    reply.error = error;
  }
  if (reply.stopReason == 'refusal') {
    reply.blocks.removeWhere(
      (b) => b is ThinkingPart || (b is TextPart && !b.isTemplate),
    );
  }
  for (final b in reply.blocks) {
    if (b is ThinkingPart && b.endedAt == null) {
      b.endedAt = nowMs;
    }
  }
}

String getReplyText(AssistantMessage reply) {
  final buf = StringBuffer();
  var prevWasNonText = false;
  var hasText = false;
  for (final b in reply.blocks) {
    if (b is TextPart && !b.isTemplate) {
      if (b.text.isNotEmpty) {
        if (hasText && prevWasNonText) {
          buf.write('\n\n');
        }
        buf.write(b.text);
        hasText = true;
        prevWasNonText = false;
      }
    } else {
      prevWasNonText = true;
    }
  }
  return buf.toString();
}

String getTemplateText(AssistantMessage reply) {
  final parts = <String>[];
  for (final b in reply.blocks) {
    if (b is TextPart && b.isTemplate && b.text.isNotEmpty) {
      parts.add(b.text);
    }
  }
  return parts.join('\n\n');
}

bool hasTemplateBlock(AssistantMessage reply) =>
    reply.blocks.any((b) => b is TextPart && b.isTemplate);

bool hasServerToolBlocks(AssistantMessage reply) => reply.blocks.any(
      (b) =>
          b is ServerToolUseBlock ||
          b is WebSearchToolResultBlock ||
          b is WebFetchToolResultBlock,
    );

bool canContinueReply(AssistantMessage reply) {
  if (!reply.prefix) return false;
  if (reply.stopReason == 'refusal' || reply.stopReason == 'tool_use') {
    return false;
  }
  if (hasServerToolBlocks(reply) || hasTemplateBlock(reply)) {
    return false;
  }
  return reply.status == ReplyStatus.stopped ||
      (reply.status == ReplyStatus.done && reply.stopReason == 'max_tokens');
}

bool _isUsableReply(AssistantMessage reply) {
  if (reply.status != ReplyStatus.done && reply.status != ReplyStatus.stopped) {
    return false;
  }
  if (reply.stopReason == 'refusal') return false;
  if (hasTemplateBlock(reply)) return false;
  return getReplyText(reply).isNotEmpty;
}

List<Map<String, dynamic>> _toFileBlocks(List<FileAttachment> files) {
  final out = <Map<String, dynamic>>[];
  for (final f in files) {
    if (f.serverId != null && f.serverId!.isNotEmpty) {
      out.add({
        'type': f.isImage ? 'image' : 'document',
        'source': {
          'type': 'file',
          'file_id': f.serverId!,
        },
      });
    }
  }
  return out;
}

Map<String, dynamic> _toUserParam(UserMessage user) {
  final fileBlocks = _toFileBlocks(user.files);
  if (fileBlocks.isEmpty) {
    return {'role': 'user', 'content': user.content};
  }
  return {
    'role': 'user',
    'content': [
      ...fileBlocks,
      if (user.content.isNotEmpty) {'type': 'text', 'text': user.content},
    ],
  };
}

List<Map<String, dynamic>> _toAssistantBlocks(
  AssistantMessage reply, {
  required bool isPrefix,
  required bool thinkingEnabled,
}) {
  // For historical turns, identify valid read_link tool_use IDs (non-blank signature)
  final validReadLinkIds = <String>{};
  if (!isPrefix) {
    for (final b in reply.blocks) {
      if (b is WebFetchToolResultBlock && b.kind == 'read_link') {
        if (!b.isFetchResult || (b.signature != null && b.signature!.trim().isNotEmpty)) {
          validReadLinkIds.add(b.toolUseId);
        }
      }
    }
  }

  final out = <Map<String, dynamic>>[];
  var pendingParagraphBreak = false;

  void appendText(String text) {
    if (text.isEmpty) return;
    if (out.isNotEmpty && out.last['type'] == 'text') {
      final prev = out.last['text'] as String;
      out.last['text'] = pendingParagraphBreak ? '$prev\n\n$text' : '$prev$text';
    } else {
      final prefixText = pendingParagraphBreak && out.isNotEmpty ? '\n\n' : '';
      out.add({'type': 'text', 'text': '$prefixText$text'});
    }
    pendingParagraphBreak = false;
  }

  for (final b in reply.blocks) {
    if (b is TextPart) {
      if (!b.isTemplate) {
        appendText(b.text);
      }
      continue;
    }

    // Any non-text block separates surrounding text blocks with \n\n
    if (out.isNotEmpty && out.last['type'] == 'text') {
      pendingParagraphBreak = true;
    }

    if (b is ThinkingPart) {
      if (isPrefix && thinkingEnabled && b.thinking.trim().isNotEmpty) {
        out.add({
          'type': 'thinking',
          'thinking': b.thinking,
          'signature': b.signature ?? '',
        });
        pendingParagraphBreak = false;
      }
      continue;
    }

    if (!isPrefix) {
      if (b is ServerToolUseBlock &&
          b.kind == 'read_link' &&
          validReadLinkIds.contains(b.id)) {
        out.add(b.toWireParam());
        pendingParagraphBreak = false;
      } else if (b is WebFetchToolResultBlock &&
          b.kind == 'read_link' &&
          validReadLinkIds.contains(b.toolUseId)) {
        out.add(b.toJson());
        pendingParagraphBreak = false;
      }
    }
  }

  return out
      .where((m) => m['type'] != 'text' || (m['text'] as String).isNotEmpty)
      .toList();
}

/// Builds the full `messages` array for `POST /anthropic/v1/messages`,
/// including deduplicated `latest_reminder` messages and optional continuation prefill.
List<Map<String, dynamic>> toRequestMessages({
  required List<ChatMessage> history,
  required UserMessage question,
  AssistantMessage? continuationPrefix,
  required bool thinkingEnabled,
  String? currentLatestReminder,
}) {
  final wire = <Map<String, dynamic>>[];
  String? previousReminder;

  void maybeAddReminder(String? reminder) {
    if (reminder != null &&
        reminder.isNotEmpty &&
        reminder != previousReminder) {
      wire.add({'role': 'latest_reminder', 'content': reminder});
      previousReminder = reminder;
    }
  }

  // Pair usable [user, assistant] turns from history
  for (var i = 0; i + 1 < history.length; i++) {
    final u = history[i];
    final a = history[i + 1];
    if (u is UserMessage && a is AssistantMessage && _isUsableReply(a)) {
      if (u.content.isEmpty && _toFileBlocks(u.files).isEmpty) {
        i++;
        continue;
      }
      maybeAddReminder(a.latestReminder);
      wire.add(_toUserParam(u));
      final aBlocks = _toAssistantBlocks(
        a,
        isPrefix: false,
        thinkingEnabled: thinkingEnabled,
      );
      if (aBlocks.isNotEmpty) {
        wire.add({'role': 'assistant', 'content': aBlocks});
      }
      i++;
    }
  }

  // Current turn
  maybeAddReminder(currentLatestReminder);
  wire.add(_toUserParam(question));

  if (continuationPrefix != null && continuationPrefix.prefix) {
    final prefixBlocks = _toAssistantBlocks(
      continuationPrefix,
      isPrefix: true,
      thinkingEnabled: thinkingEnabled,
    );
    final hasSubstantive = prefixBlocks.any((b) =>
        (b['type'] == 'text' && (b['text'] as String).trim().isNotEmpty) ||
        (b['type'] == 'thinking' &&
            (b['thinking'] as String).trim().isNotEmpty));
    if (hasSubstantive) {
      wire.add({'role': 'assistant', 'content': prefixBlocks});
    }
  }

  return wire;
}

/// Derives inline error/refusal notice for an assistant message (`chat/describe.ts`).
ReplyNotice? describeReply(AssistantMessage reply, AppStrings s) {
  final template = getTemplateText(reply);

  if (reply.status == ReplyStatus.error) {
    final err = reply.error;
    if (err != null) {
      if (err.kind == 'upload') {
        return ReplyNotice(
          text: err.message.isNotEmpty ? err.message : s.uploadFailed,
        );
      }
      if (err.kind == 'network') {
        return ReplyNotice(text: s.networkError);
      }
      final st = err.status;
      if (st == 401) {
        return ReplyNotice(
          text: s.replyInvalidApiKey,
          action: NoticeAction.apiKey,
        );
      }
      if (st == 402) {
        return ReplyNotice(
          text: s.replyInsufficientBalance,
          action: NoticeAction.topUp,
        );
      }
      if (st == 413) {
        return ReplyNotice(text: s.requestTooLarge);
      }
      if (st == 429) {
        return ReplyNotice(text: s.replyRateLimited);
      }
      if (st != null && st >= 500) {
        return ReplyNotice(text: s.serverBusy);
      }
      if (err.message.isNotEmpty) {
        return ReplyNotice(text: err.message);
      }
      return null;
    }
    if (template.isNotEmpty) {
      return ReplyNotice(text: template);
    }
    return null;
  }

  if (reply.stopReason == 'refusal') {
    return ReplyNotice(
      text: template.isNotEmpty ? template : s.replyRefused,
      asResponse: true,
    );
  }

  if (template.isNotEmpty) {
    return ReplyNotice(text: template, asResponse: true);
  }

  return null;
}
