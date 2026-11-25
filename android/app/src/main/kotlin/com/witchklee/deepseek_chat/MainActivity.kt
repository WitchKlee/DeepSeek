package com.witchklee.deepseek_chat

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    companion object {
        private const val AUDIO_CHANNEL = "com.witchklee.deepseek_chat/audio"
        private const val SPECTRUM_CHANNEL = "com.witchklee.deepseek_chat/spectrum"
        private const val RECORDER_SAMPLE_RATE = 16000
        private const val MAX_RECORD_SECONDS = 120
        private const val MAX_RECORD_SAMPLES = RECORDER_SAMPLE_RATE * MAX_RECORD_SECONDS
        private const val TTS_SAMPLE_RATE = 24000
        private const val SPECTRUM_BARS = 40
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var spectrumSink: EventChannel.EventSink? = null

    // Recorder state
    private val isRecording = AtomicBoolean(false)
    private var recorderThread: Thread? = null
    private var audioRecord: AudioRecord? = null
    private val pcmBuffer = ByteArrayOutputStream()
    private val pcmLock = Any()

    // TTS Streaming PCM Player state
    private val playerLock = Any()
    private var audioTrack: AudioTrack? = null
    private var playerThread: Thread? = null
    private val pcmQueue = LinkedBlockingQueue<ByteArray>()
    private val isPlayingPcm = AtomicBoolean(false)
    private val streamEnded = AtomicBoolean(false)
    private val endSentinel = ByteArray(0)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SPECTRUM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    spectrumSink = events
                }

                override fun onCancel(arguments: Any?) {
                    spectrumSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> {
                        try {
                            startRecording()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("RECORD_START_ERROR", e.message, null)
                        }
                    }
                    "stopRecording" -> {
                        val outputPath = call.argument<String>("outputPath")
                        try {
                            val savedPath = stopRecording(outputPath)
                            result.success(savedPath)
                        } catch (e: Exception) {
                            result.error("RECORD_STOP_ERROR", e.message, null)
                        }
                    }
                    "cancelRecording" -> {
                        cancelRecording()
                        result.success(true)
                    }
                    "startPcmPlayback" -> {
                        try {
                            startPcmPlayback()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PCM_START_ERROR", e.message, null)
                        }
                    }
                    "feedPcm" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes != null && bytes.isNotEmpty() && isPlayingPcm.get()) {
                            pcmQueue.offer(bytes)
                        }
                        result.success(true)
                    }
                    "finishPcmPlayback" -> {
                        streamEnded.set(true)
                        pcmQueue.offer(endSentinel)
                        result.success(true)
                    }
                    "stopPcmPlayback" -> {
                        stopPcmPlayback()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startRecording() {
        cancelRecording()

        val minBuf = AudioRecord.getMinBufferSize(
            RECORDER_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = max(minBuf, 4096)

        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            RECORDER_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            throw IllegalStateException("AudioRecord initialization failed")
        }

        synchronized(pcmLock) {
            pcmBuffer.reset()
        }

        audioRecord = record
        isRecording.set(true)
        record.startRecording()

        val smoothed = DoubleArray(SPECTRUM_BARS) { 0.0 }

        recorderThread = Thread {
            val readBuf = ShortArray(1024)
            val byteBuf = ByteArray(readBuf.size * 2)
            var totalSamples = 0

            while (isRecording.get()) {
                val read = record.read(readBuf, 0, readBuf.size)
                if (read > 0) {
                    val remaining = MAX_RECORD_SAMPLES - totalSamples
                    val toTake = min(read, remaining)
                    if (toTake > 0) {
                        var j = 0
                        for (i in 0 until toTake) {
                            val s = readBuf[i].toInt()
                            byteBuf[j++] = (s and 0xFF).toByte()
                            byteBuf[j++] = ((s ushr 8) and 0xFF).toByte()
                        }
                        synchronized(pcmLock) {
                            pcmBuffer.write(byteBuf, 0, toTake * 2)
                        }
                        totalSamples += toTake
                    }

                    // Compute spectrum bars (approx 100Hz - 4000Hz log-spaced)
                    val levels = computeSpectrum(readBuf, read, smoothed)
                    val seconds = totalSamples.toDouble() / RECORDER_SAMPLE_RATE
                    val limitReached = totalSamples >= MAX_RECORD_SAMPLES

                    mainHandler.post {
                        spectrumSink?.success(
                            mapOf(
                                "bars" to levels,
                                "seconds" to seconds,
                                "limitReached" to limitReached
                            )
                        )
                    }

                    if (limitReached) {
                        isRecording.set(false)
                        break
                    }
                }
            }
        }.apply { start() }
    }

    private fun computeSpectrum(
        samples: ShortArray,
        length: Int,
        smoothed: DoubleArray
    ): List<Double> {
        val n = min(length, 512)
        if (n < 64) return smoothed.toList()

        // Fast Hann-windowed Goertzel / DFT on 40 log-spaced frequencies (100Hz .. 4000Hz)
        val fMin = 100.0
        val fMax = 4000.0
        val logMin = ln(fMin)
        val logMax = ln(fMax)
        val out = ArrayList<Double>(SPECTRUM_BARS)

        for (b in 0 until SPECTRUM_BARS) {
            val ratio = if (SPECTRUM_BARS > 1) b.toDouble() / (SPECTRUM_BARS - 1) else 0.0
            val freq = kotlin.math.exp(logMin + ratio * (logMax - logMin))
            val omega = 2.0 * PI * freq / RECORDER_SAMPLE_RATE
            val coeff = 2.0 * cos(omega)
            var s0: Double
            var s1 = 0.0
            var s2 = 0.0
            for (i in 0 until n) {
                val window = 0.5 * (1.0 - cos(2.0 * PI * i / (n - 1)))
                val x = (samples[i] / 32768.0) * window
                s0 = x + coeff * s1 - s2
                s2 = s1
                s1 = s0
            }
            val power = s1 * s1 + s2 * s2 - coeff * s1 * s2
            val mag = sqrt(max(0.0, power)) / (n / 2.0)
            val octaves = log10(freq / fMin) / log10(2.0)
            val db = 20.0 * log10(max(mag, 1e-6)) + octaves * 4.0
            val norm = ((db - (-80.0)) / ((-25.0) - (-80.0))).coerceIn(0.0, 1.0)
            val prev = smoothed[b]
            val next = if (norm > prev) {
                prev + (norm - prev) * 0.8
            } else {
                prev + (norm - prev) * 0.35
            }
            smoothed[b] = next
            out.add(next)
        }
        return out
    }

    private fun stopRecording(outputPath: String?): String? {
        isRecording.set(false)
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        try {
            recorderThread?.join(1000)
        } catch (_: Exception) {}
        try {
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
        recorderThread = null

        val pcmBytes: ByteArray
        synchronized(pcmLock) {
            pcmBytes = pcmBuffer.toByteArray()
            pcmBuffer.reset()
        }

        if (pcmBytes.isEmpty()) return null

        val path = outputPath ?: File(cacheDir, "recording_${System.currentTimeMillis()}.wav").absolutePath
        writeWavFile(File(path), pcmBytes, RECORDER_SAMPLE_RATE)
        return path
    }

    private fun cancelRecording() {
        isRecording.set(false)
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        try {
            recorderThread?.join(500)
        } catch (_: Exception) {}
        try {
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
        recorderThread = null
        synchronized(pcmLock) {
            pcmBuffer.reset()
        }
    }

    private fun writeWavFile(file: File, pcmData: ByteArray, sampleRate: Int) {
        val channels = 1
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val dataSize = pcmData.size
        val chunkSize = 36 + dataSize

        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt(chunkSize)
            put("WAVE".toByteArray(Charsets.US_ASCII))
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16) // PCM subchunk1 size
            putShort(1.toShort()) // AudioFormat = 1 (PCM)
            putShort(channels.toShort())
            putInt(sampleRate)
            putInt(byteRate)
            putShort(blockAlign.toShort())
            putShort(bitsPerSample.toShort())
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataSize)
        }.array()

        FileOutputStream(file).use { out ->
            out.write(header)
            out.write(pcmData)
        }
    }

    private fun startPcmPlayback() {
        stopPcmPlayback()

        val minBuf = AudioTrack.getMinBufferSize(
            TTS_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = max(minBuf * 2, 16384)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(TTS_SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        synchronized(playerLock) {
            audioTrack = track
            pcmQueue.clear()
            streamEnded.set(false)
            isPlayingPcm.set(true)
        }

        track.play()

        playerThread = Thread {
            try {
                while (isPlayingPcm.get()) {
                    val chunk = pcmQueue.take()
                    if (chunk === endSentinel || (!isPlayingPcm.get())) {
                        break
                    }
                    var offset = 0
                    while (offset < chunk.size && isPlayingPcm.get()) {
                        val written = track.write(chunk, offset, chunk.size - offset)
                        if (written <= 0) break
                        offset += written
                    }
                }
                if (isPlayingPcm.get() && streamEnded.get()) {
                    // Let remaining audio drain naturally
                    Thread.sleep(250)
                }
            } catch (_: InterruptedException) {
            } finally {
                val finishedNaturally = isPlayingPcm.compareAndSet(true, false) && streamEnded.get()
                synchronized(playerLock) {
                    try {
                        track.stop()
                    } catch (_: Exception) {}
                    try {
                        track.release()
                    } catch (_: Exception) {}
                    if (audioTrack === track) {
                        audioTrack = null
                    }
                }
                if (finishedNaturally) {
                    mainHandler.post {
                        spectrumSink?.success(mapOf("ttsFinished" to true))
                    }
                }
            }
        }.apply { start() }
    }

    private fun stopPcmPlayback() {
        isPlayingPcm.set(false)
        streamEnded.set(false)
        pcmQueue.clear()
        pcmQueue.offer(endSentinel)
        synchronized(playerLock) {
            try {
                audioTrack?.pause()
                audioTrack?.flush()
                audioTrack?.stop()
            } catch (_: Exception) {}
        }
        try {
            playerThread?.join(400)
        } catch (_: Exception) {}
        playerThread = null
    }

    override fun onDestroy() {
        cancelRecording()
        stopPcmPlayback()
        super.onDestroy()
    }
}
