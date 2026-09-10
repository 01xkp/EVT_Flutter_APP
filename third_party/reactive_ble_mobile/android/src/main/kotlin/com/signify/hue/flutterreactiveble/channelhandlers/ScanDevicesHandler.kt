package com.signify.hue.flutterreactiveble.channelhandlers

import android.os.ParcelUuid
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.signify.hue.flutterreactiveble.converters.ProtobufMessageConverter
import com.signify.hue.flutterreactiveble.converters.UuidConverter
import com.signify.hue.flutterreactiveble.model.ScanMode
import com.signify.hue.flutterreactiveble.model.createScanMode
import io.flutter.plugin.common.EventChannel
import io.reactivex.android.schedulers.AndroidSchedulers
import io.reactivex.disposables.Disposable
import com.signify.hue.flutterreactiveble.ProtobufModel as pb

class ScanDevicesHandler(
    private val bleClient: com.signify.hue.flutterreactiveble.ble.BleClient,
) : EventChannel.StreamHandler {
    private var scanDevicesSink: EventChannel.EventSink? = null
    private lateinit var scanForDevicesDisposable: Disposable
    private val mainHandler = Handler(Looper.getMainLooper())
    private var delayedStart: Runnable? = null
    private var lastScanStoppedAt = 0L
    private val converter = ProtobufMessageConverter()

    companion object {
        // Android can reject a new registration for a short period after the
        // previous BluetoothLeScanner was stopped.
        private const val SCAN_RESTART_COOLDOWN_MS = 250L
        private var scanParameters: ScanParameters? = null
    }

    override fun onListen(
        objectSink: Any?,
        eventSink: EventChannel.EventSink?,
    ) {
        eventSink?.let {
            scanDevicesSink = eventSink
            startDeviceScan()
        }
    }

    override fun onCancel(objectSink: Any?) {
        stopDeviceScan()
        scanDevicesSink = null
    }

    private fun startDeviceScan() {
        val remainingCooldown =
            SCAN_RESTART_COOLDOWN_MS - (SystemClock.elapsedRealtime() - lastScanStoppedAt)
        if (remainingCooldown > 0) {
            val restart = Runnable {
                delayedStart = null
                if (scanDevicesSink != null) startDeviceScan()
            }
            delayedStart = restart
            mainHandler.postDelayed(restart, remainingCooldown)
            return
        }
        startDeviceScanNow()
    }

    private fun startDeviceScanNow() {
        scanParameters?.let { params ->
            scanForDevicesDisposable =
                bleClient.scanForDevices(params.filter, params.mode, params.locationServiceIsMandatory)
                    .observeOn(AndroidSchedulers.mainThread())
                    .subscribe(
                        { scanResult ->
                            handleDeviceScanResult(converter.convertScanInfo(scanResult))
                        },
                        { throwable ->
                            handleDeviceScanResult(converter.convertScanErrorInfo(throwable.message))
                        },
                    )
        }
            ?: handleDeviceScanResult(converter.convertScanErrorInfo("Scanning parameters are not set"))
    }

    fun stopDeviceScan() {
        val hadActiveScan =
            delayedStart != null ||
                (this::scanForDevicesDisposable.isInitialized &&
                    !scanForDevicesDisposable.isDisposed)
        delayedStart?.let {
            mainHandler.removeCallbacks(it)
            delayedStart = null
        }
        if (hadActiveScan) {
            lastScanStoppedAt = SystemClock.elapsedRealtime()
        }
        if (this::scanForDevicesDisposable.isInitialized) {
            scanForDevicesDisposable.let {
                if (!it.isDisposed) {
                    it.dispose()
                }
            }
        }
        scanParameters = null
    }

    fun prepareScan(scanMessage: pb.ScanForDevicesRequest) {
        stopDeviceScan()
        val filter =
            scanMessage.serviceUuidsList
                .map { ParcelUuid(UuidConverter().uuidFromByteArray(it.data.toByteArray())) }
        val scanMode = createScanMode(scanMessage.scanMode)
        scanParameters = ScanParameters(filter, scanMode, scanMessage.requireLocationServicesEnabled)
    }

    private fun handleDeviceScanResult(discoveryMessage: pb.DeviceScanInfo) {
        scanDevicesSink?.success(discoveryMessage.toByteArray())
    }
}

private data class ScanParameters(
    val filter: List<ParcelUuid>,
    val mode: ScanMode,
    val locationServiceIsMandatory: Boolean,
)
