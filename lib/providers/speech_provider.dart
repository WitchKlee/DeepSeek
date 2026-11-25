import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../services/api/api_errors.dart';
import '../services/speech/native_audio.dart';
import 'settings_provider.dart';

enum VoiceInputStatus { idle, recording, transcribing }

enum ReadAloudStatus { idle, loading, playing }

class SpeechProvider extends ChangeNotifier {
  final SettingsProvider settingsProvider;

  SpeechProvider(this.settingsProvider) {
    _ttsFinishedSub = NativeAudioService.ttsFinishedStream.listen((_) {
      if (_readAloudStatus != ReadAloudStatus.idle) {
        _readingMessageId = null;
        _readAloudStatus = ReadAloudStatus.idle;
        notifyListeners();
      }
    });
  }

  // --- Voice Input (ASR) ---
  VoiceInputStatus _voiceStatus = VoiceInputStatus.idle;
  List<double> _spectrumBars = List.filled(40, 0.0);
  double _recordingSeconds = 0.0;
  StreamSubscription<AudioSpectrumEvent>? _spectrumSub;
  http.Client? _asrClient;
  void Function(String text)? _onTranscribed;
  void Function(String msg)? _onToast;

  VoiceInputStatus get voiceStatus => _voiceStatus;
  List<double> get spectrumBars => _spectrumBars;
  double get recordingSeconds => _recordingSeconds;
  bool get isVoiceBusy => _voiceStatus != VoiceInputStatus.idle;

  // --- Read Aloud (TTS) ---
  String? _readingMessageId;
  ReadAloudStatus _readAloudStatus = ReadAloudStatus.idle;
  http.Client? _ttsClient;
  int _ttsGeneration = 0;
  StreamSubscription<void>? _ttsFinishedSub;

  String? get readingMessageId => _readingMessageId;
  ReadAloudStatus get readAloudStatus => _readAloudStatus;

  ReadAloudStatus statusForMessage(String messageId) {
    if (_readingMessageId != messageId) return ReadAloudStatus.idle;
    return _readAloudStatus;
  }

  Future<void> toggleVoiceInput({
    required void Function(String text) onTranscribed,
    required void Function(String msg) onToast,
    required VoidCallback onNeedApiKey,
  }) async {
    _onTranscribed = onTranscribed;
    _onToast = onToast;

    if (!settingsProvider.hasApiKey) {
      onNeedApiKey();
      return;
    }

    if (_voiceStatus == VoiceInputStatus.recording) {
      await _finishRecordingAndTranscribe();
      return;
    }

    if (_voiceStatus == VoiceInputStatus.transcribing) {
      _cancelTranscription();
      return;
    }

    // Stop TTS before recording
    await stopReadAloud();

    final s = settingsProvider.strings;
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      onToast(s.micPermissionDenied);
      return;
    }

    try {
      _spectrumBars = List.filled(40, 0.0);
      _recordingSeconds = 0.0;
      _voiceStatus = VoiceInputStatus.recording;
      notifyListeners();

      _spectrumSub?.cancel();
      _spectrumSub = NativeAudioService.spectrumStream.listen((event) {
        _spectrumBars = event.bars;
        _recordingSeconds = event.seconds;
        notifyListeners();
        if (event.limitReached && _voiceStatus == VoiceInputStatus.recording) {
          _onToast?.call(settingsProvider.strings.recordingLimitReached);
          _finishRecordingAndTranscribe();
        }
      });

      await NativeAudioService.startRecording();
    } catch (e) {
      _spectrumSub?.cancel();
      _spectrumSub = null;
      _voiceStatus = VoiceInputStatus.idle;
      notifyListeners();
      onToast(s.asrFailed);
    }
  }

  Future<void> cancelVoiceInput() async {
    _spectrumSub?.cancel();
    _spectrumSub = null;
    if (_voiceStatus == VoiceInputStatus.recording) {
      try {
        await NativeAudioService.cancelRecording();
      } catch (_) {}
    } else if (_voiceStatus == VoiceInputStatus.transcribing) {
      _cancelTranscription();
      return;
    }
    _voiceStatus = VoiceInputStatus.idle;
    _spectrumBars = List.filled(40, 0.0);
    _recordingSeconds = 0.0;
    notifyListeners();
  }

  void _cancelTranscription() {
    _asrClient?.close();
    _asrClient = null;
    _voiceStatus = VoiceInputStatus.idle;
    notifyListeners();
  }

  Future<void> _finishRecordingAndTranscribe() async {
    _spectrumSub?.cancel();
    _spectrumSub = null;
    final s = settingsProvider.strings;

    String? wavPath;
    try {
      wavPath = await NativeAudioService.stopRecording();
    } catch (_) {}

    if (wavPath == null) {
      _voiceStatus = VoiceInputStatus.idle;
      notifyListeners();
      _onToast?.call(s.asrEmpty);
      return;
    }

    _voiceStatus = VoiceInputStatus.transcribing;
    notifyListeners();

    final client = http.Client();
    _asrClient = client;

    try {
      final file = File(wavPath);
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}

      final text = await settingsProvider
          .createClient()
          .transcribeAudio(wavBytes: bytes, client: client);
      if (_asrClient != client) return; // cancelled
      _asrClient = null;
      _voiceStatus = VoiceInputStatus.idle;
      notifyListeners();

      if (text.trim().isEmpty) {
        _onToast?.call(s.asrEmpty);
      } else {
        _onTranscribed?.call(text);
      }
    } catch (e) {
      if (_asrClient != client) return; // cancelled
      _asrClient = null;
      _voiceStatus = VoiceInputStatus.idle;
      notifyListeners();
      _onToast?.call(_describeAsrError(e));
    } finally {
      client.close();
    }
  }

  String _describeAsrError(Object e) {
    final s = settingsProvider.strings;
    if (e is ApiError) {
      final cond = classifyApiError(e);
      if (cond == ApiErrorCondition.unauthorized) return s.apiKeyInvalid;
      if (cond == ApiErrorCondition.insufficientBalance) {
        return s.replyInsufficientBalance;
      }
      if (cond == ApiErrorCondition.rateLimited) return s.replyRateLimited;
      if (cond == ApiErrorCondition.network) return s.networkError;
    }
    return s.asrFailed;
  }

  Future<void> toggleReadAloud({
    required String messageId,
    required String text,
    required void Function(String msg) onToast,
    required VoidCallback onNeedApiKey,
  }) async {
    if (_readingMessageId == messageId &&
        _readAloudStatus != ReadAloudStatus.idle) {
      await stopReadAloud();
      return;
    }

    if (!settingsProvider.hasApiKey) {
      onNeedApiKey();
      return;
    }

    await stopReadAloud();

    final gen = ++_ttsGeneration;
    _readingMessageId = messageId;
    _readAloudStatus = ReadAloudStatus.loading;
    notifyListeners();

    final client = http.Client();
    _ttsClient = client;

    try {
      final response = await settingsProvider.createClient().streamTts(
            text: text,
            voiceId: settingsProvider.settings.ttsVoice.apiValue,
            client: client,
          );

      if (gen != _ttsGeneration) return;

      await NativeAudioService.startPcmPlayback();
      var startedPlaying = false;
      int? trailingByte;

      await for (final rawChunk in response.stream) {
        if (gen != _ttsGeneration) return;
        if (rawChunk.isEmpty) continue;

        // Keep 16-bit LE PCM sample alignment across chunk boundaries
        Uint8List aligned;
        if (trailingByte != null) {
          final merged = Uint8List(rawChunk.length + 1);
          merged[0] = trailingByte;
          merged.setRange(1, merged.length, rawChunk);
          trailingByte = null;
          aligned = merged;
        } else {
          aligned = Uint8List.fromList(rawChunk);
        }

        if (aligned.length.isOdd) {
          trailingByte = aligned.last;
          aligned = aligned.sublist(0, aligned.length - 1);
        }

        if (aligned.isEmpty) continue;

        if (!startedPlaying) {
          startedPlaying = true;
          _readAloudStatus = ReadAloudStatus.playing;
          notifyListeners();
        }
        await NativeAudioService.feedPcm(aligned);
      }

      if (gen != _ttsGeneration) return;

      if (!startedPlaying) {
        await NativeAudioService.stopPcmPlayback();
        _readingMessageId = null;
        _readAloudStatus = ReadAloudStatus.idle;
        notifyListeners();
      } else {
        await NativeAudioService.finishPcmPlayback();
      }
    } catch (e) {
      if (gen != _ttsGeneration) return;
      await NativeAudioService.stopPcmPlayback();
      _readingMessageId = null;
      _readAloudStatus = ReadAloudStatus.idle;
      notifyListeners();
      onToast(_describeTtsError(e));
    } finally {
      if (_ttsClient == client) {
        _ttsClient = null;
      }
      client.close();
    }
  }

  Future<void> stopReadAloud() async {
    _ttsGeneration++;
    _ttsClient?.close();
    _ttsClient = null;
    try {
      await NativeAudioService.stopPcmPlayback();
    } catch (_) {}
    if (_readingMessageId != null || _readAloudStatus != ReadAloudStatus.idle) {
      _readingMessageId = null;
      _readAloudStatus = ReadAloudStatus.idle;
      notifyListeners();
    }
  }

  String _describeTtsError(Object e) {
    final s = settingsProvider.strings;
    if (e is ApiError) {
      if (e.kind == ApiErrorKind.protocol && e.message.isNotEmpty) {
        return e.message;
      }
      if (e.status == 400) return s.ttsUnavailable;
      final cond = classifyApiError(e);
      if (cond == ApiErrorCondition.unauthorized) return s.apiKeyInvalid;
      if (cond == ApiErrorCondition.insufficientBalance) {
        return s.replyInsufficientBalance;
      }
      if (cond == ApiErrorCondition.rateLimited) return s.replyRateLimited;
      if (cond == ApiErrorCondition.network) return s.networkError;
    }
    return s.ttsFailed;
  }

  @override
  void dispose() {
    _spectrumSub?.cancel();
    _ttsFinishedSub?.cancel();
    _asrClient?.close();
    _ttsClient?.close();
    super.dispose();
  }
}
