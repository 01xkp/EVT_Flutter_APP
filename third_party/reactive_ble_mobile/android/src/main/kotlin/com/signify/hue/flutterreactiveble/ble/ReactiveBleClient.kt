package com.signify.hue.flutterreactiveble.ble

import android.bluetooth.BluetoothDevice.BOND_BONDING
import android.bluetooth.BluetoothGattCharacteristic
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import androidx.annotation.VisibleForTesting
import com.polidea.rxandroidble2.LogConstants
import com.polidea.rxandroidble2.LogOptions
import com.polidea.rxandroidble2.NotificationSetupMode
import com.polidea.rxandroidble2.RxBleClient
import com.polidea.rxandroidble2.RxBleConnection
import com.polidea.rxandroidble2.RxBleDevice
import com.polidea.rxandroidble2.RxBleDeviceServices
import com.polidea.rxandroidble2.scan.IsConnectable
import com.polidea.rxandroidble2.scan.ScanFilter
import com.polidea.rxandroidble2.scan.ScanSettings
import com.signify.hue.flutterreactiveble.ble.extensions.resolveCharacteristic
import com.signify.hue.flutterreactiveble.ble.extensions.writeCharWithResponse
import com.signify.hue.flutterreactiveble.ble.extensions.writeCharWithoutResponse
import com.signify.hue.flutterreactiveble.converters.extractManufacturerData
import com.signify.hue.flutterreactiveble.model.ScanMode
import com.signify.hue.flutterreactiveble.model.toScanSettings
import com.signify.hue.flutterreactiveble.utils.Duration
import com.signify.hue.flutterreactiveble.utils.NativeBleLog
import com.signify.hue.flutterreactiveble.utils.toBleState
import io.reactivex.Completable
import io.reactivex.Observable
import io.reactivex.Single
import io.reactivex.disposables.CompositeDisposable
import io.reactivex.subjects.BehaviorSubject
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.collections.component1
import kotlin.collections.component2

private val EVT_FILE_TRANSFER_CHARACTERISTIC_UUID: UUID =
    UUID.fromString("0000ff13-1212-efde-1523-785feabcd123")
private val DVT_AUDIO_STREAM_CHARACTERISTIC_UUID: UUID =
    UUID.fromString("0000fa18-1212-efde-1523-785feabcd123")
private val DVT_ARCHIVE_CHARACTERISTIC_UUID: UUID =
    UUID.fromString("0000ff16-1212-efde-1523-785feabcd123")
private val DVT_WQOTA_SERVICE_UUID: UUID =
    UUID.fromString("00007033-0000-1000-8000-00805f9b34fb")
private val DVT_WQOTA_RESPONSE_CHARACTERISTIC_UUID: UUID =
    UUID.fromString("00002002-0000-1000-8000-00805f9b34fb")
private const val hexadecimalRadix = 16

@VisibleForTesting
internal enum class EvtNotificationMode {
    INDICATE,
    NOTIFY,
}

private val EVT_INDICATE_CHARACTERISTIC_UUIDS =
    setOf(
        UUID.fromString("0000fa11-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000fa12-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000fa15-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000fa16-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000fa17-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000fa19-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000fb11-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000ff11-1212-efde-1523-785feabcd123"),
        UUID.fromString("0000ff12-1212-efde-1523-785feabcd123"),
        DVT_ARCHIVE_CHARACTERISTIC_UUID,
    )

private val EVT_NOTIFY_CHARACTERISTIC_UUIDS =
    setOf(
        EVT_FILE_TRANSFER_CHARACTERISTIC_UUID,
        DVT_AUDIO_STREAM_CHARACTERISTIC_UUID,
    )

/**
 * EVT V1.6 response channels must use a real Client Characteristic
 * Configuration Descriptor. `NotificationSetupMode.COMPAT` only enables the
 * local Android callback; it deliberately skips the remote CCCD write and is
 * therefore invalid for a peripheral that sends Notify or Indicate packets.
 */
private val EVT_CCCD_REQUIRED_CHARACTERISTIC_UUIDS =
    EVT_INDICATE_CHARACTERISTIC_UUIDS + EVT_NOTIFY_CHARACTERISTIC_UUIDS

private val CLIENT_CHARACTERISTIC_CONFIGURATION_UUID: UUID =
    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

@VisibleForTesting
internal fun requiresEvtCccd(
    characteristicId: UUID,
    serviceId: UUID? = null,
): Boolean =
    characteristicId in EVT_CCCD_REQUIRED_CHARACTERISTIC_UUIDS ||
        isDvtWqotaResponseCharacteristic(characteristicId, serviceId)

@VisibleForTesting
internal fun evtNotificationModeFor(
    characteristicId: UUID,
    serviceId: UUID? = null,
): EvtNotificationMode? {
    if (isDvtWqotaResponseCharacteristic(characteristicId, serviceId)) {
        return EvtNotificationMode.NOTIFY
    }
    return when (characteristicId) {
        in EVT_NOTIFY_CHARACTERISTIC_UUIDS -> EvtNotificationMode.NOTIFY
        in EVT_INDICATE_CHARACTERISTIC_UUIDS -> EvtNotificationMode.INDICATE
        else -> null
    }
}

/**
 * The WQOTA UUID is a Bluetooth SIG 16-bit UUID. Scope the DVT mapping to
 * service 0x7033 so an unrelated peripheral's 0x2002 characteristic retains
 * the plugin's normal property-driven subscription behavior.
 */
private fun isDvtWqotaResponseCharacteristic(
    characteristicId: UUID,
    serviceId: UUID?,
): Boolean =
    characteristicId == DVT_WQOTA_RESPONSE_CHARACTERISTIC_UUID &&
        serviceId == DVT_WQOTA_SERVICE_UUID

/**
 * EVT channels have a protocol-defined CCC value. Do not use a characteristic
 * that merely has another response capability: that would acknowledge a
 * subscription while configuring the wrong CCCD value on the peripheral.
 */
@VisibleForTesting
internal fun requireEvtNotificationMode(
    characteristicId: UUID,
    properties: Int,
    serviceId: UUID? = null,
): EvtNotificationMode? {
    val expectedMode = evtNotificationModeFor(characteristicId, serviceId) ?: return null
    val requiredProperty =
        if (expectedMode == EvtNotificationMode.INDICATE) {
            BluetoothGattCharacteristic.PROPERTY_INDICATE
        } else {
            BluetoothGattCharacteristic.PROPERTY_NOTIFY
        }
    if ((properties and requiredProperty) == 0) {
        val expectedName = expectedMode.name.lowercase()
        throw IllegalStateException(
            "EVT 特征 $characteristicId 必须提供 $expectedName 属性，" +
                "当前 properties=0x${properties.toString(hexadecimalRadix)}。",
        )
    }
    return expectedMode
}

/**
 * EVT response characteristics use protocol-defined response modes. Generic
 * plugin callers keep the historical property-driven behavior.
 */
@VisibleForTesting
internal fun shouldPreferIndication(
    characteristicId: UUID,
    properties: Int,
    serviceId: UUID? = null,
): Boolean =
    when (evtNotificationModeFor(characteristicId, serviceId)) {
        EvtNotificationMode.INDICATE -> true
        EvtNotificationMode.NOTIFY -> false
        null -> (properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
    }

@VisibleForTesting
internal fun notificationSetupModeFor(
    characteristicId: UUID,
    descriptorUuids: Collection<UUID>,
    serviceId: UUID? = null,
): NotificationSetupMode =
    if (requiresEvtCccd(characteristicId, serviceId)) {
        NotificationSetupMode.DEFAULT
    } else if (descriptorUuids.isEmpty()) {
        NotificationSetupMode.COMPAT
    } else {
        NotificationSetupMode.DEFAULT
    }

@Suppress("TooManyFunctions")
open class ReactiveBleClient(private val context: Context) : BleClient {
    private val connectionQueue = ConnectionQueue()
    private val allConnections = CompositeDisposable()

    companion object {
        // this needs to be in companion update since background isolates respawn the event channels
        // Fix for https://github.com/PhilipsHue/flutter_reactive_ble/issues/277
        private val connectionUpdateBehaviorSubject: BehaviorSubject<ConnectionUpdate> =
            BehaviorSubject.create()

        lateinit var rxBleClient: RxBleClient
            internal set
        internal var activeConnections = mutableMapOf<String, DeviceConnector>()
    }

    override val connectionUpdateSubject: BehaviorSubject<ConnectionUpdate>
        get() = connectionUpdateBehaviorSubject

    override fun initializeClient() {
        activeConnections = mutableMapOf()
        rxBleClient = RxBleClient.create(context)
    }

    /*yes spread operator is not performant but after kotlin v1.60 it is less bad and it is also the
    recommended way to call varargs in java https://kotlinlang.org/docs/reference/java-interop.html#java-varargs
     */
    @Suppress("SpreadOperator")
    override fun scanForDevices(
        services: List<ParcelUuid>,
        scanMode: ScanMode,
        requireLocationServicesEnabled: Boolean,
    ): Observable<ScanInfo> {
        val filters =
            services.map { service ->
                ScanFilter.Builder()
                    .setServiceUuid(service)
                    .build()
            }.toTypedArray()

        val scanSettings =
            ScanSettings.Builder()
                .setScanMode(scanMode.toScanSettings())
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .setShouldCheckLocationServicesState(requireLocationServicesEnabled)
                .apply {
                    // EVT V1.6 uses a legacy primary advertisement plus scan
                    // response. Restricting Android to extended advertisements
                    // makes the device undiscoverable on API 26 and newer.
                    // Android only added this setting on API 26; pre-O already
                    // scans legacy advertisements and must not call the method.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setLegacy(true)
                    }
                }
                .build()

        return rxBleClient.scanBleDevices(
            scanSettings,
            *filters,
        )
            .map { result ->
                ScanInfo(
                    result.bleDevice.macAddress,
                    result.scanRecord.deviceName
                        ?: result.bleDevice.name ?: "",
                    result.rssi,
                    when (result.isConnectable) {
                        null -> Connectable.UNKNOWN
                        IsConnectable.LEGACY_UNKNOWN -> Connectable.UNKNOWN
                        IsConnectable.NOT_CONNECTABLE -> Connectable.NOT_CONNECTABLE
                        IsConnectable.CONNECTABLE -> Connectable.CONNECTABLE
                    },
                    result.scanRecord.serviceData?.mapKeys { it.key.uuid } ?: emptyMap(),
                    result.scanRecord.serviceUuids?.map { it.uuid } ?: emptyList(),
                    extractManufacturerData(result.scanRecord.manufacturerSpecificData),
                )
            }
    }

    override fun connectToDevice(
        deviceId: String,
        timeout: Duration,
    ) {
        allConnections.add(
            getConnection(deviceId, timeout)
                .subscribe({ result ->
                    when (result) {
                        is EstablishedConnection -> {
                        }
                        is EstablishConnectionFailure -> {
                            connectionUpdateBehaviorSubject.onNext(
                                ConnectionUpdateError(
                                    deviceId,
                                    result.errorMessage,
                                ),
                            )
                        }
                    }
                }, { error ->
                    connectionUpdateBehaviorSubject.onNext(
                        ConnectionUpdateError(
                            deviceId,
                            error?.message
                                ?: "unknown error",
                        ),
                    )
                }),
        )
    }

    override fun disconnectDevice(deviceId: String): Completable {
        val connector = activeConnections[deviceId] ?: return Completable.complete()
        return connector.disconnectDevice(deviceId)
            .doOnComplete {
                // A later connect may have installed a new connector for the
                // same device while an earlier cleanup completed. Only remove
                // the connector this operation actually terminated.
                if (activeConnections[deviceId] === connector) {
                    activeConnections.remove(deviceId)
                }
            }
    }

    override fun disconnectAllDevices() {
        val connectors = activeConnections.toMap()
        activeConnections.clear()
        connectors.forEach { (device, connector) ->
            connector.disconnectDevice(device).subscribe()
        }
        // Keep the aggregate disposable reusable.  The plugin can be
        // deinitialized and initialized again during an app lifecycle (and
        // the EVT reconnect flow may do exactly that); disposing this
        // CompositeDisposable permanently would immediately dispose every
        // later connect subscription added to it.
        allConnections.clear()
    }

    override fun clearGattCache(deviceId: String): Completable =
        activeConnections[deviceId]?.let(DeviceConnector::clearGattCache)
            ?: Completable.error(IllegalStateException("Device is not connected"))

    override fun discoverServices(deviceId: String): Single<RxBleDeviceServices> {
        return getConnection(deviceId).flatMapSingle { connectionResult ->
            when (connectionResult) {
                is EstablishedConnection ->
                    if (rxBleClient.getBleDevice(connectionResult.deviceId).bluetoothDevice.bondState == BOND_BONDING) {
                        Single.error(
                            Exception(
                                "Bonding is in progress wait for bonding to be finished before executing more operations on the device",
                            ),
                        )
                    } else {
                        connectionResult.rxConnection.discoverServices()
                    }
                is EstablishConnectionFailure -> Single.error(Exception(connectionResult.errorMessage))
            }
        }.firstOrError()
    }

    override fun readCharacteristic(
        deviceId: String,
        characteristicId: UUID,
        characteristicInstanceId: Int,
    ): Single<CharOperationResult> =
        getConnection(deviceId).flatMapSingle { connectionResult ->
            when (connectionResult) {
                is EstablishedConnection -> {
                    connectionResult.rxConnection.resolveCharacteristic(
                        characteristicId,
                        characteristicInstanceId,
                    ).flatMap { c: BluetoothGattCharacteristic ->
                        connectionResult.rxConnection.readCharacteristic(c)
                                /*
                                On Android7 the ble stack frequently gives incorrectly
                                the error GAT_AUTH_FAIL(137) when reading char that will establish
                                the bonding with the peripheral. By retrying the operation once we
                                deviate between this flaky one time error and real auth failed cases
                                 */
                            .retry(1) { Build.VERSION.SDK_INT < Build.VERSION_CODES.O }
                            .map { value ->
                                CharOperationSuccessful(deviceId, value.asList())
                            }
                    }
                }
                is EstablishConnectionFailure ->
                    Single.just(
                        CharOperationFailed(
                            deviceId,
                            "failed to connect ${connectionResult.errorMessage}",
                        ),
                    )
            }
        }.first(CharOperationFailed(deviceId, "read char failed"))

    override fun writeCharacteristicWithResponse(
        deviceId: String,
        characteristicId: UUID,
        characteristicInstanceId: Int,
        value: ByteArray,
    ): Single<CharOperationResult> =
        executeWriteOperation(
            deviceId,
            characteristicId,
            characteristicInstanceId,
            value,
            RxBleConnection::writeCharWithResponse,
        )

    override fun writeCharacteristicWithoutResponse(
        deviceId: String,
        characteristicId: UUID,
        characteristicInstanceId: Int,
        value: ByteArray,
    ): Single<CharOperationResult> =
        executeWriteOperation(
            deviceId,
            characteristicId,
            characteristicInstanceId,
            value,
            RxBleConnection::writeCharWithoutResponse,
        )

    override fun setupNotification(
        deviceId: String,
        characteristicId: UUID,
        characteristicInstanceId: Int,
    ): Observable<Observable<ByteArray>> {
        return getConnection(deviceId)
            .flatMap { deviceConnection ->
                setupNotificationOrIndication(
                    deviceConnection,
                    characteristicId,
                    characteristicInstanceId,
                )
            }
    }

    override fun negotiateMtuSize(
        deviceId: String,
        size: Int,
    ): Single<MtuNegotiateResult> =
        getConnection(deviceId).flatMapSingle { connectionResult ->
            when (connectionResult) {
                is EstablishedConnection ->
                    connectionResult.rxConnection.requestMtu(size)
                        .map { value -> MtuNegotiateSuccessful(deviceId, value) }

                is EstablishConnectionFailure ->
                    Single.just(
                        MtuNegotiateFailed(
                            deviceId,
                            "failed to connect ${connectionResult.errorMessage}",
                        ),
                    )
            }
        }.first(MtuNegotiateFailed(deviceId, "negotiate mtu timed out"))

    override fun observeBleStatus(): Observable<BleStatus> =
        rxBleClient.observeStateChanges()
            .startWith(rxBleClient.state)
            .map { it.toBleState() }

    @VisibleForTesting
    internal open fun createDeviceConnector(
        device: RxBleDevice,
        timeout: Duration,
    ) = DeviceConnector(device, timeout, connectionUpdateBehaviorSubject::onNext, connectionQueue)

    private fun getConnection(
        deviceId: String,
        timeout: Duration = Duration(0, TimeUnit.MILLISECONDS),
    ): Observable<EstablishConnectionResult> {
        val device = rxBleClient.getBleDevice(deviceId)
        // An unexpected disconnect is converted to an
        // EstablishConnectionFailure by DeviceConnector.  That value is
        // retained by its BehaviorSubject, so reusing the connector would
        // make every later reconnect immediately fail without touching the
        // radio.  Replace only terminal connectors; an in-flight or healthy
        // connector remains shared for concurrent operations.
        val connector = synchronized(activeConnections) {
            val existing = activeConnections[deviceId]
            if (existing?.isTerminal == true) {
                activeConnections.remove(deviceId)
                existing.disposeSilently()
            }
            activeConnections.getOrPut(deviceId) {
                createDeviceConnector(device, timeout)
            }
        }

        return connector.connection
    }

    private fun executeWriteOperation(
        deviceId: String,
        characteristicId: UUID,
        characteristicInstanceId: Int,
        value: ByteArray,
        bleOperation: RxBleConnection.(characteristic: BluetoothGattCharacteristic, value: ByteArray) -> Single<ByteArray>,
    ): Single<CharOperationResult> {
        return getConnection(deviceId)
            .flatMapSingle { connectionResult ->
                when (connectionResult) {
                    is EstablishedConnection -> {
                        connectionResult.rxConnection.resolveCharacteristic(characteristicId, characteristicInstanceId)
                            .flatMap { characteristic ->
                                connectionResult.rxConnection.bleOperation(characteristic, value)
                                    .map { value -> CharOperationSuccessful(deviceId, value.asList()) }
                            }
                    }
                    is EstablishConnectionFailure -> {
                        Single.just(
                            CharOperationFailed(
                                deviceId,
                                "failed to connect ${connectionResult.errorMessage}",
                            ),
                        )
                    }
                }
            }.first(CharOperationFailed(deviceId, "Writechar timed-out"))
    }

    @Suppress("LongMethod", "CyclomaticComplexMethod")
    private fun setupNotificationOrIndication(
        deviceConnection: EstablishConnectionResult,
        characteristicId: UUID,
        characteristicInstanceId: Int,
    ): Observable<Observable<ByteArray>> =
        when (deviceConnection) {
            is EstablishedConnection -> {
                if (rxBleClient.getBleDevice(deviceConnection.deviceId).bluetoothDevice.bondState == BOND_BONDING) {
                    Observable.error(
                        Exception("Bonding is in progress wait for bonding to be finished before executing more operations on the device"),
                    )
                } else {
                    deviceConnection.rxConnection.resolveCharacteristic(
                        characteristicId,
                        characteristicInstanceId,
                    ).flatMapObservable { characteristic ->
                        val serviceId = characteristic.service?.uuid
                        val descriptorUuids = characteristic.descriptors.map { it.uuid }
                        val cccdPresent =
                            descriptorUuids.any { it == CLIENT_CHARACTERISTIC_CONFIGURATION_UUID }
                        val requiresCccd = requiresEvtCccd(characteristic.uuid, serviceId)
                        val mode = notificationSetupModeFor(
                            characteristic.uuid,
                            descriptorUuids,
                            serviceId,
                        )
                        val expectedEvtMode = try {
                            requireEvtNotificationMode(
                                characteristic.uuid,
                                characteristic.properties,
                                serviceId,
                            )
                        } catch (error: IllegalStateException) {
                            NativeBleLog.error(
                                event = "ccc_configuration_rejected",
                                message = "【AIPIN原生BLE】【CCC配置失败】EVT 特征属性与协议模式不一致",
                                fields = mapOf(
                                    "device_id" to deviceConnection.deviceId,
                                    "characteristic_uuid" to characteristic.uuid.toString(),
                                    "properties_hex" to "0x${characteristic.properties.toString(hexadecimalRadix)}",
                                    "error" to (error.message ?: "unknown"),
                                ),
                            )
                            return@flatMapObservable Observable.error(error)
                        }
                        val indication = expectedEvtMode == EvtNotificationMode.INDICATE ||
                            (expectedEvtMode == null && shouldPreferIndication(
                                characteristic.uuid,
                                characteristic.properties,
                                serviceId,
                            ))
                        NativeBleLog.debug(
                            event = "ccc_configuration_requested",
                            message = "【AIPIN原生BLE】【CCC配置】准备订阅设备响应特征",
                            fields = mapOf(
                                "device_id" to deviceConnection.deviceId,
                                "service_uuid" to serviceId?.toString(),
                                "characteristic_uuid" to characteristic.uuid.toString(),
                                "properties_hex" to "0x${characteristic.properties.toString(hexadecimalRadix)}",
                                "response_mode" to if (indication) "indicate" else "notify",
                                "expected_evt_mode" to expectedEvtMode?.name?.lowercase(),
                                "setup_mode" to mode.name,
                                "cccd_required" to requiresCccd,
                                "cccd_present" to cccdPresent,
                                "descriptors" to descriptorUuids.joinToString(prefix = "[", postfix = "]"),
                            ),
                        )
                        if (requiresCccd && !cccdPresent) {
                            val error = IllegalStateException(
                                "EVT 特征 ${characteristic.uuid} 缺少 CCCD " +
                                "(0x2902)，已拒绝使用 COMPAT 模式。请检查设备 GATT 表或清除 Android GATT 缓存后重连。",
                            )
                            NativeBleLog.error(
                                event = "ccc_configuration_rejected",
                                message = "【AIPIN原生BLE】【CCC配置失败】EVT 特征缺少 CCCD",
                                fields = mapOf(
                                    "device_id" to deviceConnection.deviceId,
                                    "service_uuid" to serviceId?.toString(),
                                    "characteristic_uuid" to characteristic.uuid.toString(),
                                    "error" to (error.message ?: "unknown"),
                                ),
                            )
                            return@flatMapObservable Observable.error(error)
                        }

                        val notification = if (indication) {
                            deviceConnection.rxConnection.setupIndication(
                                characteristic,
                                mode,
                            )
                        } else {
                            deviceConnection.rxConnection.setupNotification(
                                characteristic,
                                mode,
                            )
                        }
                        notification
                            .doOnNext {
                                NativeBleLog.debug(
                                    event = "ccc_configuration_completed",
                                    message = "【AIPIN原生BLE】【CCC配置完成】系统已完成 EVT 响应特征订阅",
                                    fields = mapOf(
                                        "device_id" to deviceConnection.deviceId,
                                        "service_uuid" to serviceId?.toString(),
                                        "characteristic_uuid" to characteristic.uuid.toString(),
                                        "response_mode" to if (indication) "indicate" else "notify",
                                        "expected_evt_mode" to expectedEvtMode?.name?.lowercase(),
                                        "setup_mode" to mode.name,
                                        "cccd_present" to cccdPresent,
                                    ),
                                )
                            }
                            .doOnError { error ->
                                NativeBleLog.error(
                                    event = "ccc_configuration_failed",
                                    message = "【AIPIN原生BLE】【CCC配置异常】系统未能完成响应特征订阅",
                                    fields = mapOf(
                                        "device_id" to deviceConnection.deviceId,
                                        "service_uuid" to serviceId?.toString(),
                                        "characteristic_uuid" to characteristic.uuid.toString(),
                                        "setup_mode" to mode.name,
                                        "error_type" to error.javaClass.simpleName,
                                        "error" to (error.message ?: "unknown"),
                                    ),
                                )
                            }
                    }
                }
            }
            is EstablishConnectionFailure -> {
                Observable.error(
                    Exception("failed to connect ${deviceConnection.errorMessage}"),
                )
            }
        }

    override fun requestConnectionPriority(
        deviceId: String,
        priority: ConnectionPriority,
    ): Single<RequestConnectionPriorityResult> =
        getConnection(deviceId).switchMapSingle { connectionResult ->
            when (connectionResult) {
                is EstablishedConnection ->
                    connectionResult.rxConnection.requestConnectionPriority(
                        priority.code,
                        2,
                        TimeUnit.SECONDS,
                    )
                        .toSingle {
                            RequestConnectionPrioritySuccess(deviceId)
                        }
                is EstablishConnectionFailure ->
                    Single.fromCallable {
                        RequestConnectionPriorityFailed(deviceId, connectionResult.errorMessage)
                    }
            }
        }.first(RequestConnectionPriorityFailed(deviceId, "Unknown failure"))

    override fun readRssi(deviceId: String): Single<Int> =
        getConnection(deviceId).flatMapSingle { connectionResult ->
            when (connectionResult) {
                is EstablishedConnection -> {
                    connectionResult.rxConnection.readRssi()
                }
                is EstablishConnectionFailure ->
                    Single.error(
                        java.lang.IllegalStateException(
                            "Reading RSSI failed. Device is not connected",
                        ),
                    )
            }
        }.firstOrError()

    // enable this for extra debug output on the android stack
    private fun enableDebugLogging() =
        RxBleClient
            .updateLogOptions(
                LogOptions.Builder().setLogLevel(LogConstants.VERBOSE)
                    .setMacAddressLogSetting(LogConstants.MAC_ADDRESS_FULL)
                    .setUuidsLogSetting(LogConstants.UUIDS_FULL)
                    .setShouldLogAttributeValues(true)
                    .build(),
            )
}
