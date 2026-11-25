import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepseek_chat/l10n/app_strings.dart';
import 'package:deepseek_chat/models/api_types.dart';
import 'package:deepseek_chat/models/chat_models.dart';
import 'package:deepseek_chat/models/settings_models.dart';
import 'package:deepseek_chat/services/api/parse_event.dart';
import 'package:deepseek_chat/services/api/sse_decoder.dart';
import 'package:deepseek_chat/services/chat/branches.dart';
import 'package:deepseek_chat/services/chat/latest_reminder.dart';
import 'package:deepseek_chat/services/chat/reply_logic.dart';
import 'package:deepseek_chat/services/chat/reply_view.dart';
import 'package:deepseek_chat/services/storage/history_backup.dart';

void main() {
  group('SSE Decoder', () {
    test('handles split chunks, BOM, CRLF, comments, and multi-line data', () async {
      final raw = '\uFEFF: keep-alive\r\nevent: message_start\r\ndata: {"type":"message_start"}\r\n\r\ndata: line1\ndata: line2\n\n';
      final bytes = utf8.encode(raw);
      // Feed 5 bytes at a time to verify chunk boundary handling
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 5) {
        chunks.add(bytes.sublist(i, i + 5 > bytes.length ? bytes.length : i + 5));
      }
      final frames = await decodeSseStream(Stream.fromIterable(chunks)).toList();
      expect(frames.length, 2);
      expect(frames[0].event, 'message_start');
      expect(frames[0].data, '{"type":"message_start"}');
      expect(frames[1].event, 'message');
      expect(frames[1].data, 'line1\nline2');
    });
  });

  group('Event Parsing & Reply Merging', () {
    test('parses thinking, search, citations, and message_delta title', () {
      final reply = AssistantMessage(
        id: 'a1',
        createdAt: 1000,
        model: 'deepseek-flash',
        thinking: true,
        search: true,
      );
      final map = <int, int>{};

      final events = [
        parseMessageEvent({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'thinking', 'thinking': ''},
        })!,
        parseMessageEvent({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': 'Let me check...'},
        })!,
        parseMessageEvent({'type': 'content_block_stop', 'index': 0})!,
        parseMessageEvent({
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'server_tool_use',
            'id': 'srvtoolu_s_1',
            'name': 'deepseek_web_search',
            'kind': 'search',
            'input': {'action': 'search', 'queries': ['DeepSeek V4']},
          },
        })!,
        parseMessageEvent({
          'type': 'content_block_start',
          'index': 2,
          'content_block': {
            'type': 'web_search_tool_result',
            'tool_use_id': 'srvtoolu_s_1',
            'kind': 'search',
            'content': [
              {
                'type': 'web_search_result',
                'title': 'DeepSeek Docs',
                'url': 'https://api-docs.deepseek.com/',
                'snippet': 'Official docs',
                'site_name': 'DeepSeek',
                'site_icon': null,
                'encrypted_content': '',
                'page_age': '2026-11-13',
              }
            ],
          },
        })!,
        parseMessageEvent({
          'type': 'content_block_start',
          'index': 3,
          'content_block': {'type': 'text', 'text': 'Hello world.  '},
        })!,
        parseMessageEvent({
          'type': 'content_block_delta',
          'index': 3,
          'delta': {
            'type': 'citations_delta',
            'citation': {
              'type': 'web_search_result_location',
              'url': 'https://api-docs.deepseek.com/',
              'title': 'DeepSeek Docs',
              'cited_text': 'Official docs',
              'encrypted_index': '',
            },
          },
        })!,
        parseMessageEvent({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn', 'title': 'DeepSeek Overview'},
        })!,
      ];

      for (final ev in events) {
        applyEvent(reply, ev, 3500, map);
      }
      settleReply(reply, ReplyStatus.done, 3500);

      final view = buildReplyView(reply);
      expect(view.steps.length, 2); // ThinkingStep + SearchStep
      expect(view.searchResults.length, 1);
      // Citation marker inserted BEFORE trailing spaces
      expect(view.answer, 'Hello world.[citation:1]  ');
      expect(view.sourcesByIndex[1]?.title, 'DeepSeek Docs');
    });
  });

  group('Branching & Context Assembly', () {
    test('supports editing and switching sibling branches', () {
      final session = ChatSession(id: 's1', createdAt: 1, updatedAt: 1);
      final u1 = UserMessage(id: 'u1', createdAt: 1, content: 'Hi');
      final a1 = AssistantMessage(
        id: 'a1',
        createdAt: 2,
        status: ReplyStatus.done,
        blocks: [TextPart(text: 'Hello 1')],
      );
      appendBranch(session, null, [u1, a1]);

      final a2 = AssistantMessage(
        id: 'a2',
        createdAt: 3,
        status: ReplyStatus.done,
        blocks: [TextPart(text: 'Hello 2')],
      );
      appendBranch(session, u1.id, [a2]);

      expect(getVisibleMessages(session).map((m) => m.id), ['u1', 'a2']);
      final versions = buildMessageVersions(session);
      expect(versions['a2']?.index, 1);
      expect(versions['a2']?.total, 2);

      expect(selectVersion(session, 'a1'), isTrue);
      expect(getVisibleMessages(session).map((m) => m.id), ['u1', 'a1']);
    });

    test('builds exact 5-tuple latest_reminder and deduplicates in request', () {
      final reminder = buildLatestReminder(
        now: DateTime(2026, 11, 25),
        locale: 'zh-CN',
        location: const UserLocation(region: 'CN', province: '110000', city: '110100'),
      );
      expect(reminder, '2026-11-25,星期三,北京市,Web,中文');

      final u1 = UserMessage(id: 'u1', createdAt: 1, content: 'Q1');
      final a1 = AssistantMessage(
        id: 'a1',
        createdAt: 2,
        status: ReplyStatus.done,
        latestReminder: reminder,
        blocks: [TextPart(text: 'A1')],
      );
      final u2 = UserMessage(id: 'u2', createdAt: 3, content: 'Q2');

      final req = toRequestMessages(
        history: [u1, a1],
        question: u2,
        thinkingEnabled: false,
        currentLatestReminder: reminder, // duplicate -> should NOT emit twice
      );
      final reminderCount = req.where((m) => m['role'] == 'latest_reminder').length;
      expect(reminderCount, 1);
      expect(req.length, 4); // latest_reminder, u1, a1, u2
    });
  });

  group('ZIP v3 Backup Round-Trip', () {
    test('exports and re-imports session tree cleanly', () async {
      final session = ChatSession(
        id: 'session-test-1',
        title: 'Test Chat',
        createdAt: 1764000000000,
        updatedAt: 1764000010000,
      );
      final u1 = UserMessage(id: 'u1', createdAt: 1764000001000, content: 'Explain E=mc^2');
      final a1 = AssistantMessage(
        id: 'a1',
        createdAt: 1764000002000,
        thinking: true,
        status: ReplyStatus.done,
        blocks: [
          ThinkingPart(thinking: 'Relativity basics', startedAt: 1000, endedAt: 3000),
          TextPart(text: 'Energy equals mass times speed of light squared.'),
        ],
      );
      appendBranch(session, null, [u1, a1]);

      final zipBytes = await HistoryBackupService.exportArchive(
        sessions: [session],
        strings: const AppStrings(true),
      );
      expect(zipBytes.sublist(0, 4), Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]));

      final imported = await HistoryBackupService.parseImportArchive(zipBytes);
      expect(imported.sessions.length, 1);
      final s2 = imported.sessions.first;
      expect(s2.id, 'session-test-1');
      expect(s2.title, 'Test Chat');
      final vis = getVisibleMessages(s2);
      expect(vis.length, 2);
      expect((vis[0] as UserMessage).content, 'Explain E=mc^2');
      final impA = vis[1] as AssistantMessage;
      expect(impA.prefix, isFalse);
      expect(getReplyText(impA), 'Energy equals mass times speed of light squared.');
    });
  });
}
