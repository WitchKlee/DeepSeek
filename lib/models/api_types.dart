// Exact Anthropic-compatible + DeepSeek extended API wire types.

class MessageUsage {
  final int inputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;
  final int outputTokens;
  final int? webSearchRequests;
  final int? toolSearch;

  const MessageUsage({
    required this.inputTokens,
    required this.cacheCreationInputTokens,
    required this.cacheReadInputTokens,
    required this.outputTokens,
    this.webSearchRequests,
    this.toolSearch,
  });

  int get totalTokens =>
      inputTokens +
      cacheCreationInputTokens +
      cacheReadInputTokens +
      outputTokens;

  Map<String, dynamic> toJson() => {
        'input_tokens': inputTokens,
        'cache_creation_input_tokens': cacheCreationInputTokens,
        'cache_read_input_tokens': cacheReadInputTokens,
        'output_tokens': outputTokens,
        if (webSearchRequests != null || toolSearch != null)
          'server_tool_use': {
            'web_search_requests': webSearchRequests ?? 0,
            'tool_search': toolSearch ?? 0,
          },
      };

  static MessageUsage? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final i = raw['input_tokens'];
    final cc = raw['cache_creation_input_tokens'];
    final cr = raw['cache_read_input_tokens'];
    final o = raw['output_tokens'];
    if (i is! num || cc is! num || cr is! num || o is! num) return null;
    if (!i.isFinite || !cc.isFinite || !cr.isFinite || !o.isFinite) return null;
    int? ws;
    int? ts;
    final stu = raw['server_tool_use'];
    if (stu is Map) {
      if (stu['web_search_requests'] is num) {
        ws = (stu['web_search_requests'] as num).toInt();
      }
      if (stu['tool_search'] is num) {
        ts = (stu['tool_search'] as num).toInt();
      }
    }
    return MessageUsage(
      inputTokens: i.toInt(),
      cacheCreationInputTokens: cc.toInt(),
      cacheReadInputTokens: cr.toInt(),
      outputTokens: o.toInt(),
      webSearchRequests: ws,
      toolSearch: ts,
    );
  }
}

class TextCitation {
  final String type; // 'web_search_result_location'
  final String url;
  final String? title;
  final String citedText;
  final String encryptedIndex;

  const TextCitation({
    this.type = 'web_search_result_location',
    required this.url,
    this.title,
    this.citedText = '',
    this.encryptedIndex = '',
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'url': url,
        'title': title,
        'cited_text': citedText,
        'encrypted_index': encryptedIndex,
      };

  static TextCitation? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    if (raw['type'] != 'web_search_result_location') return null;
    final url = raw['url'];
    if (url is! String) return null;
    final title = raw['title'];
    if (title != null && title is! String) return null;
    return TextCitation(
      type: 'web_search_result_location',
      url: url,
      title: title as String?,
      citedText: raw['cited_text'] is String ? raw['cited_text'] as String : '',
      encryptedIndex: raw['encrypted_index'] is String
          ? raw['encrypted_index'] as String
          : '',
    );
  }
}

class StopDetails {
  final String type;
  final String? category;
  final String? explanation;

  const StopDetails({
    required this.type,
    this.category,
    this.explanation,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'category': category,
        'explanation': explanation,
      };

  static StopDetails? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String) return null;
    return StopDetails(
      type: type,
      category: raw['category'] as String?,
      explanation: raw['explanation'] as String?,
    );
  }
}

class FileObject {
  final String id;
  final String type;
  final int sizeBytes;
  final String createdAt;
  final String filename;
  final String mimeType;

  const FileObject({
    required this.id,
    required this.type,
    required this.sizeBytes,
    required this.createdAt,
    required this.filename,
    required this.mimeType,
  });

  factory FileObject.fromJson(Map<String, dynamic> json) {
    return FileObject(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'file',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Reply Blocks (stored in AssistantMessage.blocks)
// ---------------------------------------------------------------------------

sealed class ReplyBlock {
  const ReplyBlock();
  String get type;
  Map<String, dynamic> toJson();

  static ReplyBlock? fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'thinking':
        return ThinkingPart.fromJson(json);
      case 'text':
        return TextPart.fromJson(json);
      case 'server_tool_use':
        return ServerToolUseBlock.fromJson(json);
      case 'web_search_tool_result':
        return WebSearchToolResultBlock.fromJson(json);
      case 'web_fetch_tool_result':
        return WebFetchToolResultBlock.fromJson(json);
      default:
        return null;
    }
  }
}

class ThinkingPart extends ReplyBlock {
  @override
  String get type => 'thinking';
  String thinking;
  String? signature;
  int? startedAt;
  int? endedAt;
  double? elapsedSeconds;

  ThinkingPart({
    required this.thinking,
    this.signature,
    this.startedAt,
    this.endedAt,
    this.elapsedSeconds,
  });

  ThinkingPart clone() => ThinkingPart(
        thinking: thinking,
        signature: signature,
        startedAt: startedAt,
        endedAt: endedAt,
        elapsedSeconds: elapsedSeconds,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'thinking',
        'thinking': thinking,
        if (signature != null) 'signature': signature,
        if (startedAt != null) 'startedAt': startedAt,
        if (endedAt != null) 'endedAt': endedAt,
        if (elapsedSeconds != null) 'elapsedSeconds': elapsedSeconds,
      };

  factory ThinkingPart.fromJson(Map<String, dynamic> json) => ThinkingPart(
        thinking: json['thinking'] as String? ?? '',
        signature: json['signature'] as String?,
        startedAt: (json['startedAt'] as num?)?.toInt(),
        endedAt: (json['endedAt'] as num?)?.toInt(),
        elapsedSeconds: (json['elapsedSeconds'] as num?)?.toDouble(),
      );
}

class TextPart extends ReplyBlock {
  @override
  String get type => 'text';
  String text;
  List<TextCitation> citations;
  bool isTemplate;

  TextPart({
    required this.text,
    List<TextCitation>? citations,
    this.isTemplate = false,
  }) : citations = citations ?? [];

  TextPart clone() => TextPart(
        text: text,
        citations: List<TextCitation>.from(citations),
        isTemplate: isTemplate,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'text': text,
        if (citations.isNotEmpty)
          'citations': citations.map((c) => c.toJson()).toList(),
        if (isTemplate) 'isTemplate': true,
      };

  factory TextPart.fromJson(Map<String, dynamic> json) {
    final rawCites = json['citations'];
    final cites = <TextCitation>[];
    if (rawCites is List) {
      for (final item in rawCites) {
        final parsed = TextCitation.tryParse(item);
        if (parsed != null) cites.add(parsed);
      }
    }
    return TextPart(
      text: json['text'] as String? ?? '',
      citations: cites,
      isTemplate: json['isTemplate'] == true,
    );
  }
}

class ServerToolUseBlock extends ReplyBlock {
  @override
  String get type => 'server_tool_use';
  final String id;
  final String name; // 'deepseek_web_search' | 'deepseek_read_url'
  final String kind; // 'search' | 'deep_search' | 'read_link' | 'image_search' | 'deep_image_search'
  final Map<String, dynamic> input; // contains 'action': 'search' | 'open_page' | 'read_link' | 'find_in_page'

  const ServerToolUseBlock({
    required this.id,
    required this.name,
    required this.kind,
    required this.input,
  });

  String get action => input['action'] as String? ?? '';

  List<String> get queries {
    final q = input['queries'];
    if (q is List) {
      return q.whereType<String>().toList();
    }
    return const [];
  }

  String get url => input['url'] as String? ?? '';
  String get pattern => input['pattern'] as String? ?? '';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'server_tool_use',
        'id': id,
        'name': name,
        'kind': kind,
        'input': input,
      };

  Map<String, dynamic> toWireParam() => {
        'type': 'server_tool_use',
        'id': id,
        'name': name,
        'kind': kind,
        'input': input,
      };

  factory ServerToolUseBlock.fromJson(Map<String, dynamic> json) =>
      ServerToolUseBlock(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        input: Map<String, dynamic>.from(json['input'] as Map? ?? const {}),
      );
}

class WebSearchResultItem {
  final String type; // 'web_search_result' | 'web_search_tool_result_error'
  final String title;
  final String url;
  final String? imageUrl;
  final String snippet;
  final String? siteIcon;
  final String? siteName;
  final String encryptedContent;
  final String? pageAge;
  final String? errorCode;

  const WebSearchResultItem({
    required this.type,
    this.title = '',
    this.url = '',
    this.imageUrl,
    this.snippet = '',
    this.siteIcon,
    this.siteName,
    this.encryptedContent = '',
    this.pageAge,
    this.errorCode,
  });

  bool get isError => type == 'web_search_tool_result_error';

  Map<String, dynamic> toJson() => isError
      ? {
          'type': 'web_search_tool_result_error',
          'error_code': errorCode ?? 'unavailable',
        }
      : {
          'type': 'web_search_result',
          'title': title,
          'url': url,
          if (imageUrl != null) 'image_url': imageUrl,
          'snippet': snippet,
          'site_icon': siteIcon,
          'site_name': siteName,
          'encrypted_content': encryptedContent,
          'page_age': pageAge,
        };

  static WebSearchResultItem? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final t = raw['type'];
    if (t == 'web_search_tool_result_error') {
      final ec = raw['error_code'];
      if (ec is! String) return null;
      return WebSearchResultItem(
        type: 'web_search_tool_result_error',
        errorCode: ec,
      );
    }
    if (t == 'web_search_result') {
      final url = raw['url'];
      final title = raw['title'];
      if (url is! String || title is! String) return null;
      return WebSearchResultItem(
        type: 'web_search_result',
        title: title,
        url: url,
        imageUrl: raw['image_url'] is String ? raw['image_url'] as String : null,
        snippet: raw['snippet'] is String ? raw['snippet'] as String : '',
        siteIcon: raw['site_icon'] is String ? raw['site_icon'] as String : null,
        siteName: raw['site_name'] is String ? raw['site_name'] as String : null,
        encryptedContent: raw['encrypted_content'] is String
            ? raw['encrypted_content'] as String
            : '',
        pageAge: raw['page_age'] is String ? raw['page_age'] as String : null,
      );
    }
    return null;
  }
}

class WebSearchToolResultBlock extends ReplyBlock {
  @override
  String get type => 'web_search_tool_result';
  final String toolUseId;
  final String kind;
  final List<WebSearchResultItem> content;

  const WebSearchToolResultBlock({
    required this.toolUseId,
    required this.kind,
    required this.content,
  });

  bool get hasError => content.any((e) => e.isError);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'web_search_tool_result',
        'tool_use_id': toolUseId,
        'kind': kind,
        'content': content.map((e) => e.toJson()).toList(),
      };

  factory WebSearchToolResultBlock.fromJson(Map<String, dynamic> json) {
    final items = <WebSearchResultItem>[];
    final rawList = json['content'];
    if (rawList is List) {
      for (final item in rawList) {
        final parsed = WebSearchResultItem.tryParse(item);
        if (parsed != null) items.add(parsed);
      }
    }
    return WebSearchToolResultBlock(
      toolUseId: json['tool_use_id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      content: items,
    );
  }
}

class WebFetchToolResultBlock extends ReplyBlock {
  @override
  String get type => 'web_fetch_tool_result';
  final String toolUseId;
  final String kind; // 'read_link' | 'deep_search'
  final String? signature;
  final Map<String, dynamic> content; // WebFetchResult or WebFetchToolResultError

  const WebFetchToolResultBlock({
    required this.toolUseId,
    required this.kind,
    this.signature,
    required this.content,
  });

  bool get isFetchResult => content['type'] == 'web_fetch_result';
  bool get isError => content['type'] == 'web_fetch_tool_result_error';

  String? get url => content['url'] as String?;
  String? get publishedAt => content['published_at'] as String?;

  String? get title {
    final doc = content['content'];
    if (doc is Map && doc['title'] is String) return doc['title'] as String;
    return null;
  }

  String? get textData {
    final doc = content['content'];
    if (doc is Map) {
      final src = doc['source'];
      if (src is Map && src['data'] is String) return src['data'] as String;
    }
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'web_fetch_tool_result',
        'tool_use_id': toolUseId,
        'kind': kind,
        if (signature != null) 'signature': signature,
        'content': content,
      };

  factory WebFetchToolResultBlock.fromJson(Map<String, dynamic> json) =>
      WebFetchToolResultBlock(
        toolUseId: json['tool_use_id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        signature: json['signature'] as String?,
        content: Map<String, dynamic>.from(json['content'] as Map? ?? const {}),
      );
}

/// Client tool_use marker (not stored in blocks, disables continuation prefix).
class ClientToolUsePlaceholder {
  const ClientToolUsePlaceholder();
}

// ---------------------------------------------------------------------------
// SSE Message Events
// ---------------------------------------------------------------------------

sealed class MessageEvent {
  const MessageEvent();
}

class MessageStartEvent extends MessageEvent {
  final String id;
  final String model;
  final MessageUsage? usage;

  const MessageStartEvent({
    required this.id,
    required this.model,
    this.usage,
  });
}

class ContentBlockStartEvent extends MessageEvent {
  final int index;
  final ReplyBlock? block;
  final bool isClientToolUse;

  const ContentBlockStartEvent({
    required this.index,
    this.block,
    this.isClientToolUse = false,
  });
}

class ContentBlockDeltaEvent extends MessageEvent {
  final int index;
  final String deltaType; // text_delta | thinking_delta | signature_delta | citations_delta
  final String? text;
  final String? thinking;
  final String? signature;
  final TextCitation? citation;

  const ContentBlockDeltaEvent({
    required this.index,
    required this.deltaType,
    this.text,
    this.thinking,
    this.signature,
    this.citation,
  });
}

class ContentBlockStopEvent extends MessageEvent {
  final int index;
  const ContentBlockStopEvent({required this.index});
}

class MessageDeltaEvent extends MessageEvent {
  final String stopReason; // 'end_turn' | 'max_tokens' | 'tool_use' | 'refusal'
  final StopDetails? stopDetails;
  final String? title;
  final MessageUsage? usage;

  const MessageDeltaEvent({
    required this.stopReason,
    this.stopDetails,
    this.title,
    this.usage,
  });
}

class MessageStopEvent extends MessageEvent {
  const MessageStopEvent();
}
