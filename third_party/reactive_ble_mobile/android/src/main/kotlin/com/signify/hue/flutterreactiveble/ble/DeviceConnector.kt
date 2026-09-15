package com.signify.hue.flutterreactiveble.ble

import androidx.annotation.VisibleForTesting
import com.polidea.rxandroidble2.RxBleConnection
import com.polidea.rxandroidble2.RxBleCustomOperation
import com.polidea.rxandroidble2.RxBleDevice
import com.signify.hue.flutterreactiveble.model.ConnectionState
import com.signify.hue.flutterreactiveble.model.toConnectionState
import com.signify.hue.flutterreactiveble.utils.Duration
import io.reactivex.Completable
import io.reactivex.Observable
import io.reactivex.Single
import io.reactivex.disposables.Disposable
import io.reactivex.functions.Function
import io.reactivex.subjects.BehaviorSubject
import java.util.concurrent.TimeUnit

internal class DeviceConnector(
    private val device: RxBleDevice,
    private val connectionTimeout: Duration,
    private val updateListeners: (update: ConnectionUpdate) -> Unit,
    private val connectionQueue: ConnectionQueue,
) {
    companion object {
        private const val minTimeMsBeforeDisconnectingIsAllowed = 200L
        private const val delayMsAfterClearingCache = 300L
    }

    private val connectDeviceSubject = BehaviorSubject.create<EstablishConnectionResult>()

    private var timestampEstablishConnection: Long = 0

    @VisibleForTesting
    internal var connectionDisposable: Disposable? = null

    /**
     * A connector owns one RxAndroidBle establishConnection subscription.  A
     * terminal connection failure cannot be restarted through that same
     * BehaviorSubject, so the client must discard this connector before the
     * next reconnect attempt.
     */
    @Volatile
    internal var isTerminal: Boolean = false
        private set

    // The Dart connection stream can be cancelled more than once while its
    // owner is tearing down. All callers must observe one physical disconnect
    // and one terminal update rather than scheduling duplicate delayed work.
    private var disconnectCompletion: Completable? = null

    // A terminal connector may be replaced by ReactiveBleClient before a
    // caller explicitly requests disconnect. Keep that replacement silent:
    // the old connector must release its GATT subscription without emitting a
    // late disconnected event for the newly-created connector.
    @Volatile
    private var silentlyDisposed = false

    private var subscriptionsDisposed = false

    private val lazyConnection =
        lazy {
            connectionDisposable = establishConnection(device)
            connectDeviceSubject
        }

    private val currentConnection: EstablishConnectionResult?
        get() = if (lazyConnection.isInitialized()) connection.value else null

    internal val connection by lazyConnection

    private var connectionStatusUpdates: Disposable? = null

    internal fun disconnectDevice(deviceId: String): Completable = synchronized(this) {
        disconnectCompletion ?: createDisconnectCompletion(deviceId)
            .cache()
            .also { disconnectCompletion = it }
    }

    private fun createDisconnectCompletion(deviceId: String): Completable {
        val diff = System.currentTimeMillis() - timestampEstablishConnection

        /*
        in order to prevent Android from ignoring disconnects we add a delay when we try to
        disconnect to quickly after establishing connection. https://issuetracker.google.com/issues/37121223
         */
        val delay =
            (DeviceConnector.Companion.minTimeMsBeforeDisconnectingIsAllowed - diff)
                .coerceAtLeast(0L)
        return Completable.timer(delay, TimeUnit.MILLISECONDS)
            .doOnComplete {
                if (!silentlyDisposed) {
                    sendDisconnectedUpdate(deviceId)
                }
                disposeSubscriptions()
            }
    }

    private fun sendDisconnectedUpdate(deviceId: String) {
        updateListeners(ConnectionUpdateSuccess(deviceId, ConnectionState.DISCONNECTED.code))
    }

    /**
     * Releases all native subscriptions without publishing a disconnect
     * update. Used only when a terminal connector is replaced by a fresh
     * reconnect attempt.
     */
    internal fun disposeSilently() = synchronized(this) {
        silentlyDisposed = true
        disposeSubscriptions()
    }

    private fun disposeSubscriptions() {
        synchronized(this) {
            if (subscriptionsDisposed) {
                return@synchronized
            }
            subscriptionsDisposed = true
            connectionDisposable?.dispose()
            connectDeviceSubject.onComplete()
            connectionStatusUpdates?.dispose()
            connectionStatusUpdates = null
        }
    }

    private fun ensureConnectionStatusUpdates() {
        synchronized(this) {
            if (subscriptionsDisposed || connectionStatusUpdates != null) {
                return@synchronized
            }
            connectionStatusUpdates =
                device.observeConnectionStateChanges()
                    .startWith(device.connectionState)
                    .map<ConnectionUpdate> { ConnectionUpdateSuccess(device.macAddress, it.toConnectionState().code) }
                    .onErrorReturn {
                        ConnectionUpdateError(
                            device.macAddress,
                            it.message
                                ?: "Unknown error",
                        )
                    }
                    .subscribe {
                        updateListeners.invoke(it)
                    }
        }
    }

    private fun establishConnection(rxBleDevice: RxBleDevice): Disposable {
        val deviceId = rxBleDevice.macAddress

        val shouldNotTimeout = connectionTimeout.value <= 0L
        connectionQueue.addToQueue(deviceId)
        updateListeners(ConnectionUpdateSuccess(deviceId, ConnectionState.CONNECTING.code))

        return waitUntilFirstOfQueue(deviceId)
            .switchMap { queue ->
                if (!queue.contains(deviceId)) {
                    Observable.just(
                        EstablishConnectionFailure(
                            deviceId,
                            "Device is not in queue",
                        ),
                    )
                } else {
                    connectDevice(rxBleDevice, shouldNotTimeout)
                        .map<EstablishConnectionResult> { EstablishedConnection(rxBleDevice.macAddress, it) }
                }
            }
            .onErrorReturn { error ->
                EstablishConnectionFailure(
                    rxBleDevice.macAddress,
                    error.message ?: "Unknown error",
                )
            }
            .doOnNext {
                // Trigger side effect by calling the lazy initialization of this property so
                // listening to changes starts.
                ensureConnectionStatusUpdates()
                timestampEstablishConnection = System.currentTimeMillis()
                connectionQueue.removeFromQueue(deviceId)
                if (it is EstablishConnectionFailure) {
                    // `onErrorReturn` turns a transport disconnect into a
                    // terminal failure value.  Keep the connector marked so
                    // ReactiveBleClient can create a fresh GATT session
                    // instead of replaying this stale value on reconnect.
                    isTerminal = true
                    updateListeners.invoke(ConnectionUpdateError(deviceId, it.errorMessage))
                }
            }
            .doOnError {
                isTerminal = true
                connectionQueue.removeFromQueue(deviceId)
                updateListeners.invoke(
                    ConnectionUpdateError(
                        deviceId,
                        it.message
                            ?: "Unknown error",
                    ),
                )
            }
            .subscribe(
                { connectDeviceSubject.onNext(it) },
                { throwable -> connectDeviceSubject.onError(throwable) },
            )
    }

    private fun connectDevice(
        rxBleDevice: RxBleDevice,
        shouldNotTimeout: Boolean,
    ): Observable<RxBleConnection> =
        rxBleDevice.establishConnection(shouldNotTimeout)
            .compose {
                if (shouldNotTimeout) {
                    it
                } else {
                    it.timeout(
                        Observable.timer(connectionTimeout.value, connectionTimeout.unit),
                        Function<RxBleConnection, Observable<Unit>> {
                            Observable.never<Unit>()
                        },
                    )
                }
            }

    internal fun clearGattCache(): Completable =
        currentConnection?.let { connection ->
            when (connection) {
                is EstablishedConnection -> clearGattCache(connection.rxConnection)
                is EstablishConnectionFailure -> Completable.error(Throwable(connection.errorMessage))
            }
        } ?: Completable.error(IllegalStateException("Connection is not established"))

    /**
     * Clear GATT attribute cache using an undocumented method `BluetoothGatt.refresh()`.
     *
     * May trigger the following warning in the system message log:
     *
     * https://android.googlesource.com/platform/frameworks/base/+/pie-release/config/hiddenapi-light-greylist.txt
     *
     *     Accessing hidden method Landroid/bluetooth/BluetoothGatt;->refresh()Z (light greylist, reflection)
     *
     * Known to work up to Android Q beta 2.
     */
    private fun clearGattCache(connection: RxBleConnection): Completable {
        val operation =
            RxBleCustomOperation<Unit> { bluetoothGatt, _, _ ->
                try {
                    val refreshMethod = bluetoothGatt.javaClass.getMethod("refresh")
                    val success = refreshMethod.invoke(bluetoothGatt) as Boolean
                    if (success) {
                        Observable.empty<Unit>()
                            .delay(DeviceConnector.Companion.delayMsAfterClearingCache, TimeUnit.MILLISECONDS)
                    } else {
                        val reason = "BluetoothGatt.refresh() returned false"
                        Observable.error(RuntimeException(reason))
                    }
                } catch (e: ReflectiveOperationException) {
                    Observable.error<Unit>(e)
                }
            }
        return connection.queue(operation).ignoreElements()
    }

    private fun waitUntilFirstOfQueue(deviceId: String) =
        connectionQueue.observeQueue()
            .filter { queue ->
                queue.firstOrNull() == deviceId || !queue.contains(deviceId)
            }
            .takeUntil { it.isEmpty() || it.first() == deviceId }

    /**
     * Reads the current RSSI value of the device
     */
    internal fun readRssi(): Single<Int> =
        currentConnection?.let { connection ->
            when (connection) {
                is EstablishedConnection -> connection.rxConnection.readRssi()
                is EstablishConnectionFailure -> Single.error(Throwable(connection.errorMessage))
            }
        } ?: Single.error(IllegalStateException("Connection is not established"))
}
