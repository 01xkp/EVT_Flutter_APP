package com.signify.hue.flutterreactiveble.utils

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.VisibleForTesting
import io.flutter.plugin.common.EventChannel

/**
 * Emits raw Android BLE diagnostics to both Logcat and an optional Flutter
 * EventChannel. The latter lets the host app persist native-only evidence when
 * a packet never reaches the normal characteristic-value stream.
 */
internal object NativeBleLog {
    private const val tag = "AIPIN_BLE"

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    private var mainHandler: Handler? = null

    private val androidSink: (String, String) -> Unit = { level, message ->
        when (level) {
            "D" -> Log.d(tag, message)
            "W" -> Log.w(tag, message)
            else -> Log.e(tag, message)
        }
        Unit
    }

    @VisibleForTesting
    internal var sink: (String, String) -> Unit = androidSink

    fun debug(
        event: String,
        message: String,
        fields: Map<String, Any?> = emptyMap(),
        rawPacketHex: String? = null,
    ) = emit("D", event, message, fields, rawPacketHex)

    fun warn(
        event: String,
        message: String,
        fields: Map<String, Any?> = emptyMap(),
        rawPacketHex: String? = null,
    ) = emit("W", event, message, fields, rawPacketHex)

    fun error(
        event: String,
        message: String,
        fields: Map<String, Any?> = emptyMap(),
        rawPacketHex: String? = null,
    ) = emit("E", event, message, fields, rawPacketHex)

    fun attachEventSink(sink: EventChannel.EventSink?) {
        if (sink != null && mainHandler == null) {
            mainHandler = Handler(Looper.getMainLooper())
        }
        // Volatile publication makes the associated main handler visible to a
        // BLE callback that arrives immediately on a background thread.
        eventSink = sink
    }

    fun detachEventSink(sink: EventChannel.EventSink) {
        if (eventSink === sink) {
            eventSink = null
        }
    }

    fun clearEventSink() {
        eventSink = null
    }

    private fun emit(
        level: String,
        event: String,
        message: String,
        fields: Map<String, Any?>,
        rawPacketHex: String?,
    ) {
        sink(level, renderMessage(event, message, fields, rawPacketHex))

        val sinkAtEmission = eventSink ?: return
        val payload = linkedMapOf<String, Any?>(
            "timestamp_ms" to System.currentTimeMillis(),
            "level" to level,
            "event" to event,
            "message" to message,
            "fields" to safeFields(fields),
            "raw_packet_hex" to rawPacketHex,
        )
        val emitToFlutter = Runnable {
            if (eventSink === sinkAtEmission) {
                sinkAtEmission.success(payload)
            }
        }
        val handler = mainHandler
        if (handler != null && Looper.myLooper() != Looper.getMainLooper()) {
            handler.post(emitToFlutter)
        } else {
            emitToFlutter.run()
        }
    }

    private fun renderMessage(
        event: String,
        message: String,
        fields: Map<String, Any?>,
        rawPacketHex: String?,
    ): String = buildString {
        append(message)
        append(" event=").append(event)
        safeFields(fields).forEach { (key, value) ->
            append(' ').append(key).append('=').append(value)
        }
        if (rawPacketHex != null) {
            append(" raw_packet_hex=").append(rawPacketHex)
        }
    }

    private fun safeFields(fields: Map<String, Any?>): Map<String, Any?> =
        linkedMapOf<String, Any?>().apply {
            fields.forEach { (key, value) ->
                put(
                    key,
                    when (value) {
                        null,
                        is String,
                        is Number,
                        is Boolean -> value
                        else -> value.toString()
                    },
                )
            }
        }

    @VisibleForTesting
    internal fun resetForTests() {
        sink = androidSink
        clearEventSink()
        mainHandler = null
    }
}
