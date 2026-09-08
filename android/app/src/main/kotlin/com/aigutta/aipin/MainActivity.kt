package com.aigutta.aipin

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.content.ContentValues
import android.content.ContentUris
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.polidea.rxandroidble2.exceptions.BleException
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val bluetoothChannel = "com.aigutta.aipin/bluetooth"
        private const val publicDiagnosticLogsChannel = "aipin/public_diagnostic_logs"
        private const val enableBluetoothRequestCode = 7101
        private const val legacyLogStoragePermissionRequestCode = 7102
    }

    private var pendingBluetoothEnableResult: MethodChannel.Result? = null
    private var legacyLogStoragePermissionRequestInFlight = false
    private val pendingLegacyLogMirrors = mutableListOf<PendingLegacyLogMirror>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        installReactiveBleUndeliverableErrorHandler()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bluetoothChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestEnable" -> requestBluetoothEnable(result)
                    "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
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

    /**
     * RxAndroidBle can emit a disconnect error after Flutter has cancelled the
     * corresponding subscription. There is intentionally no subscriber left
     * to receive that error, so RxJava surfaces it as an UndeliverableException.
     * Ignore only that documented case and preserve every other native error.
     */
    private fun installReactiveBleUndeliverableErrorHandler() {
        RxJavaPlugins.setErrorHandler { throwable ->
            if (throwable is UndeliverableException && throwable.cause is BleException) {
                return@setErrorHandler
            }
            throw throwable
        }
    }

    private fun mirrorCanonicalLog(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val filename = call.argument<String>("filename")
        if (sourcePath.isNullOrBlank() || filename.isNullOrBlank()) {
            result.success(mirrorFailure("invalid_arguments"))
            return
        }
        if (requiresLegacyLogStoragePermission()) {
            pendingLegacyLogMirrors.add(PendingLegacyLogMirror(sourcePath, filename, result))
            requestLegacyLogStoragePermissionIfNeeded()
            return
        }
        mirrorCanonicalLogAsync(sourcePath, filename, result)
    }

    private fun mirrorCanonicalLogAsync(
        sourcePath: String,
        filename: String,
        result: MethodChannel.Result,
    ) {
        Thread {
            val response = try {
                mirrorCanonicalLogFile(sourcePath, filename)
            } catch (_: Exception) {
                mirrorFailure("storage_error")
            }
            runOnUiThread { result.success(response) }
        }.start()
    }

    private fun requiresLegacyLogStoragePermission(): Boolean =
        BuildConfig.DEBUG &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED

    private fun requestLegacyLogStoragePermissionIfNeeded() {
        if (legacyLogStoragePermissionRequestInFlight) {
            return
        }
        legacyLogStoragePermissionRequestInFlight = true
        requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            legacyLogStoragePermissionRequestCode,
        )
    }

    private fun completePendingLegacyLogMirrors(granted: Boolean) {
        val pending = pendingLegacyLogMirrors.toList()
        pendingLegacyLogMirrors.clear()
        for (request in pending) {
            if (granted) {
                mirrorCanonicalLogAsync(request.sourcePath, request.filename, request.result)
            } else {
                request.result.success(mirrorFailure("legacy_permission_denied"))
            }
        }
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
            val output = contentResolver.openOutputStream(uri, "w")
                ?: throw IllegalStateException("MediaStore output stream unavailable")
            output.use {
                FileInputStream(source).use { input -> input.copyTo(output) }
            }
            val updated = contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            if (updated != 1) {
                throw IllegalStateException("MediaStore pending update failed")
            }
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

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == legacyLogStoragePermissionRequestCode) {
            legacyLogStoragePermissionRequestInFlight = false
            completePendingLegacyLogMirrors(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
            )
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private data class PendingLegacyLogMirror(
        val sourcePath: String,
        val filename: String,
        val result: MethodChannel.Result,
    )
}
