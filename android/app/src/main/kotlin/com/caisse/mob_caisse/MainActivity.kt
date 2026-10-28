package com.caisse.mob_caisse

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.sin

// local_auth (fingerprint) needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    private val sampleRate = 44100

    // Short sine beeps, like a barcode scanner: one high "bip" for a good read, two low ones for an error.
    private val ok: ShortArray by lazy { tone(listOf(Triple(2600.0, 110, 0))) }
    private val error: ShortArray by lazy { tone(listOf(Triple(420.0, 130, 60), Triple(420.0, 160, 0))) }

    /** Segments are (frequency Hz, duration ms, silence after ms). */
    private fun tone(segments: List<Triple<Double, Int, Int>>): ShortArray {
        val out = ArrayList<Short>()
        for ((freq, ms, gap) in segments) {
            val n = sampleRate * ms / 1000
            for (i in 0 until n) {
                // Fast fade in / out so the beep does not click.
                val edge = minOf(i, n - 1 - i) / (sampleRate * 0.006)
                val env = minOf(1.0, edge)
                out.add((sin(2 * PI * freq * i / sampleRate) * env * 0.9 * Short.MAX_VALUE).toInt().toShort())
            }
            repeat(sampleRate * gap / 1000) { out.add(0) }
        }
        return out.toShortArray()
    }

    private fun play(samples: ShortArray) {
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(samples.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        track.write(samples, 0, samples.size)
        track.setNotificationMarkerPosition(samples.size)
        track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
            override fun onMarkerReached(t: AudioTrack) = t.release()
            override fun onPeriodicNotification(t: AudioTrack) {}
        })
        track.play()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "caisse/sound").setMethodCallHandler { call, result ->
            when (call.method) {
                "beep" -> { play(ok); result.success(null) }
                "error" -> { play(error); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
