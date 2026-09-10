package com.signify.hue.flutterreactiveble.channelhandlers

import com.signify.hue.flutterreactiveble.utils.NativeBleLog
import io.flutter.plugin.common.EventChannel

/**
 * Optional Debug diagnostics stream. It is deliberately independent from the
 * normal characteristic stream so a native receipt can be observed even if
 * the Dart BLE subscription is absent or fails before a packet is forwarded.
 */
internal class NativeBleLogHandler : EventChannel.StreamHandler {
    private var activeEventSink: EventChannel.EventSink? = null

    override fun onListen(
        arguments: Any?,
        eventSink: EventChannel.EventSink?,
    ) {
        activeEventSink = eventSink
        NativeBleLog.attachEventSink(eventSink)
        NativeBleLog.debug(
            event = "native_log_stream_listening",
            message = "【AIPIN原生BLE】【日志通道】原生 BLE 结构化日志监听已建立",
        )
    }

    override fun onCancel(arguments: Any?) {
        val sink = activeEventSink
        activeEventSink = null
        if (sink != null) {
            NativeBleLog.detachEventSink(sink)
        }
        NativeBleLog.warn(
            event = "native_log_stream_cancelled",
            message = "【AIPIN原生BLE】【日志通道】原生 BLE 结构化日志监听已取消",
        )
    }

    fun dispose() {
        val sink = activeEventSink
        activeEventSink = null
        if (sink != null) {
            NativeBleLog.detachEventSink(sink)
        }
    }
}
