import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const int kMaxImageEdge = 4096;

class PreparedUploadImage {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final bool wasResized;

  const PreparedUploadImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    required this.wasResized,
  });
}

class _ResizeArgs {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  const _ResizeArgs(this.bytes, this.filename, this.mimeType);
}

/// Checks and resizes an image off the UI isolate if its longest edge > 4096px,
/// matching `src/utils/resizeUploadImage.ts`.
Future<PreparedUploadImage> prepareImageForUpload({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  return compute(_resizeInIsolate, _ResizeArgs(bytes, filename, mimeType));
}

PreparedUploadImage _resizeInIsolate(_ResizeArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) {
    return PreparedUploadImage(
      bytes: args.bytes,
      filename: args.filename,
      mimeType: args.mimeType,
      wasResized: false,
    );
  }

  final longest = max(decoded.width, decoded.height);
  if (longest <= kMaxImageEdge) {
    return PreparedUploadImage(
      bytes: args.bytes,
      filename: args.filename,
      mimeType: args.mimeType,
      wasResized: false,
    );
  }

  final scale = kMaxImageEdge / longest;
  final targetW = max(1, (decoded.width * scale).round());
  final targetH = max(1, (decoded.height * scale).round());
  final resized = img.copyResize(
    decoded,
    width: targetW,
    height: targetH,
    interpolation: img.Interpolation.linear,
  );

  final isJpeg = args.mimeType == 'image/jpeg';
  final Uint8List encoded;
  final String outMime;
  final String outExt;

  if (isJpeg) {
    encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 100));
    outMime = 'image/jpeg';
    outExt = 'jpg';
  } else {
    encoded = Uint8List.fromList(img.encodePng(resized));
    outMime = 'image/png';
    outExt = 'png';
  }

  final dotIdx = args.filename.lastIndexOf('.');
  final baseName = dotIdx > 0 ? args.filename.substring(0, dotIdx) : args.filename;
  return PreparedUploadImage(
    bytes: encoded,
    filename: '$baseName.$outExt',
    mimeType: outMime,
    wasResized: true,
  );
}

/// Checks if a local image's natural dimensions exceed 4096px.
Future<bool> isImageOversized(Uint8List bytes) async {
  return compute((Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return false;
    return max(decoded.width, decoded.height) > kMaxImageEdge;
  }, bytes);
}
