import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../models/api_types.dart';
import 'api_errors.dart';
import 'parse_event.dart';
import 'sse_decoder.dart';

/// DeepSeek Full-Suite App API client ported 1:1 from `api/client.ts` & `api/speech.ts`.
class DeepSeekClient {
  static const String filesBetaHeader = 'files-api-2025-04-14';
  static const String systemPrompt = '该助手为DeepSeek，由深度求索公司创造。';

  final String apiOrigin;
  final String apiKey;

  DeepSeekClient({
    required this.apiKey,
    String apiOrigin = 'https://api.deepseek.com',
  }) : apiOrigin = apiOrigin.replaceAll(RegExp(r'/+$'), '');

  String get anthropicBaseUrl => '$apiOrigin/anthropic/v1';
  String get toolsBaseUrl => '$apiOrigin/v1/tools';

  /// Verifies API key against `GET ${apiOrigin}/models` (no billing).
  Future<void> verifyApiKey() async {
    final uri = Uri.parse('$apiOrigin/models');
    http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ApiError(ApiErrorKind.network, e.toString());
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        ApiErrorKind.http,
        readErrorResponseText(response.body, response.reasonPhrase ?? ''),
        status: response.statusCode,
      );
    }
  }

  /// Uploads a file via Anthropic Files API (`POST /anthropic/v1/files`).
  /// IMPORTANT: `purpose` MUST precede `file` in multipart form order.
  /// For images, `purpose` is omitted completely (`purpose == null`).
  Future<FileObject> uploadFile({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String? purpose,
    http.Client? client,
  }) async {
    final uri = Uri.parse('$anthropicBaseUrl/files');
    final request = http.MultipartRequest('POST', uri);
    request.headers['x-api-key'] = apiKey;
    request.headers['anthropic-beta'] = filesBetaHeader;

    // Order matters: purpose BEFORE file
    if (purpose != null) {
      request.fields['purpose'] = purpose;
    }

    MediaType? contentType;
    if (mimeType.isNotEmpty) {
      try {
        contentType = MediaType.parse(mimeType);
      } catch (_) {}
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    );

    final httpClient = client ?? http.Client();
    try {
      final streamed = await httpClient.send(request);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw ApiError(
          ApiErrorKind.http,
          readErrorResponseText(body, streamed.reasonPhrase ?? ''),
          status: streamed.statusCode,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['id'] is! String) {
        throw ApiError(ApiErrorKind.protocol, body, status: streamed.statusCode);
      }
      return FileObject.fromJson(decoded);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError(ApiErrorKind.network, e.toString());
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Deletes a file via `DELETE /anthropic/v1/files/{fileId}`.
  Future<void> deleteFile(String fileId) async {
    final uri =
        Uri.parse('$anthropicBaseUrl/files/${Uri.encodeComponent(fileId)}');
    try {
      final res = await http.delete(
        uri,
        headers: {
          'x-api-key': apiKey,
          'anthropic-beta': filesBetaHeader,
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiError(
          ApiErrorKind.http,
          readErrorResponseText(res.body, res.reasonPhrase ?? ''),
          status: res.statusCode,
        );
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError(ApiErrorKind.network, e.toString());
    }
  }

  /// Streams chat reply via `POST /anthropic/v1/messages`.
  /// Pass a caller-owned [client] and close it to abort the stream immediately.
  Stream<MessageEvent> streamMessage({
    required String model,
    required List<Map<String, dynamic>> messages,
    required bool thinking,
    required bool search,
    required bool requestTitle,
    required http.Client client,
  }) async* {
    final hasFiles = _messagesContainFile(messages);
    final tools = <Map<String, dynamic>>[
      {'type': 'deepseek_read_url', 'name': 'deepseek_read_url'},
      if (search)
        {'type': 'deepseek_web_search', 'name': 'deepseek_web_search'},
    ];

    final payload = <String, dynamic>{
      'model': model,
      'system': systemPrompt,
      'messages': messages,
      'thinking': {'type': thinking ? 'enabled' : 'disabled'},
      'tools': tools,
      'safety_check': {'level': 'high'},
      if (requestTitle) 'title': {'enabled': true},
      'stream': true,
    };

    final uri = Uri.parse('$anthropicBaseUrl/messages');
    final request = http.Request('POST', uri);
    request.headers['x-api-key'] = apiKey;
    if (hasFiles) {
      request.headers['anthropic-beta'] = filesBetaHeader;
    }
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode(payload);

    http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (e) {
      throw ApiError(ApiErrorKind.network, e.toString());
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw ApiError(
        ApiErrorKind.http,
        readErrorResponseText(body, response.reasonPhrase ?? ''),
        status: response.statusCode,
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final body = await response.stream.bytesToString();
      throw ApiError(ApiErrorKind.protocol, body, status: response.statusCode);
    }

    var receivedStop = false;
    try {
      await for (final frame in decodeSseStream(response.stream)) {
        dynamic parsedJson;
        try {
          parsedJson = jsonDecode(frame.data);
        } catch (_) {
          if (frame.event == 'error') {
            throw ApiError(ApiErrorKind.stream, frame.data);
          }
          continue;
        }

        final errorMsg = extractErrorBodyMessage(parsedJson);
        if (errorMsg != null) {
          throw ApiError(ApiErrorKind.stream, errorMsg);
        }
        if (frame.event == 'error') {
          throw ApiError(ApiErrorKind.stream, frame.data);
        }

        final event = parseMessageEvent(parsedJson);
        if (event == null) continue;
        yield event;

        if (event is MessageStopEvent) {
          receivedStop = true;
          return;
        }
      }
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError(ApiErrorKind.network, e.toString());
    }

    if (!receivedStop) {
      throw const ApiError(ApiErrorKind.interrupted, '');
    }
  }

  /// Transcribes 16kHz mono 16-bit PCM WAV via `POST /v1/tools/asr` (Bearer auth).
  Future<String> transcribeAudio({
    required Uint8List wavBytes,
    http.Client? client,
  }) async {
    final uri = Uri.parse('$toolsBaseUrl/asr');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        wavBytes,
        filename: 'recording.wav',
        contentType: MediaType('audio', 'wav'),
      ),
    );

    final httpClient = client ?? http.Client();
    try {
      final streamed = await httpClient.send(request);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw ApiError(
          ApiErrorKind.http,
          readErrorResponseText(body, streamed.reasonPhrase ?? ''),
          status: streamed.statusCode,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['text'] is String) {
        return decoded['text'] as String;
      }
      throw ApiError(ApiErrorKind.protocol, body, status: streamed.statusCode);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError(ApiErrorKind.network, e.toString());
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Streams raw 24kHz mono 16-bit signed LE PCM via `POST /v1/tools/tts` (Bearer auth).
  Future<http.StreamedResponse> streamTts({
    required String text,
    required String voiceId, // 'stella' | 'tide'
    required http.Client client,
  }) async {
    final uri = Uri.parse('$toolsBaseUrl/tts');
    final request = http.Request('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'text': text,
      'voice_id': voiceId,
      'format': 'pcm',
      'filter_markdown': true,
    });

    http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (e) {
      throw ApiError(ApiErrorKind.network, e.toString());
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw ApiError(
        ApiErrorKind.http,
        readErrorResponseText(body, response.reasonPhrase ?? ''),
        status: response.statusCode,
      );
    }

    return response;
  }

  bool _messagesContainFile(List<Map<String, dynamic>> messages) {
    for (final m in messages) {
      final content = m['content'];
      if (content is List) {
        for (final block in content) {
          if (block is Map &&
              (block['type'] == 'image' || block['type'] == 'document')) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
