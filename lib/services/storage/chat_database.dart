import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/chat_models.dart';
import '../chat/reply_logic.dart';

class ChatDatabase {
  static final ChatDatabase instance = ChatDatabase._();
  ChatDatabase._();

  Database? _db;
  Directory? _filesDir;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'deepseek_chat.db');
    _filesDir = Directory(p.join(dir.path, 'attachments'));
    if (!await _filesDir!.exists()) {
      await _filesDir!.create(recursive: true);
    }

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            payload TEXT NOT NULL,
            file_ids TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_sessions_updated ON sessions(updated_at DESC)',
        );
      },
    );
    return _db!;
  }

  Future<Directory> get attachmentsDir async {
    if (_filesDir == null) {
      await database;
    }
    if (!await _filesDir!.exists()) {
      await _filesDir!.create(recursive: true);
    }
    return _filesDir!;
  }

  Future<String> saveLocalFile(String fileId, Uint8List bytes) async {
    final dir = await attachmentsDir;
    final path = p.join(dir.path, fileId);
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<Uint8List?> readLocalFile(String fileId, [String? localPath]) async {
    if (localPath != null && localPath.isNotEmpty) {
      final f = File(localPath);
      if (await f.exists()) return f.readAsBytes();
    }
    final dir = await attachmentsDir;
    final f = File(p.join(dir.path, fileId));
    if (await f.exists()) return f.readAsBytes();
    return null;
  }

  Future<String?> resolveLocalPath(String fileId, [String? localPath]) async {
    if (localPath != null && await File(localPath).exists()) {
      return localPath;
    }
    final dir = await attachmentsDir;
    final path = p.join(dir.path, fileId);
    if (await File(path).exists()) return path;
    return null;
  }

  List<String> _extractSessionFileIds(ChatSession session) {
    final ids = <String>{};
    for (final m in session.messages) {
      if (m is UserMessage) {
        for (final f in m.files) {
          ids.add(f.id);
        }
      }
    }
    return ids.toList();
  }

  Future<List<SessionSummary>> listSummaries() async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      columns: ['id', 'title', 'created_at', 'updated_at'],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((r) => SessionSummary(
              id: r['id'] as String,
              title: r['title'] as String,
              createdAt: (r['created_at'] as num).toInt(),
              updatedAt: (r['updated_at'] as num).toInt(),
            ))
        .toList();
  }

  Future<List<ChatSession>> loadAllSessions() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'updated_at DESC');
    final list = <ChatSession>[];
    for (final r in rows) {
      try {
        final session = ChatSession.fromJson(
          jsonDecode(r['payload'] as String) as Map<String, dynamic>,
        );
        _settleInterrupted(session);
        list.add(session);
      } catch (_) {}
    }
    return list;
  }

  Future<ChatSession?> loadSession(String id) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final session = ChatSession.fromJson(
      jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
    );
    _settleInterrupted(session);
    return session;
  }

  void _settleInterrupted(ChatSession session) {
    for (final m in session.messages) {
      if (m is AssistantMessage && m.isStreaming) {
        settleReply(m, ReplyStatus.stopped, session.updatedAt);
      }
    }
  }

  Future<void> saveSession(ChatSession session) async {
    final db = await database;
    final fileIds = _extractSessionFileIds(session);
    await db.insert(
      'sessions',
      {
        'id': session.id,
        'title': session.title,
        'created_at': session.createdAt,
        'updated_at': session.updatedAt,
        'payload': jsonEncode(session.toJson()),
        'file_ids': jsonEncode(fileIds),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSession(String id) async {
    final db = await database;
    final targetRows = await db.query(
      'sessions',
      columns: ['file_ids'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final candidateFileIds = <String>{};
    if (targetRows.isNotEmpty) {
      final raw = jsonDecode(targetRows.first['file_ids'] as String);
      if (raw is List) {
        candidateFileIds.addAll(raw.whereType<String>());
      }
    }

    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);

    if (candidateFileIds.isNotEmpty) {
      final otherRows = await db.query('sessions', columns: ['file_ids']);
      final stillUsed = <String>{};
      for (final row in otherRows) {
        final raw = jsonDecode(row['file_ids'] as String);
        if (raw is List) stillUsed.addAll(raw.whereType<String>());
      }
      final dir = await attachmentsDir;
      for (final fid in candidateFileIds) {
        if (!stillUsed.contains(fid)) {
          final f = File(p.join(dir.path, fid));
          if (await f.exists()) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }
    }
  }

  Future<void> deleteAllSessions() async {
    final db = await database;
    await db.delete('sessions');
    final dir = await attachmentsDir;
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Atomically replaces all local sessions and local attachment blobs (used by ZIP import).
  Future<void> replaceAllSessions(
    List<ChatSession> sessions,
    Map<String, Uint8List> imageBlobs,
  ) async {
    final db = await database;
    final dir = await attachmentsDir;

    // Write imported blobs to disk first, keeping track of written files
    final newFilePaths = <String, String>{};
    for (final entry in imageBlobs.entries) {
      final path = p.join(dir.path, entry.key);
      await File(path).writeAsBytes(entry.value, flush: true);
      newFilePaths[entry.key] = path;
    }

    // Backfill localPath on attachments
    for (final s in sessions) {
      for (final m in s.messages) {
        if (m is UserMessage) {
          for (final f in m.files) {
            if (newFilePaths.containsKey(f.id)) {
              f.localPath = newFilePaths[f.id];
            }
          }
        }
      }
    }

    await db.transaction((txn) async {
      await txn.delete('sessions');
      for (final session in sessions) {
        final fileIds = _extractSessionFileIds(session);
        await txn.insert(
          'sessions',
          {
            'id': session.id,
            'title': session.title,
            'created_at': session.createdAt,
            'updated_at': session.updatedAt,
            'payload': jsonEncode(session.toJson()),
            'file_ids': jsonEncode(fileIds),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    // Clean up orphaned files not in newFilePaths
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        if (!newFilePaths.containsKey(name)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    }
  }
}
