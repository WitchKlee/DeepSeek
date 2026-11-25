import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../data/upload_exts.dart';
import '../models/api_types.dart';
import '../models/chat_models.dart';
import '../services/api/api_errors.dart';
import '../services/chat/branches.dart';
import '../services/chat/latest_reminder.dart';
import '../services/chat/reply_logic.dart';
import '../services/storage/chat_database.dart';
import '../services/storage/history_backup.dart';
import '../services/storage/image_resizer.dart';
import 'settings_provider.dart';

const _uuid = Uuid();
const int _kFileRetryLimit = 2;
const int _kFileRetryBaseDelayMs = 1000;

class ChatProvider extends ChangeNotifier {
  final SettingsProvider settingsProvider;
  final ChatDatabase _db = ChatDatabase.instance;

  ChatProvider(this.settingsProvider);

  List<SessionSummary> _summaries = [];
  ChatSession? _activeSession;
  bool _loading = true;
  bool _saveFailed = false;

  // Per-session draft attachments (key: sessionId ?? '')
  final Map<String, List<DraftAttachment>> _drafts = {};
  final Map<String, String> _draftTexts = {};

  // Active streaming state
  String? _streamingSessionId;
  http.Client? _streamClient;
  bool _userStopped = false;
  final Set<String> _titleRequests = {};

  // Concurrent upload queue (max 3)
  int _activeUploads = 0;
  final List<Future<void> Function()> _uploadQueue = [];

  // Search panel state
  List<ReplySource>? _searchPanelSources;
  bool _isHistoryOpBusy = false;

  List<SessionSummary> get summaries => _summaries;
  ChatSession? get activeSession => _activeSession;
  bool get loading => _loading;
  bool get saveFailed => _saveFailed;
  bool get isStreaming => _streamingSessionId != null;
  bool get isActiveSessionStreaming =>
      _streamingSessionId != null &&
      _activeSession != null &&
      _streamingSessionId == _activeSession!.id;
  bool get isHistoryOpBusy => _isHistoryOpBusy;
  List<ReplySource>? get searchPanelSources => _searchPanelSources;

  String get _currentDraftKey => _activeSession?.id ?? '';

  List<DraftAttachment> get currentDraftAttachments =>
      _drafts[_currentDraftKey] ?? const [];

  String get currentDraftText => _draftTexts[_currentDraftKey] ?? '';

  bool get hasUploadingDrafts => currentDraftAttachments
      .any((a) => a.status == DraftUploadStatus.uploading);

  bool get hasFailedDrafts =>
      currentDraftAttachments.any((a) => a.status == DraftUploadStatus.error);

  List<ChatMessage> get visibleMessages =>
      _activeSession == null ? const [] : getVisibleMessages(_activeSession!);

  Map<String, MessageVersionInfo> get messageVersions =>
      _activeSession == null ? const {} : buildMessageVersions(_activeSession!);

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    try {
      _summaries = await _db.listSummaries();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setDraftText(String text) {
    _draftTexts[_currentDraftKey] = text;
  }

  void openSearchPanel(List<ReplySource> sources) {
    _searchPanelSources = sources;
    notifyListeners();
  }

  void closeSearchPanel() {
    if (_searchPanelSources != null) {
      _searchPanelSources = null;
      notifyListeners();
    }
  }

  Future<void> newChat() async {
    _activeSession = null;
    _searchPanelSources = null;
    notifyListeners();
  }

  Future<void> openSession(String sessionId) async {
    if (_activeSession?.id == sessionId) return;
    _searchPanelSources = null;
    final loaded = await _db.loadSession(sessionId);
    if (loaded != null) {
      normalizeSession(loaded);
      _activeSession = loaded;
      notifyListeners();
    }
  }

  Future<void> renameSession(String sessionId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    _titleRequests.remove(sessionId);

    ChatSession? target =
        _activeSession?.id == sessionId ? _activeSession : await _db.loadSession(sessionId);
    if (target == null) return;
    target.title = trimmed;
    await _persistSession(target);
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    if (_streamingSessionId == sessionId) {
      stopStreaming();
    }
    _drafts.remove(sessionId);
    _draftTexts.remove(sessionId);
    _titleRequests.remove(sessionId);

    await _db.deleteSession(sessionId);
    _summaries.removeWhere((s) => s.id == sessionId);
    if (_activeSession?.id == sessionId) {
      _activeSession = null;
      _searchPanelSources = null;
    }
    notifyListeners();
  }

  Future<void> deleteAllSessions() async {
    stopStreaming();
    _drafts.clear();
    _draftTexts.clear();
    _titleRequests.clear();
    await _db.deleteAllSessions();
    _summaries = [];
    _activeSession = null;
    _searchPanelSources = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Attachments & Concurrent Upload Queue (max 3)
  // -------------------------------------------------------------------------

  Future<String?> addDraftFiles(List<({String name, Uint8List bytes, String? mimeType})> picked) async {
    final s = settingsProvider.strings;
    final key = _currentDraftKey;
    final list = _drafts.putIfAbsent(key, () => []);

    // All-or-nothing batch validation matching chat-demo attachments.ts
    if (list.length + picked.length > kMaxAttachmentCount) {
      return s.tooManyFiles;
    }
    for (final item in picked) {
      final ext = getFileExt(item.name);
      if (ext.isEmpty || !kAcceptFileExts.contains(ext)) {
        return s.unsupportedFileType;
      }
      final mime = resolveMimeType(item.name, item.mimeType);
      final isImg = isImageMime(mime);
      final maxMb = getMaxSizeMb(item.name, isImg);
      if (item.bytes.length > maxMb * 1024 * 1024) {
        return s.fileTooLarge(maxMb);
      }
    }

    for (final item in picked) {
      final fid = _uuid.v4();
      final mime = resolveMimeType(item.name, item.mimeType);
      final isImg = isImageMime(mime);
      final localPath = await _db.saveLocalFile(fid, item.bytes);
      final attachment = FileAttachment(
        id: fid,
        serverId: null,
        imageSizeChecked: false,
        name: item.name,
        size: item.bytes.length,
        isImage: isImg,
        mimeType: mime,
        localPath: localPath,
      );
      final draft = DraftAttachment(
        file: attachment,
        status: DraftUploadStatus.uploading,
      );
      list.add(draft);
      notifyListeners();
      _enqueueDraftUpload(draft);
    }
    return null;
  }

  void removeDraftAttachment(String fileId) {
    final list = _drafts[_currentDraftKey];
    if (list == null) return;
    list.removeWhere((a) => a.file.id == fileId);
    notifyListeners();
  }

  void retryDraftAttachment(String fileId) {
    final list = _drafts[_currentDraftKey];
    if (list == null) return;
    for (final d in list) {
      if (d.file.id == fileId) {
        d.status = DraftUploadStatus.uploading;
        d.errorMessage = null;
        d.retryable = true;
        notifyListeners();
        _enqueueDraftUpload(d);
        break;
      }
    }
  }

  void _enqueueDraftUpload(DraftAttachment draft) {
    _uploadQueue.add(() => _performDraftUpload(draft));
    _pumpUploadQueue();
  }

  void _pumpUploadQueue() {
    while (_activeUploads < kMaxConcurrentUploads && _uploadQueue.isNotEmpty) {
      final task = _uploadQueue.removeAt(0);
      _activeUploads++;
      task().whenComplete(() {
        _activeUploads--;
        _pumpUploadQueue();
      });
    }
  }

  Future<void> _performDraftUpload(DraftAttachment draft) async {
    try {
      await _uploadSingleAttachment(draft.file);
      draft.status = DraftUploadStatus.done;
      draft.errorMessage = null;
    } catch (e) {
      draft.status = DraftUploadStatus.error;
      draft.errorMessage = describeUploadError(e, settingsProvider.strings);
      draft.retryable = isRetryableApiError(e);
    }
    notifyListeners();
  }

  Future<void> _uploadSingleAttachment(FileAttachment attachment) async {
    final rawBytes = await _db.readLocalFile(attachment.id, attachment.localPath);
    if (rawBytes == null) {
      throw const ApiError(ApiErrorKind.protocol, 'Local file missing');
    }

    var uploadBytes = rawBytes;
    var uploadName = attachment.name;
    var uploadMime = attachment.mimeType;

    if (attachment.isImage) {
      final prepared = await prepareImageForUpload(
        bytes: rawBytes,
        filename: attachment.name,
        mimeType: attachment.mimeType,
      );
      uploadBytes = prepared.bytes;
      uploadName = prepared.filename;
      uploadMime = prepared.mimeType;
    }

    final purpose = getUploadPurpose(uploadName, attachment.isImage);
    final uploaded = await settingsProvider.createClient().uploadFile(
          bytes: uploadBytes,
          filename: uploadName,
          mimeType: uploadMime,
          purpose: purpose,
        );
    attachment.serverId = uploaded.id;
    if (attachment.isImage) {
      attachment.imageSizeChecked = true;
    }
  }

  // -------------------------------------------------------------------------
  // Send / Edit / Regenerate / Continue / Stop / Branch Switch
  // -------------------------------------------------------------------------

  Future<void> sendMessage(String rawText) async {
    final text = rawText.trim();
    final draftKey = _currentDraftKey;
    final drafts = List<DraftAttachment>.from(_drafts[draftKey] ?? const []);
    if (text.isEmpty && drafts.isEmpty) return;
    if (drafts.any((d) => d.status != DraftUploadStatus.done)) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final files = drafts.map((d) => d.file.clone()).toList();
    _drafts.remove(draftKey);
    _draftTexts.remove(draftKey);

    ChatSession session;
    if (_activeSession == null) {
      session = ChatSession(
        id: _uuid.v4(),
        title: '',
        createdAt: now,
        updatedAt: now,
      );
      _activeSession = session;
    } else {
      session = _activeSession!;
    }

    final visible = getVisibleMessages(session);
    final parentId = visible.isEmpty ? null : visible.last.id;

    final question = UserMessage(
      id: _uuid.v4(),
      createdAt: now,
      content: text,
      files: files,
    );

    final settings = settingsProvider.settings;
    final reminder = buildLatestReminder(
      now: DateTime.fromMillisecondsSinceEpoch(now),
      locale: settings.locale,
      location: settings.location,
    );

    final reply = AssistantMessage(
      id: _uuid.v4(),
      createdAt: now,
      model: settings.model,
      thinking: settings.thinking,
      search: settings.search,
      latestReminder: reminder,
      prefix: true,
      status: ReplyStatus.pending,
    );

    appendBranch(session, parentId, [question, reply]);
    session.updatedAt = now;
    await _persistSession(session);
    notifyListeners();

    await _streamReply(
      session: session,
      history: visible,
      question: question,
      reply: reply,
      continuationPrefix: null,
    );
  }

  Future<void> editUserMessage(String userMessageId, String newContent) async {
    final session = _activeSession;
    if (session == null || isStreaming) return;
    final trimmed = newContent.trim();

    final visible = getVisibleMessages(session);
    final idx = visible.indexWhere((m) => m.id == userMessageId);
    if (idx < 0 || visible[idx] is! UserMessage) return;

    final previous = visible[idx] as UserMessage;
    if (trimmed.isEmpty && previous.files.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final history = visible.sublist(0, idx);
    final parentId = idx == 0 ? null : visible[idx - 1].id;

    final newQuestion = UserMessage(
      id: _uuid.v4(),
      createdAt: now,
      content: trimmed,
      files: previous.files.map((f) => f.clone()).toList(),
    );

    final settings = settingsProvider.settings;
    final reminder = buildLatestReminder(
      now: DateTime.fromMillisecondsSinceEpoch(now),
      locale: settings.locale,
      location: settings.location,
    );

    final reply = AssistantMessage(
      id: _uuid.v4(),
      createdAt: now,
      model: settings.model,
      thinking: settings.thinking,
      search: settings.search,
      latestReminder: reminder,
      prefix: true,
      status: ReplyStatus.pending,
    );

    appendBranch(session, parentId, [newQuestion, reply]);
    session.updatedAt = now;
    await _persistSession(session);
    notifyListeners();

    await _streamReply(
      session: session,
      history: history,
      question: newQuestion,
      reply: reply,
      continuationPrefix: null,
    );
  }

  Future<void> regenerateReply(String assistantMessageId) async {
    final session = _activeSession;
    if (session == null || isStreaming) return;

    final visible = getVisibleMessages(session);
    final idx = visible.indexWhere((m) => m.id == assistantMessageId);
    if (idx < 1 || visible[idx - 1] is! UserMessage) return;

    final question = visible[idx - 1] as UserMessage;
    final history = visible.sublist(0, idx - 1);
    final now = DateTime.now().millisecondsSinceEpoch;
    final settings = settingsProvider.settings;
    final reminder = buildLatestReminder(
      now: DateTime.fromMillisecondsSinceEpoch(now),
      locale: settings.locale,
      location: settings.location,
    );

    final reply = AssistantMessage(
      id: _uuid.v4(),
      createdAt: now,
      model: settings.model,
      thinking: settings.thinking,
      search: settings.search,
      latestReminder: reminder,
      prefix: true,
      status: ReplyStatus.pending,
    );

    appendBranch(session, question.id, [reply]);
    session.updatedAt = now;
    await _persistSession(session);
    notifyListeners();

    await _streamReply(
      session: session,
      history: history,
      question: question,
      reply: reply,
      continuationPrefix: null,
    );
  }

  Future<void> continueReply(String assistantMessageId) async {
    final session = _activeSession;
    if (session == null || isStreaming) return;

    final visible = getVisibleMessages(session);
    if (visible.length < 2) return;
    if (visible.last.id != assistantMessageId) return;
    if (visible.last is! AssistantMessage ||
        visible[visible.length - 2] is! UserMessage) {
      return;
    }

    final reply = visible.last as AssistantMessage;
    if (!canContinueReply(reply)) return;

    final question = visible[visible.length - 2] as UserMessage;
    final history = visible.sublist(0, visible.length - 2);

    reply.status = ReplyStatus.streaming;
    reply.error = null;
    reply.stopReason = null;
    reply.stopDetails = null;
    reply.model ??= settingsProvider.settings.model;
    notifyListeners();

    await _streamReply(
      session: session,
      history: history,
      question: question,
      reply: reply,
      continuationPrefix: reply,
    );
  }

  Future<void> selectMessageVersion(String messageId) async {
    final session = _activeSession;
    if (session == null || isStreaming) return;
    if (selectVersion(session, messageId)) {
      await _persistSession(session);
      notifyListeners();
    }
  }

  void stopStreaming() {
    if (_streamingSessionId == null) return;
    _userStopped = true;
    _streamClient?.close();
    _streamClient = null;
  }

  Future<void> retrySave() async {
    if (_activeSession == null) return;
    await _persistSession(_activeSession!);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Streaming Pipeline + File Backfill + File-ID Auto-Healing
  // -------------------------------------------------------------------------

  Future<void> _prepareFilesForTurn(
    List<ChatMessage> history,
    UserMessage question,
  ) async {
    // 1. Verify legacy unchecked images
    final allAttachments = <FileAttachment>[
      ...question.files,
      for (final m in history)
        if (m is UserMessage) ...m.files,
    ];
    for (final f in allAttachments) {
      if (f.isImage && f.serverId != null && !f.imageSizeChecked) {
        final raw = await _db.readLocalFile(f.id, f.localPath);
        if (raw != null && await isImageOversized(raw)) {
          f.serverId = null;
        } else {
          f.imageSizeChecked = true;
        }
      }
    }

    // 2. Current question files without serverId -> parallel upload (must succeed)
    final missingCurrent = question.files
        .where((f) => f.serverId == null || f.serverId!.isEmpty)
        .toList();
    if (missingCurrent.isNotEmpty) {
      await Future.wait(missingCurrent.map(_uploadSingleAttachment));
    }

    // 3. History files without serverId (e.g. imported images) -> sequential newest-to-oldest, skip failures
    for (var i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (m is UserMessage) {
        for (final f in m.files) {
          if (f.serverId == null || f.serverId!.isEmpty) {
            final localBytes = await _db.readLocalFile(f.id, f.localPath);
            if (localBytes != null) {
              try {
                await _uploadSingleAttachment(f);
              } catch (_) {}
            }
          }
        }
      }
    }
  }

  Future<void> _streamReply({
    required ChatSession session,
    required List<ChatMessage> history,
    required UserMessage question,
    required AssistantMessage reply,
    required AssistantMessage? continuationPrefix,
  }) async {
    _streamingSessionId = session.id;
    _userStopped = false;
    final wantTitle = session.title.isEmpty;
    if (wantTitle) {
      _titleRequests.add(session.id);
    }

    var attempt = 0;

    try {
      while (true) {
        // Prepare files (upload missing/backfill)
        try {
          await _prepareFilesForTurn(history, question);
        } catch (e) {
          settleReply(
            reply,
            ReplyStatus.error,
            DateTime.now().millisecondsSinceEpoch,
            error: ReplyError(
              kind: 'upload',
              message: describeUploadError(e, settingsProvider.strings),
              retryable: isRetryableApiError(e),
            ),
          );
          break;
        }

        final requestMessages = toRequestMessages(
          history: history,
          question: question,
          continuationPrefix: continuationPrefix,
          thinkingEnabled: reply.thinking,
          currentLatestReminder: reply.latestReminder,
        );

        final client = http.Client();
        _streamClient = client;
        final blockIndexes = <int, int>{};
        var receivedContent = false;

        try {
          reply.status = ReplyStatus.streaming;
          notifyListeners();

          final stream = settingsProvider.createClient().streamMessage(
                model: reply.model ?? settingsProvider.settings.model,
                messages: requestMessages,
                thinking: reply.thinking,
                search: reply.search,
                requestTitle: wantTitle && _titleRequests.contains(session.id),
                client: client,
              );

          await for (final event in stream) {
            if (_userStopped) break;
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            if (event is ContentBlockStartEvent) {
              receivedContent = true;
            }
            applyEvent(reply, event, nowMs, blockIndexes);

            if (event is MessageDeltaEvent &&
                event.title != null &&
                event.title!.trim().isNotEmpty &&
                (event.stopReason == 'end_turn' ||
                    event.stopReason == 'max_tokens') &&
                _titleRequests.contains(session.id) &&
                session.title.isEmpty &&
                !_isHistoryOpBusy) {
              session.title = event.title!.trim();
              _titleRequests.remove(session.id);
            }
            notifyListeners();
          }

          final endMs = DateTime.now().millisecondsSinceEpoch;
          if (_userStopped) {
            settleReply(reply, ReplyStatus.stopped, endMs);
          } else {
            settleReply(reply, ReplyStatus.done, endMs);
          }
          break;
        } catch (e) {
          final endMs = DateTime.now().millisecondsSinceEpoch;
          if (_userStopped) {
            settleReply(reply, ReplyStatus.stopped, endMs);
            break;
          }

          if (e is ApiError &&
              e.kind == ApiErrorKind.interrupted &&
              reply.stopReason != null) {
            settleReply(reply, ReplyStatus.done, endMs);
            break;
          }

          // Expired/Invalid file_id auto-heal retry
          if (attempt < _kFileRetryLimit &&
              !receivedContent &&
              getFileErrorCode(e) != null) {
            final badIds = e is ApiError ? extractFileIds(e.message) : <String>[];
            final allFiles = <FileAttachment>[
              ...question.files,
              for (final m in history)
                if (m is UserMessage) ...m.files,
            ];
            for (final f in allFiles) {
              if (badIds.isEmpty ||
                  (f.serverId != null && badIds.contains(f.serverId))) {
                f.serverId = null;
              }
            }
            await _persistSession(session);
            final delayMs = _kFileRetryBaseDelayMs * (1 << attempt);
            attempt++;
            await Future<void>.delayed(Duration(milliseconds: delayMs));
          } else {
            final err = e is ApiError
                ? ReplyError(
                    kind: e.kind.name,
                    message: e.message,
                    status: e.status,
                    retryable: isRetryableApiError(e),
                  )
                : ReplyError(
                    kind: 'network',
                    message: e.toString(),
                    retryable: true,
                  );
            settleReply(reply, ReplyStatus.error, endMs, error: err);
            break;
          }
        } finally {
          if (_streamClient == client) {
            _streamClient = null;
          }
          client.close();
        }
      }
    } finally {
      _streamingSessionId = null;
      _titleRequests.remove(session.id);
      session.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _persistSession(session);
      notifyListeners();
    }
  }

  Future<void> _persistSession(ChatSession session) async {
    try {
      await _db.saveSession(session);
      _saveFailed = false;
      final summary = session.toSummary();
      _summaries.removeWhere((s) => s.id == session.id);
      _summaries.insert(0, summary);
      _summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      _saveFailed = true;
    }
  }

  // -------------------------------------------------------------------------
  // ZIP History Import & Export
  // -------------------------------------------------------------------------

  Future<int> importHistoryZip(
    Uint8List zipBytes, {
    void Function(int processed, int total)? onProgress,
  }) async {
    stopStreaming();
    _isHistoryOpBusy = true;
    notifyListeners();
    try {
      final result = await HistoryBackupService.parseImportArchive(
        zipBytes,
        onProgress: onProgress,
      );
      await _db.replaceAllSessions(result.sessions, result.blobs);
      _drafts.clear();
      _draftTexts.clear();
      _activeSession = null;
      _searchPanelSources = null;
      _summaries = await _db.listSummaries();
      return result.sessions.length;
    } finally {
      _isHistoryOpBusy = false;
      notifyListeners();
    }
  }

  Future<File> exportHistoryZip({
    required Directory outputDir,
    void Function(int processed, int total)? onProgress,
  }) async {
    _isHistoryOpBusy = true;
    notifyListeners();
    try {
      final allSessions = await _db.loadAllSessions();
      final bytes = await HistoryBackupService.exportArchive(
        sessions: allSessions,
        strings: settingsProvider.strings,
        onProgress: onProgress,
      );
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final file = File('${outputDir.path}/deepseek_data-$y-$m-$d.zip');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } finally {
      _isHistoryOpBusy = false;
      notifyListeners();
    }
  }
}
