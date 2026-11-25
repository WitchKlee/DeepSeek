import 'dart:async';
import 'dart:convert';

class SseFrame {
  final String event;
  final String data;
  final String lastEventId;

  const SseFrame({
    required this.event,
    required this.data,
    required this.lastEventId,
  });
}

/// Spec-compliant WHATWG EventSource byte-stream parser ported 1:1 from `api/sse.ts`.
Stream<SseFrame> decodeSseStream(Stream<List<int>> byteStream) async* {
  final decoder = const Utf8Decoder(allowMalformed: true);
  final stringStream = decoder.bind(byteStream);

  var isFirstChunk = true;
  var pendingLine = StringBuffer();
  var pendingCr = false;

  var eventType = '';
  final dataBuffer = StringBuffer();
  var hasData = false;
  var lastEventId = '';

  SseFrame? processLine(String line) {
    if (line.isEmpty) {
      if (!hasData) {
        eventType = '';
        return null;
      }
      final frame = SseFrame(
        event: eventType.isEmpty ? 'message' : eventType,
        data: dataBuffer.toString(),
        lastEventId: lastEventId,
      );
      eventType = '';
      dataBuffer.clear();
      hasData = false;
      return frame;
    }

    if (line.startsWith(':')) {
      return null;
    }

    final colonIndex = line.indexOf(':');
    String field;
    String value;
    if (colonIndex == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colonIndex);
      value = line.substring(colonIndex + 1);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
    }

    switch (field) {
      case 'data':
        if (hasData) dataBuffer.write('\n');
        dataBuffer.write(value);
        hasData = true;
        break;
      case 'event':
        eventType = value;
        break;
      case 'id':
        if (!value.contains('\u0000')) {
          lastEventId = value;
        }
        break;
      default:
        break;
    }
    return null;
  }

  await for (var chunk in stringStream) {
    if (isFirstChunk) {
      isFirstChunk = false;
      if (chunk.startsWith('\uFEFF')) {
        chunk = chunk.substring(1);
      }
    }

    var start = 0;
    if (pendingCr) {
      pendingCr = false;
      if (chunk.isNotEmpty && chunk.codeUnitAt(0) == 0x0A) {
        start = 1;
      }
      final frame = processLine(pendingLine.toString());
      pendingLine = StringBuffer();
      if (frame != null) yield frame;
    }

    for (var i = start; i < chunk.length; i++) {
      final code = chunk.codeUnitAt(i);
      if (code == 0x0D || code == 0x0A) {
        pendingLine.write(chunk.substring(start, i));
        if (code == 0x0D) {
          if (i + 1 < chunk.length) {
            if (chunk.codeUnitAt(i + 1) == 0x0A) {
              i++;
            }
            final frame = processLine(pendingLine.toString());
            pendingLine = StringBuffer();
            if (frame != null) yield frame;
          } else {
            pendingCr = true;
          }
        } else {
          final frame = processLine(pendingLine.toString());
          pendingLine = StringBuffer();
          if (frame != null) yield frame;
        }
        start = i + 1;
      }
    }

    if (start < chunk.length) {
      pendingLine.write(chunk.substring(start));
    }
  }

  if (pendingCr) {
    final frame = processLine(pendingLine.toString());
    if (frame != null) yield frame;
  }
}
