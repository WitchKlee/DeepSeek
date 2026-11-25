import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

import '../../l10n/app_strings.dart';
import '../../models/api_types.dart';
import '../../models/chat_models.dart';
import '../chat/branches.dart';
import '../chat/reply_logic.dart';
import 'chat_database.dart';

const int kExportFormatVersion = 3;

enum BackupErrorCode {
  invalidZip,
  newerVersion,
  invalidVersion,
  incomplete,
  invalidFiles,
}

class BackupException implements Exception {
  final BackupErrorCode code;
  final String? detail;
  const BackupException(this.code, [this.detail]);

  String localize(AppStrings s) {
    switch (code) {
      case BackupErrorCode.invalidZip:
        return s.backupInvalidZip;
      case BackupErrorCode.newerVersion:
        return s.backupNewerVersion;
      case BackupErrorCode.invalidVersion:
        return s.backupInvalidVersion;
      case BackupErrorCode.incomplete:
        return s.backupIncomplete;
      case BackupErrorCode.invalidFiles:
        return s.backupInvalidFiles;
    }
  }
}

String _safeName(String s) {
  final replaced = s.replaceAll(RegExp(r'[/\\]'), '_');
  if (replaced.isEmpty || replaced == '.' || replaced == '..') {
    return 'unnamed';
  }
  return replaced;
}

String _toIsoUtc(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String();

int? _parseIsoUtc(dynamic raw) {
  if (raw is! String) return null;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$')
      .hasMatch(raw)) {
    return null;
  }
  final dt = DateTime.tryParse(raw);
  return dt?.millisecondsSinceEpoch;
}

/// Magic-byte MIME sniffing matching `chat/history/importArchive.ts`.
String sniffImageMime(Uint8List bytes) {
  if (bytes.length < 12) return '';
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  final ascii6 = String.fromCharCodes(bytes.sublist(0, 6));
  if (ascii6 == 'GIF87a' || ascii6 == 'GIF89a') return 'image/gif';
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final webp = String.fromCharCodes(bytes.sublist(8, 12));
  if (riff == 'RIFF' && webp == 'WEBP') return 'image/webp';
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) return 'image/bmp';
  if ((bytes[0] == 0x49 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x2A &&
          bytes[3] == 0x00) ||
      (bytes[0] == 0x4D &&
          bytes[1] == 0x4D &&
          bytes[2] == 0x00 &&
          bytes[3] == 0x2A)) {
    return 'image/tiff';
  }
  final ftyp = String.fromCharCodes(bytes.sublist(4, 8));
  if (ftyp == 'ftyp' && (webp == 'avif' || webp == 'avis')) {
    return 'image/avif';
  }
  return '';
}

class HistoryBackupService {
  /// Exports all local sessions + local original images into a DeepSeek v3 ZIP archive.
  static Future<Uint8List> exportArchive({
    required List<ChatSession> sessions,
    required AppStrings strings,
    void Function(int processed, int total)? onProgress,
  }) async {
    final archive = Archive();
    final db = ChatDatabase.instance;

    // 1. manifest.json MUST be the very first entry
    final manifestBytes = utf8.encode(
      jsonEncode({'export_format_version': kExportFormatVersion}),
    );
    archive.addFile(
      ArchiveFile.noCompress('manifest.json', manifestBytes.length, manifestBytes),
    );

    final indexEntries = <Map<String, dynamic>>[];
    final imageEntries = <MapEntry<String, Uint8List>>[];
    final total = sessions.length;

    for (var sIdx = 0; sIdx < sessions.length; sIdx++) {
      final session = sessions[sIdx];
      normalizeSession(session);
      onProgress?.call(sIdx, total);

      // Collect local image blobs for this session
      final localImages = <String, Uint8List>{};
      for (final m in session.messages) {
        if (m is UserMessage) {
          for (final f in m.files) {
            if (f.isImage && !localImages.containsKey(f.id)) {
              final raw = await db.readLocalFile(f.id, f.localPath);
              if (raw != null) localImages[f.id] = raw;
            }
          }
        }
      }

      // Topological sort so parent_id < id (1..n)
      final ordered = _topologicalSort(session);
      final idMap = <String, int>{};
      for (var i = 0; i < ordered.length; i++) {
        idMap[ordered[i].id] = i + 1;
      }

      final visible = getVisibleMessages(session);
      final currentMsgId = visible.isEmpty ? 0 : (idMap[visible.last.id] ?? 0);

      // Map first assistant child per user message for thinking/search flags
      final firstChildByParent = <String, AssistantMessage>{};
      for (final m in ordered) {
        if (m is AssistantMessage &&
            m.parentId != null &&
            !firstChildByParent.containsKey(m.parentId)) {
          firstChildByParent[m.parentId!] = m;
        }
      }

      final exportedMessages = <Map<String, dynamic>>[];
      final addedImagePaths = <String>{};

      for (final m in ordered) {
        final numId = idMap[m.id]!;
        final parentNumId = m.parentId == null ? null : idMap[m.parentId!];

        if (m is UserMessage) {
          final child = firstChildByParent[m.id];
          final fragments = <Map<String, dynamic>>[];
          if (m.files.isNotEmpty) {
            final fileList = <Map<String, dynamic>>[];
            for (final f in m.files) {
              String? exportPath;
              if (f.isImage && localImages.containsKey(f.id)) {
                final ep =
                    'chat_sessions/${session.id}_files/${_safeName(f.id)}_${_safeName(f.name)}';
                exportPath = ep;
                if (addedImagePaths.add(ep)) {
                  imageEntries.add(MapEntry(ep, localImages[f.id]!));
                }
              }
              fileList.add({
                'id': f.id,
                'file_name': f.name,
                'file_size': f.size,
                'token_usage': null,
                'inserted_at': _toIsoUtc(m.createdAt),
                'export_path': exportPath,
                'is_image': f.isImage,
                'width': null,
                'height': null,
              });
            }
            fragments.add({'type': 'FILE', 'files': fileList});
          }
          fragments.add({'type': 'REQUEST', 'content': m.content});

          exportedMessages.add({
            'id': numId,
            'parent_id': parentNumId,
            'role': 'USER',
            'status': 'FINISHED',
            'thinking_enabled': child?.thinking ?? false,
            'search_enabled': child?.search ?? false,
            'accumulated_token_usage': 0,
            'inserted_at': _toIsoUtc(m.createdAt),
            'fragments': fragments,
          });
        } else if (m is AssistantMessage) {
          final statusStr = _exportStatus(m);
          final fragments = _exportAssistantFragments(m, strings);
          exportedMessages.add({
            'id': numId,
            'parent_id': parentNumId,
            'role': 'ASSISTANT',
            'status': statusStr,
            'thinking_enabled': m.thinking,
            'search_enabled': m.search,
            'accumulated_token_usage': m.usage?.totalTokens ?? 0,
            'inserted_at': _toIsoUtc(m.createdAt),
            'fragments': fragments,
          });
        }
      }

      final sessionJson = {
        'id': session.id,
        'title': session.title.isEmpty ? null : session.title,
        'pinned': false,
        'current_message_id': currentMsgId,
        'inserted_at': _toIsoUtc(session.createdAt),
        'updated_at': _toIsoUtc(session.updatedAt),
        'messages': exportedMessages,
      };
      final sessionBytes = utf8.encode(jsonEncode(sessionJson));
      archive.addFile(ArchiveFile.noCompress(
        'chat_sessions/${session.id}.json',
        sessionBytes.length,
        sessionBytes,
      ));

      indexEntries.add({
        'id': session.id,
        'title': session.title.isEmpty ? null : session.title,
        'pinned': false,
        'message_count': exportedMessages.length,
        'inserted_at': _toIsoUtc(session.createdAt),
        'updated_at': _toIsoUtc(session.updatedAt),
      });
    }

    // chat_session_index.json
    final indexBytes = utf8.encode(jsonEncode(indexEntries));
    archive.addFile(ArchiveFile.noCompress(
      'chat_session_index.json',
      indexBytes.length,
      indexBytes,
    ));

    // Image files last
    for (final entry in imageEntries) {
      archive.addFile(ArchiveFile.noCompress(
        entry.key,
        entry.value.length,
        entry.value,
      ));
    }

    onProgress?.call(total, total);
    final zipData = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipData);
  }

  /// Imports a DeepSeek v3 ZIP archive and validates structure, schemas, and trees.
  static Future<({List<ChatSession> sessions, Map<String, Uint8List> blobs})>
      parseImportArchive(
    Uint8List zipBytes, {
    void Function(int processed, int total)? onProgress,
  }) async {
    // Check ZIP local header magic bytes PK\x03\x04
    if (zipBytes.length < 4 ||
        zipBytes[0] != 0x50 ||
        zipBytes[1] != 0x4B ||
        zipBytes[2] != 0x03 ||
        zipBytes[3] != 0x04) {
      throw const BackupException(BackupErrorCode.invalidZip);
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    } catch (_) {
      throw const BackupException(BackupErrorCode.invalidZip);
    }

    final files = archive.files.where((f) => f.isFile).toList();
    if (files.isEmpty) {
      throw const BackupException(BackupErrorCode.incomplete);
    }

    // Validate path hygiene & duplicates
    final seenPaths = <String>{};
    for (final f in files) {
      final name = f.name;
      if (name.contains('\\') ||
          name.contains('\u0000') ||
          RegExp(r'^[A-Za-z]:').hasMatch(name)) {
        throw const BackupException(BackupErrorCode.invalidZip);
      }
      final segs = name.split('/');
      if (segs.any((s) => s.isEmpty || s == '.' || s == '..')) {
        throw const BackupException(BackupErrorCode.invalidZip);
      }
      if (!seenPaths.add(name)) {
        throw const BackupException(BackupErrorCode.invalidZip);
      }
    }

    // 1. manifest.json MUST be first
    if (files.first.name != 'manifest.json') {
      throw const BackupException(BackupErrorCode.incomplete);
    }
    try {
      final manifest =
          jsonDecode(utf8.decode(files.first.content as List<int>));
      if (manifest is! Map || manifest['export_format_version'] is! int) {
        throw const BackupException(BackupErrorCode.invalidVersion);
      }
      final ver = manifest['export_format_version'] as int;
      if (ver > kExportFormatVersion) {
        throw const BackupException(BackupErrorCode.newerVersion);
      }
      if (ver != kExportFormatVersion) {
        throw const BackupException(BackupErrorCode.invalidVersion);
      }
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException(BackupErrorCode.incomplete);
    }

    final sessionFiles = <String, ArchiveFile>{};
    ArchiveFile? indexFile;
    final rawAttachmentsByPath = <String, Uint8List>{};

    for (final f in files.skip(1)) {
      if (f.name == 'user.json') continue;
      if (f.name == 'chat_session_index.json') {
        indexFile = f;
      } else if (f.name.startsWith('chat_sessions/') &&
          f.name.endsWith('.json') &&
          !f.name.substring('chat_sessions/'.length).contains('/')) {
        final sid = f.name
            .substring('chat_sessions/'.length, f.name.length - '.json'.length);
        if (sid.isEmpty || sid == '.' || sid == '..') {
          throw const BackupException(BackupErrorCode.incomplete);
        }
        sessionFiles[sid] = f;
      } else if (f.name.startsWith('chat_sessions/')) {
        rawAttachmentsByPath[f.name] =
            Uint8List.fromList(f.content as List<int>);
      }
    }

    if (indexFile == null) {
      throw const BackupException(BackupErrorCode.incomplete);
    }

    // Parse chat_session_index.json
    final Set<String> indexedIds = {};
    try {
      final rawIndex = jsonDecode(utf8.decode(indexFile.content as List<int>));
      if (rawIndex is! List) {
        throw const BackupException(BackupErrorCode.incomplete);
      }
      for (final item in rawIndex) {
        if (item is! Map || item['id'] is! String) {
          throw const BackupException(BackupErrorCode.incomplete);
        }
        if (!indexedIds.add(item['id'] as String)) {
          throw const BackupException(BackupErrorCode.incomplete);
        }
      }
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException(BackupErrorCode.incomplete);
    }

    if (indexedIds.length != sessionFiles.length ||
        !indexedIds.containsAll(sessionFiles.keys)) {
      throw const BackupException(BackupErrorCode.incomplete);
    }

    final sessions = <ChatSession>[];
    final imageBlobs = <String, Uint8List>{};
    final pathToFileId = <String, String>{};
    final total = sessionFiles.length;
    var processed = 0;

    for (final entry in sessionFiles.entries) {
      final sid = entry.key;
      final file = entry.value;
      Map<String, dynamic> decoded;
      try {
        final raw = jsonDecode(utf8.decode(file.content as List<int>));
        if (raw is! Map<String, dynamic>) {
          throw const BackupException(BackupErrorCode.incomplete);
        }
        decoded = raw;
      } on BackupException {
        rethrow;
      } catch (_) {
        throw const BackupException(BackupErrorCode.incomplete);
      }

      final session = _importSession(
        expectedId: sid,
        json: decoded,
        rawAttachmentsByPath: rawAttachmentsByPath,
        pathToFileId: pathToFileId,
        imageBlobs: imageBlobs,
      );
      sessions.add(session);
      processed++;
      onProgress?.call(processed, total);
    }

    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return (sessions: sessions, blobs: imageBlobs);
  }

  static ChatSession _importSession({
    required String expectedId,
    required Map<String, dynamic> json,
    required Map<String, Uint8List> rawAttachmentsByPath,
    required Map<String, String> pathToFileId,
    required Map<String, Uint8List> imageBlobs,
  }) {
    if (json['id'] != expectedId) {
      throw const BackupException(BackupErrorCode.incomplete);
    }
    final createdAt = _parseIsoUtc(json['inserted_at']);
    final updatedAt = _parseIsoUtc(json['updated_at']);
    if (createdAt == null || updatedAt == null) {
      throw const BackupException(BackupErrorCode.incomplete);
    }
    final title = json['title'] is String ? json['title'] as String : '';
    final rawMsgs = json['messages'];
    if (rawMsgs is! List) {
      throw const BackupException(BackupErrorCode.incomplete);
    }

    final rawList = <Map<String, dynamic>>[];
    for (final item in rawMsgs) {
      if (item is! Map) throw const BackupException(BackupErrorCode.incomplete);
      rawList.add(Map<String, dynamic>.from(item));
    }
    rawList.sort((a, b) => ((a['id'] as num?)?.toInt() ?? 0)
        .compareTo((b['id'] as num?)?.toInt() ?? 0));

    final seenIds = <int, String>{};
    final roleByNumId = <int, String>{};
    final msgByNumId = <int, ChatMessage>{};
    final localMsgs = <ChatMessage>[];
    final expectedFilePrefix = 'chat_sessions/${expectedId}_files/';

    for (final rm in rawList) {
      final numId = rm['id'];
      final parentNumId = rm['parent_id'];
      final role = rm['role'];
      final msgTs = _parseIsoUtc(rm['inserted_at']);
      final frags = rm['fragments'];
      if (numId is! int ||
          (parentNumId != null && parentNumId is! int) ||
          (role != 'USER' && role != 'ASSISTANT') ||
          msgTs == null ||
          frags is! List) {
        throw const BackupException(BackupErrorCode.incomplete);
      }
      if (seenIds.containsKey(numId)) {
        throw const BackupException(BackupErrorCode.incomplete);
      }
      if (parentNumId == null) {
        if (role != 'USER') {
          throw const BackupException(BackupErrorCode.incomplete);
        }
      } else {
        if (!seenIds.containsKey(parentNumId) ||
            roleByNumId[parentNumId] == role) {
          throw const BackupException(BackupErrorCode.incomplete);
        }
      }

      final localId = 'msg-$expectedId-$numId';
      final parentLocalId = parentNumId == null ? null : seenIds[parentNumId];
      seenIds[numId] = localId;
      roleByNumId[numId] = role as String;

      if (role == 'USER') {
        final reqTexts = <String>[];
        final files = <FileAttachment>[];
        for (final frag in frags) {
          if (frag is! Map) continue;
          if (frag['type'] == 'REQUEST' && frag['content'] is String) {
            reqTexts.add(frag['content'] as String);
          } else if (frag['type'] == 'FILE' && frag['files'] is List) {
            for (final fe in frag['files'] as List) {
              if (fe is! Map || fe['id'] is! String) continue;
              final fid = fe['id'] as String;
              final fname = fe['file_name'] is String
                  ? fe['file_name'] as String
                  : 'unnamed';
              final fsize = (fe['file_size'] as num?)?.toInt() ?? 0;
              final isImg = fe['is_image'] == true;
              final exportPath = fe['export_path'] as String?;
              var mime = '';
              if (exportPath != null) {
                if (!exportPath.startsWith(expectedFilePrefix)) {
                  throw const BackupException(BackupErrorCode.invalidFiles);
                }
                final prevOwner = pathToFileId[exportPath];
                if (prevOwner != null && prevOwner != fid) {
                  throw const BackupException(BackupErrorCode.invalidFiles);
                }
                pathToFileId[exportPath] = fid;
                final blob = rawAttachmentsByPath[exportPath];
                if (blob != null) {
                  imageBlobs.putIfAbsent(fid, () => blob);
                  mime = sniffImageMime(blob);
                }
              }
              files.add(FileAttachment(
                id: fid,
                serverId: null,
                name: fname,
                size: fsize,
                isImage: isImg,
                mimeType: mime,
              ));
            }
          }
        }
        final msg = UserMessage(
          id: localId,
          parentId: parentLocalId,
          createdAt: msgTs,
          content: reqTexts.join('\n'),
          files: files,
        );
        msgByNumId[numId] = msg;
        localMsgs.add(msg);
      } else {
        final rawStatus = rm['status'] as String? ?? 'FINISHED';
        final hasDeepTool = frags.any(
          (f) => f is Map && (f['type'] == 'TOOL_OPEN' || f['type'] == 'TOOL_FIND'),
        );
        final blocks = <ReplyBlock>[];
        for (var fi = 0; fi < frags.length; fi++) {
          final frag = frags[fi];
          if (frag is! Map) continue;
          final fType = frag['type'];
          switch (fType) {
            case 'THINK':
              if (frag['content'] is String) {
                blocks.add(ThinkingPart(
                  thinking: frag['content'] as String,
                  elapsedSeconds: (frag['elapsed_secs'] as num?)?.toDouble(),
                ));
              }
              break;
            case 'RESPONSE':
              if (frag['content'] is String) {
                blocks.add(TextPart(text: frag['content'] as String));
              }
              break;
            case 'TEMPLATE_RESPONSE':
              if (frag['content'] is String) {
                blocks.add(TextPart(
                  text: frag['content'] as String,
                  isTemplate: true,
                ));
              }
              break;
            case 'TOOL_SEARCH':
              final tid = 'history-$numId-$fi';
              final kind = hasDeepTool ? 'deep_search' : 'search';
              final queries = (frag['queries'] as List?)
                      ?.whereType<String>()
                      .toList() ??
                  const [];
              blocks.add(ServerToolUseBlock(
                id: tid,
                name: 'deepseek_web_search',
                kind: kind,
                input: {'action': 'search', 'queries': queries},
              ));
              final st = frag['status'] as String?;
              if (st == 'FAILED') {
                blocks.add(WebSearchToolResultBlock(
                  toolUseId: tid,
                  kind: kind,
                  content: const [
                    WebSearchResultItem(
                      type: 'web_search_tool_result_error',
                      errorCode: 'unavailable',
                    ),
                  ],
                ));
              } else {
                final results = <WebSearchResultItem>[];
                if (frag['results'] is List) {
                  for (final r in frag['results'] as List) {
                    if (r is Map && r['url'] is String && r['title'] is String) {
                      results.add(WebSearchResultItem(
                        type: 'web_search_result',
                        url: r['url'] as String,
                        title: r['title'] as String,
                        snippet: r['snippet'] is String ? r['snippet'] as String : '',
                        siteName: r['site_name'] as String?,
                        siteIcon: r['site_icon'] as String?,
                        pageAge: r['published_at'] as String?,
                      ));
                    }
                  }
                }
                blocks.add(WebSearchToolResultBlock(
                  toolUseId: tid,
                  kind: kind,
                  content: results,
                ));
              }
              break;
            case 'TOOL_OPEN':
              final tid = 'history-$numId-$fi';
              final url = frag['url'] as String? ?? '';
              blocks.add(ServerToolUseBlock(
                id: tid,
                name: 'deepseek_web_search',
                kind: 'deep_search',
                input: {'action': 'open_page', 'url': url},
              ));
              final st = frag['status'] as String?;
              if (st == 'FINISHED') {
                blocks.add(WebFetchToolResultBlock(
                  toolUseId: tid,
                  kind: 'deep_search',
                  content: {
                    'type': 'web_fetch_result',
                    'url': url,
                    'content': {
                      'type': 'document',
                      'source': {
                        'type': 'text',
                        'media_type': 'text/plain',
                        'data': frag['snippet'] as String? ?? '',
                      },
                      'title': frag['title'],
                    },
                    'published_at': frag['published_at'],
                  },
                ));
              } else if (st == 'FAILED') {
                blocks.add(WebFetchToolResultBlock(
                  toolUseId: tid,
                  kind: 'deep_search',
                  content: {
                    'type': 'web_fetch_tool_result_error',
                    'error_code': 'unavailable',
                  },
                ));
              }
              break;
            case 'TOOL_FIND':
              final tid = 'history-$numId-$fi';
              blocks.add(ServerToolUseBlock(
                id: tid,
                name: 'deepseek_web_search',
                kind: 'deep_search',
                input: {
                  'action': 'find_in_page',
                  'url': '',
                  'pattern': frag['pattern'] as String? ?? '',
                },
              ));
              final st = frag['status'] as String?;
              blocks.add(WebFetchToolResultBlock(
                toolUseId: tid,
                kind: 'deep_search',
                content: st == 'FINISHED'
                    ? {
                        'type': 'web_fetch_result',
                        'url': '',
                        'content': {
                          'type': 'document',
                          'source': {
                            'type': 'text',
                            'media_type': 'text/plain',
                            'data': '',
                          },
                          'title': null,
                        },
                        'published_at': null,
                      }
                    : {
                        'type': 'web_fetch_tool_result_error',
                        'error_code': 'unavailable',
                      },
              ));
              break;
            case 'READ_LINK':
              if (frag['results'] is List) {
                final list = frag['results'] as List;
                for (var ri = 0; ri < list.length; ri++) {
                  final r = list[ri];
                  if (r is! Map || r['signature'] is! String) continue;
                  final tid = 'history-$numId-$fi-$ri';
                  final url = r['url'] as String? ?? '';
                  blocks.add(ServerToolUseBlock(
                    id: tid,
                    name: 'deepseek_read_url',
                    kind: 'read_link',
                    input: {'action': 'read_link', 'url': url},
                  ));
                  blocks.add(WebFetchToolResultBlock(
                    toolUseId: tid,
                    kind: 'read_link',
                    signature: r['signature'] as String,
                    content: {
                      'type': 'web_fetch_result',
                      'url': url,
                      'content': {
                        'type': 'document',
                        'source': {
                          'type': 'text',
                          'media_type': 'text/plain',
                          'data': '',
                        },
                        'title': r['title'],
                      },
                      'published_at': null,
                    },
                  ));
                }
              }
              break;
            default:
              // TIP, CONTENT_RISK, PARTIAL_FILE_READ, TOOL_IMAGE_SEARCH dropped per spec
              break;
          }
        }

        ReplyStatus status;
        String? stopReason;
        switch (rawStatus) {
          case 'FINISHED':
            status = ReplyStatus.done;
            break;
          case 'CONTENT_FILTER':
            status = ReplyStatus.done;
            stopReason = 'refusal';
            blocks.removeWhere(
              (b) => b is ThinkingPart || (b is TextPart && !b.isTemplate),
            );
            break;
          case 'INCOMPLETE':
          case 'WIP':
            status = ReplyStatus.stopped;
            break;
          default:
            status = ReplyStatus.error;
            break;
        }

        final msg = AssistantMessage(
          id: localId,
          parentId: parentLocalId,
          createdAt: msgTs,
          model: null,
          thinking: rm['thinking_enabled'] == true,
          search: rm['search_enabled'] == true,
          prefix: false,
          status: status,
          blocks: blocks,
          stopReason: stopReason,
        );
        msgByNumId[numId] = msg;
        localMsgs.add(msg);
      }
    }

    // Default every parent's selectedChildId to its highest-id child
    for (final rm in rawList) {
      final numId = rm['id'] as int;
      final parentNumId = rm['parent_id'] as int?;
      if (parentNumId != null) {
        msgByNumId[parentNumId]!.selectedChildId = msgByNumId[numId]!.id;
      }
    }

    String? rootId;
    if (rawList.isNotEmpty) {
      final curNumId = json['current_message_id'];
      if (curNumId is! int || !msgByNumId.containsKey(curNumId)) {
        throw const BackupException(BackupErrorCode.incomplete);
      }
      // Walk up from current_message_id to root
      var walkId = curNumId;
      msgByNumId[walkId]!.selectedChildId = null;
      while (true) {
        final rawNode = rawList.firstWhere((r) => r['id'] == walkId);
        final pId = rawNode['parent_id'] as int?;
        if (pId == null) {
          rootId = msgByNumId[walkId]!.id;
          break;
        }
        msgByNumId[pId]!.selectedChildId = msgByNumId[walkId]!.id;
        walkId = pId;
      }
    }

    return ChatSession(
      id: expectedId,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      rootMessageId: rootId,
      messages: localMsgs,
    );
  }

  static List<ChatMessage> _topologicalSort(ChatSession session) {
    final byParent = <String?, List<ChatMessage>>{};
    for (final m in session.messages) {
      byParent.putIfAbsent(m.parentId, () => []).add(m);
    }
    final out = <ChatMessage>[];
    final visited = <String>{};
    void visit(String? parentId) {
      final children = byParent[parentId];
      if (children == null) return;
      for (final child in children) {
        if (visited.add(child.id)) {
          out.add(child);
          visit(child.id);
        }
      }
    }

    visit(null);
    for (final m in session.messages) {
      if (visited.add(m.id)) out.add(m);
    }
    return out;
  }

  static String _exportStatus(AssistantMessage m) {
    if (m.stopReason == 'refusal') return 'CONTENT_FILTER';
    if (m.status == ReplyStatus.done && m.stopReason == 'max_tokens') {
      return 'INCOMPLETE';
    }
    switch (m.status) {
      case ReplyStatus.done:
        return 'FINISHED';
      case ReplyStatus.stopped:
        return 'INCOMPLETE';
      case ReplyStatus.error:
        return 'FAILED';
      case ReplyStatus.pending:
      case ReplyStatus.streaming:
        return 'WIP';
    }
  }

  static List<Map<String, dynamic>> _exportAssistantFragments(
    AssistantMessage m,
    AppStrings strings,
  ) {
    final hasTools = hasServerToolBlocks(m);
    final searchResById = <String, WebSearchToolResultBlock>{};
    final fetchResById = <String, WebFetchToolResultBlock>{};
    for (final b in m.blocks) {
      if (b is WebSearchToolResultBlock) searchResById[b.toolUseId] = b;
      if (b is WebFetchToolResultBlock) fetchResById[b.toolUseId] = b;
    }

    final frags = <Map<String, dynamic>>[];

    void pushTextFrag(String type, String text) {
      if (text.isEmpty) return;
      if (frags.isNotEmpty && frags.last['type'] == type) {
        frags.last['content'] = '${frags.last['content']}$text';
      } else {
        frags.add({'type': type, 'content': text});
      }
    }

    for (final b in m.blocks) {
      if (b is ThinkingPart) {
        double? secs = b.elapsedSeconds;
        if (secs == null && b.startedAt != null && b.endedAt != null) {
          secs = ((b.endedAt! - b.startedAt!) / 1000.0).clamp(0, 86400);
        }
        frags.add({
          'type': 'THINK',
          'content': b.thinking,
          'elapsed_secs': secs,
        });
      } else if (b is TextPart) {
        final cleaned = hasTools && !b.isTemplate
            ? b.text.replaceAll(RegExp(r'\[citation:\d+\]'), '')
            : b.text;
        pushTextFrag(b.isTemplate ? 'TEMPLATE_RESPONSE' : 'RESPONSE', cleaned);
      } else if (b is ServerToolUseBlock) {
        if (b.action == 'search') {
          final res = searchResById[b.id];
          final items = <Map<String, dynamic>>[];
          var st = 'WIP';
          if (res != null) {
            st = res.hasError ? 'FAILED' : 'FINISHED';
            for (final r in res.content) {
              if (!r.isError) {
                items.add({
                  'url': r.url,
                  'title': r.title,
                  'snippet': r.snippet,
                  'published_at': r.pageAge,
                  'site_name': r.siteName,
                  'site_icon': r.siteIcon,
                });
              }
            }
          }
          frags.add({
            'type': 'TOOL_SEARCH',
            'queries': b.queries,
            'results': items,
            'status': st,
          });
        } else if (b.action == 'open_page') {
          final res = fetchResById[b.id];
          frags.add({
            'type': 'TOOL_OPEN',
            'status': res == null
                ? 'WIP'
                : (res.isFetchResult ? 'FINISHED' : 'FAILED'),
            'url': res?.url ?? b.url,
            'title': res?.title,
            'snippet': res?.textData,
            'site_name': null,
            'published_at': res?.publishedAt,
          });
        } else if (b.action == 'find_in_page') {
          final res = fetchResById[b.id];
          frags.add({
            'type': 'TOOL_FIND',
            'status': res == null
                ? 'WIP'
                : (res.isFetchResult ? 'FINISHED' : 'FAILED'),
            'pattern': b.pattern,
          });
        } else if (b.action == 'read_link') {
          final res = fetchResById[b.id];
          if (res != null &&
              res.isFetchResult &&
              res.signature != null &&
              res.signature!.trim().isNotEmpty) {
            frags.add({
              'type': 'READ_LINK',
              'results': [
                {
                  'url': res.url ?? b.url,
                  'title': res.title,
                  'signature': res.signature!,
                }
              ],
            });
          }
        }
      }
    }

    final notice = describeReply(m, strings);
    if (notice != null &&
        ((m.status == ReplyStatus.error && m.error != null) ||
            (!hasTemplateBlock(m) && m.stopReason == 'refusal'))) {
      pushTextFrag('TEMPLATE_RESPONSE', notice.text);
    }

    return frags;
  }
}
