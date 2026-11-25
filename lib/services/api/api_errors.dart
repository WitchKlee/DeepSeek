import 'dart:convert';
import '../../l10n/app_strings.dart';

enum ApiErrorKind { http, stream, network, interrupted, protocol }

enum ApiErrorCondition {
  unauthorized,
  insufficientBalance,
  tooLarge,
  rateLimited,
  serverBusy,
  network,
  other,
}

class ApiError implements Exception {
  final ApiErrorKind kind;
  final String message;
  final int? status;

  const ApiError(this.kind, this.message, {this.status});

  @override
  String toString() => 'ApiError($kind, status=$status, message=$message)';
}

ApiErrorCondition classifyStatus(int status) {
  if (status == 401) return ApiErrorCondition.unauthorized;
  if (status == 402) return ApiErrorCondition.insufficientBalance;
  if (status == 413) return ApiErrorCondition.tooLarge;
  if (status == 429) return ApiErrorCondition.rateLimited;
  if (status >= 500) return ApiErrorCondition.serverBusy;
  return ApiErrorCondition.other;
}

ApiErrorCondition classifyApiError(ApiError error) {
  if (error.status != null) return classifyStatus(error.status!);
  if (error.kind == ApiErrorKind.network) return ApiErrorCondition.network;
  return ApiErrorCondition.other;
}

bool isRetryableApiError(Object error) {
  if (error is! ApiError) return true;
  final cond = classifyApiError(error);
  return cond == ApiErrorCondition.network ||
      cond == ApiErrorCondition.rateLimited ||
      cond == ApiErrorCondition.serverBusy;
}

/// Checks if a decoded JSON map matches `{ error: { message: string } }`.
String? extractErrorBodyMessage(dynamic decoded) {
  if (decoded is Map) {
    final err = decoded['error'];
    if (err is Map && err['message'] is String) {
      return err['message'] as String;
    }
  }
  return null;
}

String readErrorResponseText(String body, String reasonPhrase) {
  if (body.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      final msg = extractErrorBodyMessage(decoded);
      if (msg != null && msg.isNotEmpty) return msg;
    } catch (_) {}
    return body.trim();
  }
  return reasonPhrase;
}

/// Detects expired or missing file_id errors on HTTP 400 (for auto-heal re-upload).
String? getFileErrorCode(Object error) {
  if (error is! ApiError || error.status != 400) return null;
  final msg = error.message;
  if (RegExp(
    r'file_ids do not exist or are not created under your account',
    caseSensitive: false,
  ).hasMatch(msg)) {
    return 'fileIdMissing';
  }
  if (RegExp(r'file data not found for file_id', caseSensitive: false)
      .hasMatch(msg)) {
    return 'fileDataMissing';
  }
  if (RegExp(r'\.source\.file_id: invalid file_id', caseSensitive: false)
      .hasMatch(msg)) {
    return 'invalidFileId';
  }
  return null;
}

List<String> extractFileIds(String message) {
  final matches = RegExp(r'file-api-[\w-]+').allMatches(message);
  return matches.map((m) => m.group(0)!).toSet().toList();
}

class UploadErrorInfo {
  final String code; // 'fileCountLimit' | 'storageLimit' | 'parseFailed'
  final String? limit;
  const UploadErrorInfo(this.code, [this.limit]);
}

UploadErrorInfo? getUploadErrorInfo(Object error) {
  if (error is! ApiError || error.status != 400) return null;
  final msg = error.message;

  final countMatch = RegExp(
    r'User file count limit exceeded.*?limit (\d+)',
    caseSensitive: false,
  ).firstMatch(msg);
  if (countMatch != null) {
    return UploadErrorInfo('fileCountLimit', countMatch.group(1));
  }

  final storageMatch = RegExp(
    r'User storage quota exceeded.*?limit ([\d.]+) GB',
    caseSensitive: false,
  ).firstMatch(msg);
  if (storageMatch != null) {
    return UploadErrorInfo('storageLimit', storageMatch.group(1));
  }

  final parsePatterns = [
    RegExp(r'You have uploaded an (unsupported|invalid) (file|image)',
        caseSensitive: false),
    RegExp(r'The image is too large to process', caseSensitive: false),
    RegExp(r'password-protected', caseSensitive: false),
    RegExp(r'Failed to recognize the file', caseSensitive: false),
  ];
  if (parsePatterns.any((p) => p.hasMatch(msg))) {
    return const UploadErrorInfo('parseFailed');
  }
  return null;
}

String describeUploadError(Object error, AppStrings s) {
  final info = getUploadErrorInfo(error);
  if (info != null) {
    switch (info.code) {
      case 'fileCountLimit':
        return s.fileCountLimit(info.limit ?? '');
      case 'storageLimit':
        return s.storageLimit(info.limit ?? '');
      case 'parseFailed':
        return s.parseFailed;
    }
  }
  if (error is ApiError) {
    final cond = classifyApiError(error);
    switch (cond) {
      case ApiErrorCondition.unauthorized:
        return s.apiKeyInvalid;
      case ApiErrorCondition.insufficientBalance:
        return s.replyInsufficientBalance;
      case ApiErrorCondition.tooLarge:
        return s.requestTooLarge;
      case ApiErrorCondition.rateLimited:
        return s.replyRateLimited;
      case ApiErrorCondition.serverBusy:
        return s.serverBusy;
      case ApiErrorCondition.network:
        return s.networkError;
      case ApiErrorCondition.other:
        return error.message.isNotEmpty ? error.message : s.uploadFailed;
    }
  }
  return s.uploadFailed;
}
