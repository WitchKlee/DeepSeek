import 'dart:async';
import 'package:flutter/services.dart';

class AudioSpectrumEvent {
  final List<double> bars;
  final double seconds;
  final bool limitReached;

  const AudioSpectrumEvent({
    required this.bars,
    required this.seconds,
    required this.limitReached,
  });
}

/// Bridge to native Android AudioRecord (16kHz mono PCM WAV + spectrum)
/// and AudioTrack (24kHz mono streaming PCM playback).
class NativeAudioService {
  static const _method = MethodChannel('com.witchklee.deepseek_chat/audio');
  static const _events = EventChannel('com.witchklee.deepseek_chat/spectrum');

  static Stream<Map<dynamic, dynamic>>? _broadcast;

  static Stream<Map<dynamic, dynamic>> get _rawStream {
    _broadcast ??= _events
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .cast<Map<dynamic, dynamic>>()
        .asBroadcastStream();
    return _broadcast!;
  }

  static Stream<AudioSpectrumEvent> get spectrumStream => _rawStream
      .where((m) => m.containsKey('bars'))
      .map((m) => AudioSpectrumEvent(
            bars: (m['bars'] as List)
                .map((e) => (e as num).toDouble().clamp(0.0, 1.0))
                .toList(),
            seconds: (m['seconds'] as num?)?.toDouble() ?? 0.0,
            limitReached: m['limitReached'] == true,
          ));

  static Stream<void> get ttsFinishedStream =>
      _rawStream.where((m) => m['ttsFinished'] == true).map((_) {});

  static Future<void> startRecording() async {
    await _method.invokeMethod('startRecording');
  }

  static Future<String?> stopRecording({String? outputPath}) async {
    return _method.invokeMethod<String>(
      'stopRecording',
      {'outputPath': outputPath},
    );
  }

  static Future<void> cancelRecording() async {
    await _method.invokeMethod('cancelRecording');
  }

  static Future<void> startPcmPlayback() async {
    await _method.invokeMethod('startPcmPlayback');
  }

  static Future<void> feedPcm(Uint8List bytes) async {
    await _method.invokeMethod('feedPcm', {'bytes': bytes});
  }

  static Future<void> finishPcmPlayback() async {
    await _method.invokeMethod('finishPcmPlayback');
  }

  static Future<void> stopPcmPlayback() async {
    await _method.invokeMethod('stopPcmPlayback');
  }
}
