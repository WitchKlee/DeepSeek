import '../../models/api_types.dart';

const _validStopReasons = {'end_turn', 'max_tokens', 'tool_use', 'refusal'};
const _validToolNames = {'deepseek_web_search', 'deepseek_read_url'};
const _validToolKinds = {
  'search',
  'deep_search',
  'read_link',
  'image_search',
  'deep_image_search',
};

/// Parses and validates an SSE JSON payload into a typed [MessageEvent].
/// Unrecognized or malformed payloads return null and are ignored.
MessageEvent? parseMessageEvent(dynamic raw) {
  if (raw is! Map) return null;
  final type = raw['type'];
  if (type is! String) return null;

  switch (type) {
    case 'message_start':
      final msg = raw['message'];
      if (msg is! Map) return null;
      final id = msg['id'];
      final model = msg['model'];
      if (id is! String || model is! String) return null;
      return MessageStartEvent(
        id: id,
        model: model,
        usage: MessageUsage.tryParse(msg['usage']),
      );

    case 'content_block_start':
      final idx = raw['index'];
      if (idx is! int || idx < 0) return null;
      final cb = raw['content_block'];
      if (cb is! Map) return null;
      final cbType = cb['type'];
      if (cbType == 'tool_use') {
        return ContentBlockStartEvent(index: idx, isClientToolUse: true);
      }
      final block = _parseContentBlock(cb);
      if (block == null) return null;
      return ContentBlockStartEvent(index: idx, block: block);

    case 'content_block_delta':
      final idx = raw['index'];
      if (idx is! int || idx < 0) return null;
      final delta = raw['delta'];
      if (delta is! Map) return null;
      final dt = delta['type'];
      switch (dt) {
        case 'text_delta':
          if (delta['text'] is! String) return null;
          return ContentBlockDeltaEvent(
            index: idx,
            deltaType: 'text_delta',
            text: delta['text'] as String,
          );
        case 'thinking_delta':
          if (delta['thinking'] is! String) return null;
          return ContentBlockDeltaEvent(
            index: idx,
            deltaType: 'thinking_delta',
            thinking: delta['thinking'] as String,
          );
        case 'signature_delta':
          if (delta['signature'] is! String) return null;
          return ContentBlockDeltaEvent(
            index: idx,
            deltaType: 'signature_delta',
            signature: delta['signature'] as String,
          );
        case 'citations_delta':
          final cite = TextCitation.tryParse(delta['citation']);
          if (cite == null) return null;
          return ContentBlockDeltaEvent(
            index: idx,
            deltaType: 'citations_delta',
            citation: cite,
          );
        default:
          return null;
      }

    case 'content_block_stop':
      final idx = raw['index'];
      if (idx is! int || idx < 0) return null;
      return ContentBlockStopEvent(index: idx);

    case 'message_delta':
      final delta = raw['delta'];
      if (delta is! Map) return null;
      final stopReason = delta['stop_reason'];
      if (stopReason is! String || !_validStopReasons.contains(stopReason)) {
        return null;
      }
      return MessageDeltaEvent(
        stopReason: stopReason,
        stopDetails: StopDetails.tryParse(delta['stop_details']),
        title: delta['title'] is String ? delta['title'] as String : null,
        usage: MessageUsage.tryParse(raw['usage']),
      );

    case 'message_stop':
      return const MessageStopEvent();

    case 'ping':
    default:
      return null;
  }
}

ReplyBlock? _parseContentBlock(Map cb) {
  switch (cb['type']) {
    case 'text':
      if (cb['text'] is! String) return null;
      final cites = <TextCitation>[];
      if (cb['citations'] is List) {
        for (final item in cb['citations'] as List) {
          final c = TextCitation.tryParse(item);
          if (c != null) cites.add(c);
        }
      }
      return TextPart(text: cb['text'] as String, citations: cites);

    case 'thinking':
      if (cb['thinking'] is! String) return null;
      return ThinkingPart(
        thinking: cb['thinking'] as String,
        signature: cb['signature'] is String ? cb['signature'] as String : null,
      );

    case 'server_tool_use':
      final id = cb['id'];
      final name = cb['name'];
      final kind = cb['kind'];
      final input = cb['input'];
      if (id is! String ||
          name is! String ||
          !_validToolNames.contains(name) ||
          kind is! String ||
          !_validToolKinds.contains(kind) ||
          input is! Map) {
        return null;
      }
      final action = input['action'];
      if (action == 'search') {
        if (input['queries'] is! List) return null;
      } else if (action == 'open_page' || action == 'read_link') {
        if (input['url'] is! String) return null;
      } else if (action == 'find_in_page') {
        if (input['pattern'] is! String) return null;
      } else {
        return null;
      }
      return ServerToolUseBlock(
        id: id,
        name: name,
        kind: kind,
        input: Map<String, dynamic>.from(input),
      );

    case 'web_search_tool_result':
      final toolUseId = cb['tool_use_id'];
      final kind = cb['kind'];
      final content = cb['content'];
      if (toolUseId is! String || kind is! String || content is! List) {
        return null;
      }
      final items = <WebSearchResultItem>[];
      for (final item in content) {
        final parsed = WebSearchResultItem.tryParse(item);
        if (parsed != null) items.add(parsed);
      }
      return WebSearchToolResultBlock(
        toolUseId: toolUseId,
        kind: kind,
        content: items,
      );

    case 'web_fetch_tool_result':
      final toolUseId = cb['tool_use_id'];
      final kind = cb['kind'];
      final content = cb['content'];
      if (toolUseId is! String || kind is! String || content is! Map) {
        return null;
      }
      final cType = content['type'];
      if (cType != 'web_fetch_result' &&
          cType != 'web_fetch_tool_result_error') {
        return null;
      }
      return WebFetchToolResultBlock(
        toolUseId: toolUseId,
        kind: kind,
        signature: cb['signature'] is String ? cb['signature'] as String : null,
        content: Map<String, dynamic>.from(content),
      );

    default:
      return null;
  }
}
