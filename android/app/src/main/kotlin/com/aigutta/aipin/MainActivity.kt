package com.aigutta.aipin

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.content.ContentValues
import android.content.ContentUris
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val bluetoothChannel = "com.aigutta.aipin/bluetooth"
        private const val audioSegmentationChannel = "com.aigutta.aipin/audio-segmentation"
        private const val publicDiagnosticLogsChannel = "aipin/public_diagnostic_logs"
        private const val enableBluetoothRequestCode = 7101
    }

    private var pendingBluetoothEnableResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bluetoothChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestEnable" -> requestBluetoothEnable(result)
                    "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioSegmentationChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "splitM4a") {
                    splitM4a(call, result)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, publicDiagnosticLogsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "mirrorCanonicalLog") {
                    mirrorCanonicalLog(call, result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun mirrorCanonicalLog(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val filename = call.argument<String>("filename")
        if (sourcePath.isNullOrBlank() || filename.isNullOrBlank()) {
            result.success(mirrorFailure("invalid_arguments"))
            return
        }
        Thread {
            val response = try {
                mirrorCanonicalLogFile(sourcePath, filename)
            } catch (_: Exception) {
                mirrorFailure("storage_error")
            }
            runOnUiThread { result.success(response) }
        }.start()
    }

    private fun mirrorCanonicalLogFile(sourcePath: String, filename: String): Map<String, Any?> {
        if (!BuildConfig.DEBUG) return mirrorFailure("debug_only")
        if (!filename.matches(Regex("aipin-\\d{4}-\\d{2}-\\d{2}\\.log"))) {
            return mirrorFailure("invalid_filename")
        }
        val source = File(sourcePath)
        val appFiles = filesDir.canonicalFile
        if (!source.isFile || !source.canonicalFile.path.startsWith("${appFiles.path}${File.separator}")) {
            return mirrorFailure("invalid_source")
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            mirrorWithMediaStore(source, filename)
        } else {
            mirrorLegacyDownload(source, filename)
        }
    }

    private fun mirrorWithMediaStore(source: File, filename: String): Map<String, Any?> {
        val relativePath = "Download/AIPIN/logs/$filename"
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        contentResolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
            arrayOf(filename, "Download/AIPIN/logs%"),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                contentResolver.delete(
                    ContentUris.withAppendedId(
                        collection,
                        cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)),
                    ),
                    null,
                    null,
                )
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/AIPIN/logs")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values) ?: return mirrorFailure("storage_error")
        try {
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                FileInputStream(source).use { input -> input.copyTo(output) }
            } ?: return mirrorFailure("storage_error")
            contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            return mirrorSuccess(relativePath)
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun mirrorLegacyDownload(source: File, filename: String): Map<String, Any?> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) return mirrorFailure("legacy_permission_required")
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "AIPIN/logs",
        )
        if (!directory.exists() && !directory.mkdirs()) return mirrorFailure("storage_error")
        FileInputStream(source).use { input ->
            FileOutputStream(File(directory, filename), false).use { output -> input.copyTo(output) }
        }
        return mirrorSuccess("Download/AIPIN/logs/$filename")
    }

    private fun mirrorSuccess(relativePath: String): Map<String, Any?> = mapOf(
        "available" to true,
        "relativePath" to relativePath,
        "lastUpdatedAtEpochMilliseconds" to System.currentTimeMillis(),
    )

    private fun mirrorFailure(code: String): Map<String, Any?> = mapOf(
        "available" to false,
        "failureCode" to code,
    )

    private fun splitM4a(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val outputPathPrefix = call.argument<String>("outputPathPrefix")
        val maximumSegmentMilliseconds = call.argument<Int>("maximumSegmentMilliseconds")
        if (sourcePath.isNullOrBlank() || outputPathPrefix.isNullOrBlank() ||
            maximumSegmentMilliseconds == null || maximumSegmentMilliseconds <= 0
        ) {
            result.error("invalid_arguments", "Invalid M4A segmentation request", null)
            return
        }
        Thread {
            try {
                val segments = splitM4aFile(
                    sourcePath = sourcePath,
                    outputPathPrefix = outputPathPrefix,
                    maximumSegmentMilliseconds = maximumSegmentMilliseconds,
                )
                runOnUiThread {
                    result.success(segments.map { segment ->
                        mapOf(
                            "index" to segment.index,
                            "durationMilliseconds" to segment.durationMilliseconds,
                        )
                    })
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("audio_segmentation_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun splitM4aFile(
        sourcePath: String,
        outputPathPrefix: String,
        maximumSegmentMilliseconds: Int,
    ): List<M4aSegment> {
        val source = File(sourcePath)
        require(source.isFile && source.length() > 0) { "Audio source is unavailable" }
        val extractor = MediaExtractor()
        val outputs = mutableListOf<File>()
        try {
            extractor.setDataSource(source.path)
            val audioTrackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index)
                    .getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("Audio track is unavailable")
            val format = extractor.getTrackFormat(audioTrackIndex)
            val maximumInputSize = format.getIntegerOrDefault(
                MediaFormat.KEY_MAX_INPUT_SIZE,
                256 * 1024,
            )
            val sampleBuffer = ByteBuffer.allocate(maximumInputSize)
            val maximumSegmentMicroseconds = maximumSegmentMilliseconds.toLong() * 1000L
            val segments = mutableListOf<M4aSegment>()
            extractor.selectTrack(audioTrackIndex)

            var muxer: MediaMuxer? = null
            var muxerTrackIndex = -1
            var segmentStartMicroseconds = -1L
            var segmentLastMicroseconds = -1L
            var segmentIndex = 0

            fun closeSegment() {
                val activeMuxer = muxer ?: return
                try {
                    activeMuxer.stop()
                } finally {
                    activeMuxer.release()
                    val durationMilliseconds = ((segmentLastMicroseconds -
                        segmentStartMicroseconds) / 1000L).coerceAtLeast(1L)
                    segments.add(M4aSegment(segmentIndex, durationMilliseconds))
                    segmentIndex += 1
                    muxer = null
                }
            }

            while (true) {
                val sampleTime = extractor.sampleTime
                if (sampleTime < 0) {
                    break
                }
                if (muxer == null || sampleTime - segmentStartMicroseconds >= maximumSegmentMicroseconds) {
                    closeSegment()
                    val output = File(
                        "$outputPathPrefix${String.format(Locale.US, "%04d", segmentIndex)}.m4a",
                    )
                    output.parentFile?.mkdirs()
                    if (output.exists()) {
                        output.delete()
                    }
                    outputs.add(output)
                    muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                    muxerTrackIndex = muxer!!.addTrack(format)
                    muxer!!.start()
                    segmentStartMicroseconds = sampleTime
                    segmentLastMicroseconds = sampleTime
                }
                sampleBuffer.clear()
                val sampleSize = extractor.readSampleData(sampleBuffer, 0)
                if (sampleSize < 0) {
                    break
                }
                sampleBuffer.position(0)
                sampleBuffer.limit(sampleSize)
                val bufferInfo = MediaCodec.BufferInfo().apply {
                    set(
                        0,
                        sampleSize,
                        sampleTime - segmentStartMicroseconds,
                        extractor.sampleFlags,
                    )
                }
                muxer!!.writeSampleData(muxerTrackIndex, sampleBuffer, bufferInfo)
                segmentLastMicroseconds = sampleTime
                extractor.advance()
            }
            closeSegment()
            require(segments.isNotEmpty()) { "Audio source contains no samples" }
            return segments
        } catch (error: Exception) {
            outputs.forEach { output -> output.delete() }
            throw error
        } finally {
            extractor.release()
        }
    }

    private fun MediaFormat.getIntegerOrDefault(key: String, fallback: Int): Int {
        return if (containsKey(key)) getInteger(key).coerceAtLeast(fallback) else fallback
    }

    private data class M4aSegment(
        val index: Int,
        val durationMilliseconds: Long,
    )

    @Suppress("DEPRECATION")
    private fun requestBluetoothEnable(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            result.success("unavailable")
            return
        }
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            result.success("unavailable")
            return
        }
        if (adapter.isEnabled) {
            result.success("enabled")
            return
        }
        if (pendingBluetoothEnableResult != null) {
            result.error(
                "enable_in_progress",
                "Bluetooth enable request is already active",
                null,
            )
            return
        }
        pendingBluetoothEnableResult = result
        startActivityForResult(
            Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
            enableBluetoothRequestCode,
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == enableBluetoothRequestCode) {
            val result = pendingBluetoothEnableResult
            pendingBluetoothEnableResult = null
            result?.success(if (resultCode == Activity.RESULT_OK) "enabled" else "cancelled")
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
