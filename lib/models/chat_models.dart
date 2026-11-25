import 'api_types.dart';

class FileAttachment {
  final String id;
  String? serverId;
  bool imageSizeChecked;
  final String name;
  final int size;
  final bool isImage;
  String mimeType;
  String? localPath;

  FileAttachment({
    required this.id,
    this.serverId,
    this.imageSizeChecked = false,
    required this.name,
    required this.size,
    required this.isImage,
    required this.mimeType,
    this.localPath,
  });

  FileAttachment clone() => FileAttachment(
        id: id,
        serverId: serverId,
        imageSizeChecked: imageSizeChecked,
        name: name,
        size: size,
        isImage: isImage,
        mimeType: mimeType,
        localPath: localPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'imageSizeChecked': imageSizeChecked,
        'name': name,
        'size': size,
        'isImage': isImage,
        'mimeType': mimeType,
        if (localPath != null) 'localPath': localPath,
      };

  factory FileAttachment.fromJson(Map<String, dynamic> json) => FileAttachment(
        id: json['id'] as String,
        serverId: json['serverId'] as String?,
        imageSizeChecked: json['imageSizeChecked'] == true,
        name: json['name'] as String? ?? 'unnamed',
        size: (json['size'] as num?)?.toInt() ?? 0,
        isImage: json['isImage'] == true,
        mimeType: json['mimeType'] as String? ?? '',
        localPath: json['localPath'] as String?,
      );
}

enum DraftUploadStatus { uploading, done, error }

class DraftAttachment {
  final FileAttachment file;
  DraftUploadStatus status;
  String? errorMessage;
  bool retryable;

  DraftAttachment({
    required this.file,
    this.status = DraftUploadStatus.uploading,
    this.errorMessage,
    this.retryable = true,
  });
}

enum ReplyStatus { pending, streaming, done, stopped, error }

class ReplyError {
  final String kind; // 'http' | 'stream' | 'network' | 'interrupted' | 'protocol' | 'upload'
  final String message;
  final int? status;
  final bool retryable;

  const ReplyError({
    required this.kind,
    required this.message,
    this.status,
    this.retryable = true,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'message': message,
        if (status != null) 'status': status,
        'retryable': retryable,
      };

  factory ReplyError.fromJson(Map<String, dynamic> json) => ReplyError(
        kind: json['kind'] as String? ?? 'http',
        message: json['message'] as String? ?? '',
        status: (json['status'] as num?)?.toInt(),
        retryable: json['retryable'] != false,
      );
}

sealed class ChatMessage {
  final String id;
  String? parentId;
  String? selectedChildId;
  final int createdAt;

  ChatMessage({
    required this.id,
    this.parentId,
    this.selectedChildId,
    required this.createdAt,
  });

  String get role;
  Map<String, dynamic> toJson();

  static ChatMessage fromJson(Map<String, dynamic> json) {
    if (json['role'] == 'user') {
      return UserMessage.fromJson(json);
    }
    return AssistantMessage.fromJson(json);
  }
}

class UserMessage extends ChatMessage {
  @override
  String get role => 'user';
  final String content;
  final List<FileAttachment> files;

  UserMessage({
    required super.id,
    super.parentId,
    super.selectedChildId,
    required super.createdAt,
    required this.content,
    List<FileAttachment>? files,
  }) : files = files ?? [];

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': 'user',
        if (parentId != null) 'parentId': parentId,
        if (selectedChildId != null) 'selectedChildId': selectedChildId,
        'createdAt': createdAt,
        'content': content,
        'files': files.map((f) => f.toJson()).toList(),
      };

  factory UserMessage.fromJson(Map<String, dynamic> json) => UserMessage(
        id: json['id'] as String,
        parentId: json['parentId'] as String?,
        selectedChildId: json['selectedChildId'] as String?,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        content: json['content'] as String? ?? '',
        files: (json['files'] as List?)
                ?.whereType<Map>()
                .map((e) => FileAttachment.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
      );
}

class AssistantMessage extends ChatMessage {
  @override
  String get role => 'assistant';
  String? model;
  bool thinking;
  bool search;
  String? latestReminder;
  bool prefix;
  ReplyStatus status;
  List<ReplyBlock> blocks;
  String? stopReason;
  StopDetails? stopDetails;
  MessageUsage? usage;
  ReplyError? error;

  AssistantMessage({
    required super.id,
    super.parentId,
    super.selectedChildId,
    required super.createdAt,
    this.model,
    this.thinking = false,
    this.search = false,
    this.latestReminder,
    this.prefix = true,
    this.status = ReplyStatus.pending,
    List<ReplyBlock>? blocks,
    this.stopReason,
    this.stopDetails,
    this.usage,
    this.error,
  }) : blocks = blocks ?? [];

  bool get isStreaming =>
      status == ReplyStatus.pending || status == ReplyStatus.streaming;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': 'assistant',
        if (parentId != null) 'parentId': parentId,
        if (selectedChildId != null) 'selectedChildId': selectedChildId,
        'createdAt': createdAt,
        'model': model,
        'thinking': thinking,
        'search': search,
        if (latestReminder != null) 'latestReminder': latestReminder,
        'prefix': prefix,
        'status': status.name,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        if (stopReason != null) 'stopReason': stopReason,
        if (stopDetails != null) 'stopDetails': stopDetails!.toJson(),
        if (usage != null) 'usage': usage!.toJson(),
        if (error != null) 'error': error!.toJson(),
      };

  factory AssistantMessage.fromJson(Map<String, dynamic> json) {
    final parsedBlocks = <ReplyBlock>[];
    final rawBlocks = json['blocks'];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is Map) {
          final parsed = ReplyBlock.fromJson(Map<String, dynamic>.from(b));
          if (parsed != null) parsedBlocks.add(parsed);
        }
      }
    }
    return AssistantMessage(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      selectedChildId: json['selectedChildId'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      model: json['model'] as String?,
      thinking: json['thinking'] == true,
      search: json['search'] == true,
      latestReminder: json['latestReminder'] as String?,
      prefix: json['prefix'] != false,
      status: ReplyStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ReplyStatus.done,
      ),
      blocks: parsedBlocks,
      stopReason: json['stopReason'] as String?,
      stopDetails: StopDetails.tryParse(json['stopDetails']),
      usage: MessageUsage.tryParse(json['usage']),
      error: json['error'] is Map
          ? ReplyError.fromJson(Map<String, dynamic>.from(json['error'] as Map))
          : null,
    );
  }
}

class ChatSession {
  final String id;
  String title;
  final int createdAt;
  int updatedAt;
  List<ChatMessage> messages;
  String? rootMessageId;

  ChatSession({
    required this.id,
    this.title = '',
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessage>? messages,
    this.rootMessageId,
  }) : messages = messages ?? [];

  SessionSummary toSummary() => SessionSummary(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'rootMessageId': rootMessageId,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        rootMessageId: json['rootMessageId'] as String?,
        messages: (json['messages'] as List?)
                ?.whereType<Map>()
                .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            [],
      );
}

class SessionSummary {
  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;

  const SessionSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
}

class MessageVersionInfo {
  final List<String> ids;
  final int index;

  const MessageVersionInfo({required this.ids, required this.index});

  int get total => ids.length;
  bool get hasMultiple => ids.length > 1;
}

// ---------------------------------------------------------------------------
// Derived Reply View & Timeline Models (matching chat/view.ts)
// ---------------------------------------------------------------------------

enum StepStatus { wip, done, failed }

class ReplySource {
  final int index;
  final String url;
  String title;
  String siteName;
  String? publishedAt;
  String snippet;
  String? siteIcon;

  ReplySource({
    required this.index,
    required this.url,
    required this.title,
    required this.siteName,
    this.publishedAt,
    this.snippet = '',
    this.siteIcon,
  });
}

sealed class ReplyStep {
  final String key;
  const ReplyStep(this.key);
}

class ThinkingStep extends ReplyStep {
  final String markdown;
  final bool active;
  const ThinkingStep({
    required String key,
    required this.markdown,
    required this.active,
  }) : super(key);
}

class PreambleTextStep extends ReplyStep {
  final String markdown;
  const PreambleTextStep({required String key, required this.markdown})
      : super(key);
}

class SearchStep extends ReplyStep {
  final String kind; // 'search' | 'deep_search' | 'image_search' | 'deep_image_search'
  final List<String> queries;
  final List<ReplySource> results;
  final StepStatus status;

  const SearchStep({
    required String key,
    required this.kind,
    required this.queries,
    required this.results,
    required this.status,
  }) : super(key);

  bool get isDeep => kind == 'deep_search' || kind == 'deep_image_search';
  bool get isImage => kind == 'image_search' || kind == 'deep_image_search';
}

class OpenPageItem {
  final String url;
  final String title;
  final StepStatus status;
  const OpenPageItem({
    required this.url,
    required this.title,
    required this.status,
  });
}

class OpenStep extends ReplyStep {
  final List<OpenPageItem> pages;
  final StepStatus status;

  const OpenStep({
    required String key,
    required this.pages,
    required this.status,
  }) : super(key);
}

class FindItem {
  final String pattern;
  final StepStatus status;
  const FindItem({required this.pattern, required this.status});
}

class FindStep extends ReplyStep {
  final List<FindItem> items;
  final StepStatus status;

  const FindStep({
    required String key,
    required this.items,
    required this.status,
  }) : super(key);
}

class ReadLinkStep extends ReplyStep {
  final List<OpenPageItem> pages;
  final StepStatus status;

  const ReadLinkStep({
    required String key,
    required this.pages,
    required this.status,
  }) : super(key);
}

class ReplyView {
  final List<ReplyStep> steps;
  final String answer;
  final Map<int, ReplySource> sourcesByIndex;
  final List<ReplySource> searchResults;

  const ReplyView({
    required this.steps,
    required this.answer,
    required this.sourcesByIndex,
    required this.searchResults,
  });
}

enum NoticeAction { apiKey, topUp }

class ReplyNotice {
  final String text;
  final bool asResponse;
  final NoticeAction? action;

  const ReplyNotice({
    required this.text,
    this.asResponse = false,
    this.action,
  });
}
