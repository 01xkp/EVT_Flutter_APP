package com.signify.hue.flutterreactiveble.channelhandlers

import com.signify.hue.flutterreactiveble.converters.ProtobufMessageConverter
import com.signify.hue.flutterreactiveble.converters.UuidConverter
import com.signify.hue.flutterreactiveble.utils.NativeBleLog
import io.flutter.plugin.common.EventChannel
import io.reactivex.android.schedulers.AndroidSchedulers
import io.reactivex.disposables.CompositeDisposable
import io.reactivex.subjects.CompletableSubject
import java.util.Locale
import java.util.UUID
import com.signify.hue.flutterreactiveble.ProtobufModel as pb

@Suppress("LongMethod", "TooManyFunctions")
class CharNotificationHandler(private val bleClient: com.signify.hue.flutterreactiveble.ble.BleClient) :
    EventChannel.StreamHandler {
    private val uuidConverter = UuidConverter()
    private val protobufConverter = ProtobufMessageConverter()

    companion object {
        private val evtFileTransferCharacteristicUuid =
            UUID.fromString("0000ff13-1212-efde-1523-785feabcd123")
        private const val fileTransferLogSampleInterval = 100
        private const val fileTransferInitialPacketLogCount = 3
        private const val hexByteFormat = "%02X"

        private var charNotificationSink: EventChannel.EventSink? = null

        private val subscriptionMap = mutableMapOf<pb.CharacteristicAddress, CompositeDisposable>()
        private val notificationSetupResults =
            mutableMapOf<NotificationSetupKey, CompletableSubject>()
        private val fileTransferPacketCounts = mutableMapOf<pb.CharacteristicAddress, Int>()
    }

    override fun onListen(
        objectSink: Any?,
        eventSink: EventChannel.EventSink?,
    ) {
        eventSink?.let {
            charNotificationSink = eventSink
            NativeBleLog.debug(
                event = "characteristic_stream_listening",
                message = "【AIPIN原生BLE】【通知通道】Flutter 特征回包通道已建立监听",
            )
        }
    }

    override fun onCancel(objectSink: Any?) {
        NativeBleLog.warn(
            event = "characteristic_stream_cancelled",
            message = "【AIPIN原生BLE】【通知通道】Flutter 特征回包通道已取消，停止全部原生订阅",
            fields = mapOf("subscription_count" to subscriptionMap.size),
        )
        unsubscribeFromAllNotifications()
    }

    fun subscribeToNotifications(
        request: pb.NotifyCharacteristicRequest,
        onSetupCompleted: () -> Unit,
        onSetupFailed: (Throwable) -> Unit,
    ) {
        val charUuid =
            uuidConverter
                .uuidFromByteArray(request.characteristic.characteristicUuid.data.toByteArray())
        val previous = subscriptionMap.remove(request.characteristic)
        previous?.dispose()
        fileTransferPacketCounts.remove(request.characteristic)
        val setupKey = NotificationSetupKey(
            deviceId = request.characteristic.deviceId,
            characteristicUuid = charUuid,
        )
        NativeBleLog.debug(
            event = "characteristic_subscription_requested",
            message = "【AIPIN原生BLE】【通知订阅】请求订阅设备响应特征",
            fields = mapOf(
                "device_id" to request.characteristic.deviceId,
                "characteristic_uuid" to charUuid.toString(),
                "instance_id" to request.characteristic.characteristicInstanceId,
                "replacing_previous" to (previous != null),
            ),
        )
        val setupResult = setupResultForSubscription(
            setupKey,
            hasPreviousSubscription = previous != null,
        )
        val subscriptions = CompositeDisposable()
        subscriptionMap[request.characteristic] = subscriptions
        var setupCompleted = false
        val subscriptionFields = mapOf(
            "device_id" to request.characteristic.deviceId,
            "characteristic_uuid" to charUuid.toString(),
            "instance_id" to request.characteristic.characteristicInstanceId,
        )
        fun failSubscription(error: Throwable, event: String, message: String) {
            if (subscriptions.isDisposed ||
                subscriptionMap[request.characteristic] !== subscriptions
            ) {
                return
            }
            removeSubscriptionIfCurrent(request.characteristic, subscriptions)
            NativeBleLog.error(
                event = event,
                message = message,
                fields = subscriptionFields + mapOf(
                    "setup_completed" to setupCompleted,
                    "error_type" to error.javaClass.simpleName,
                    "error" to (error.message ?: "unknown"),
                ),
            )
            if (setupResult.isPending()) {
                setupResult.onError(error)
            }
            if (setupCompleted) {
                removeSetupResultIfCurrent(setupKey, setupResult)
                handleNotificationError(request.characteristic, error)
            } else {
                onSetupFailed(error)
            }
        }
        val setupSubscription =
            bleClient.setupNotification(
                request.characteristic.deviceId,
                charUuid,
                request.characteristic.characteristicInstanceId.toInt(),
            )
                // The outer RxAndroidBle observable OWNS the CCC and local
                // listener. Taking its first value tears both down immediately.
                .observeOn(AndroidSchedulers.mainThread())
                .doFinally {
                    NativeBleLog.debug(
                        event = "characteristic_subscription_released",
                        message = "【AIPIN原生BLE】【通知释放】原生监听已释放，库将清理本地注册和 CCC",
                        fields = subscriptionFields + ("setup_completed" to setupCompleted),
                    )
                }
                .subscribe({ notificationValues ->
                    if (subscriptions.isDisposed ||
                        subscriptionMap[request.characteristic] !== subscriptions
                    ) {
                        return@subscribe
                    }
                    val valueSubscription = notificationValues
                        .observeOn(AndroidSchedulers.mainThread())
                        .subscribe({ value ->
                            if (!subscriptions.isDisposed &&
                                subscriptionMap[request.characteristic] === subscriptions
                            ) {
                                handleNotificationValue(request.characteristic, value)
                            }
                        }, { error ->
                            failSubscription(
                                error = error,
                                event = "characteristic_stream_failed",
                                message = "【AIPIN原生BLE】【通知订阅异常】设备回包流异常",
                            )
                        }, {
                            failSubscription(
                                error = IllegalStateException("Characteristic value stream ended unexpectedly."),
                                event = "characteristic_stream_ended",
                                message = "【AIPIN原生BLE】【接收中断】回包监听意外结束，订阅不再就绪",
                            )
                        })
                    subscriptions.add(valueSubscription)
                    if (subscriptions.isDisposed ||
                        subscriptionMap[request.characteristic] !== subscriptions
                    ) {
                        return@subscribe
                    }
                    setupCompleted = true
                    NativeBleLog.debug(
                        event = "characteristic_subscription_ready",
                        message = "【AIPIN原生BLE】【通知订阅】CCC 和持续回包监听已就绪，保持订阅直到取消或断连",
                        fields = subscriptionFields,
                    )
                    // Complete the original subscription first. Flutter
                    // attaches its Dart characteristic-value listener from
                    // the resulting asyncExpand continuation. Scheduling the
                    // readiness completion on the next main-loop turn keeps a
                    // command from racing that listener after the CCC write.
                    onSetupCompleted()
                    AndroidSchedulers.mainThread().scheduleDirect {
                        if (!subscriptions.isDisposed &&
                            subscriptionMap[request.characteristic] === subscriptions &&
                            !setupResult.hasComplete() &&
                            !setupResult.hasThrowable()
                        ) {
                            setupResult.onComplete()
                        }
                    }
                }, { error ->
                    failSubscription(
                        error = error,
                        event = "characteristic_subscription_failed",
                        message = "【AIPIN原生BLE】【通知订阅失败】CCC 或持续监听发生异常",
                    )
                }, {
                    failSubscription(
                        error = IllegalStateException("Characteristic setup stream ended unexpectedly."),
                        event = "characteristic_subscription_ended",
                        message = "【AIPIN原生BLE】【订阅中断】外层订阅意外结束，停止等待设备回包",
                    )
                })
        subscriptions.add(setupSubscription)
    }

    fun unsubscribeFromNotifications(request: pb.NotifyNoMoreCharacteristicRequest) {
        NativeBleLog.debug(
            event = "characteristic_subscription_cancelled",
            message = "【AIPIN原生BLE】【通知订阅】取消单个特征订阅",
            fields = mapOf("device_id" to request.characteristic.deviceId),
        )
        subscriptionMap.remove(request.characteristic)?.dispose()
        fileTransferPacketCounts.remove(request.characteristic)
        cancelPendingNotificationSetup(
            NotificationSetupKey(
                deviceId = request.characteristic.deviceId,
                characteristicUuid = uuidConverter.uuidFromByteArray(
                    request.characteristic.characteristicUuid.data.toByteArray(),
                ),
            ),
        )
    }

    fun dispose() {
        unsubscribeFromAllNotifications()
    }

    /**
     * Waits for the CCC setup belonging to [deviceId] and [characteristicUuid].
     *
     * The wait can be registered before or after `readNotifications`: both
     * callers share the same replaying setup result. A caller must still set a
     * Dart-side timeout for the case where no subscription is ever requested.
     */
    fun awaitNotificationSetup(
        deviceId: String,
        characteristicUuid: UUID,
        onSetupCompleted: () -> Unit,
        onSetupFailed: (Throwable) -> Unit,
    ) {
        setupResultForWait(
            NotificationSetupKey(
                deviceId = deviceId,
                characteristicUuid = characteristicUuid,
            ),
        )
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe(onSetupCompleted, onSetupFailed)
    }

    fun addSingleReadToStream(charInfo: pb.CharacteristicValueInfo) {
        handleNotificationValue(charInfo.characteristic, charInfo.value.toByteArray())
    }

    fun addSingleErrorToStream(
        subscriptionRequest: pb.CharacteristicAddress,
        error: String,
    ) {
        val convertedMsg = protobufConverter.convertCharacteristicError(subscriptionRequest, error)
        charNotificationSink?.success(convertedMsg.toByteArray())
    }

    private fun unsubscribeFromAllNotifications() {
        NativeBleLog.debug(
            event = "characteristic_subscriptions_cancelled",
            message = "【AIPIN原生BLE】【通知订阅】取消全部特征订阅",
            fields = mapOf("subscription_count" to subscriptionMap.size),
        )
        charNotificationSink = null
        subscriptionMap.forEach { it.value.dispose() }
        subscriptionMap.clear()
        fileTransferPacketCounts.clear()
        notificationSetupResults.values.forEach { setupResult ->
            if (!setupResult.hasComplete() && !setupResult.hasThrowable()) {
                setupResult.onError(
                    IllegalStateException("Characteristic notification setup was cancelled."),
                )
            }
        }
        notificationSetupResults.clear()
    }

    /**
     * A caller can begin waiting before Dart's event stream has reached the
     * native subscription. Keep that pending result so both callers observe
     * the same CCC acknowledgement.
     */
    private fun setupResultForWait(
        key: NotificationSetupKey,
    ): CompletableSubject {
        notificationSetupResults[key]?.let { return it }
        return CompletableSubject.create().also { notificationSetupResults[key] = it }
    }

    /**
     * A new subscription replaces a previous active or terminal attempt. The
     * only pending result that is retained is one created by a caller waiting
     * before this first subscription begins.
     */
    private fun setupResultForSubscription(
        key: NotificationSetupKey,
        hasPreviousSubscription: Boolean,
    ): CompletableSubject {
        val existing = notificationSetupResults[key]
        val pendingExisting = existing?.takeIf { it.isPending() }
        if (!hasPreviousSubscription && pendingExisting != null) {
            return pendingExisting
        }
        pendingExisting?.onError(
                IllegalStateException("Characteristic notification setup was replaced."),
            )
        return CompletableSubject.create().also { notificationSetupResults[key] = it }
    }

    private fun removeSubscriptionIfCurrent(
        characteristic: pb.CharacteristicAddress,
        subscriptions: CompositeDisposable,
    ) {
        if (subscriptionMap[characteristic] === subscriptions) {
            subscriptionMap.remove(characteristic)?.dispose()
            fileTransferPacketCounts.remove(characteristic)
        }
    }

    private fun CompletableSubject?.isPending(): Boolean =
        this != null && !hasComplete() && !hasThrowable()

    private fun removeSetupResultIfCurrent(
        key: NotificationSetupKey,
        setupResult: CompletableSubject,
    ) {
        if (notificationSetupResults[key] === setupResult) {
            notificationSetupResults.remove(key)
        }
    }

    private fun cancelPendingNotificationSetup(key: NotificationSetupKey) {
        val setupResult = notificationSetupResults.remove(key) ?: return
        if (!setupResult.hasComplete() && !setupResult.hasThrowable()) {
            setupResult.onError(
                IllegalStateException("Characteristic notification setup was cancelled."),
            )
        }
    }

    private fun handleNotificationValue(
        subscriptionRequest: pb.CharacteristicAddress,
        value: ByteArray,
    ) {
        val convertedMsg = protobufConverter.convertCharacteristicInfo(subscriptionRequest, value)
        val sink = charNotificationSink
        if (sink == null) {
            logReceivedPacket(
                subscriptionRequest = subscriptionRequest,
                value = value,
                droppedByFlutter = true,
            )
            return
        }
        logReceivedPacket(
            subscriptionRequest = subscriptionRequest,
            value = value,
            droppedByFlutter = false,
        )
        sink.success(convertedMsg.toByteArray())
    }

    private fun handleNotificationError(
        subscriptionRequest: pb.CharacteristicAddress,
        error: Throwable,
    ) {
        NativeBleLog.error(
            event = "characteristic_stream_error",
            message = "【AIPIN原生BLE】【回包流异常】设备回包流发生异常",
            fields = mapOf(
                "device_id" to subscriptionRequest.deviceId,
                "error_type" to error.javaClass.simpleName,
                "error" to (error.message ?: "unknown"),
            ),
        )
        val convertedMsg =
            protobufConverter.convertCharacteristicError(subscriptionRequest, error.message ?: "")
        charNotificationSink?.success(convertedMsg.toByteArray())
    }

    private fun logReceivedPacket(
        subscriptionRequest: pb.CharacteristicAddress,
        value: ByteArray,
        droppedByFlutter: Boolean,
    ) {
        val isFileTransfer = isFileTransferCharacteristic(subscriptionRequest)
        val fileTransferPacketCount =
            if (isFileTransfer) nextFileTransferPacketCount(subscriptionRequest) else null
        val event =
            if (droppedByFlutter) "characteristic_packet_dropped" else "characteristic_packet_received"
        val message =
            if (droppedByFlutter) {
                "【AIPIN原生BLE】【回包丢弃】已收到设备回包，但 Flutter 特征通道无监听"
            } else {
                "【AIPIN原生BLE】【收到设备回包】已收到设备数据，转发到 Dart"
            }
        val level = if (droppedByFlutter) NativeLogLevel.ERROR else NativeLogLevel.DEBUG
        val fields = linkedMapOf<String, Any?>(
            "device_id" to subscriptionRequest.deviceId,
            "characteristic_uuid" to uuidConverter.uuidFromByteArray(
                subscriptionRequest.characteristicUuid.data.toByteArray(),
            ).toString(),
            "instance_id" to subscriptionRequest.characteristicInstanceId,
            "bytes" to value.size,
            "file_transfer" to isFileTransfer,
        )
        if (isFileTransfer) {
            fields["packet_count"] = fileTransferPacketCount
            fields["raw_packet_hex_omitted"] = true
            if (!shouldLogFileTransferPacket(fileTransferPacketCount ?: 0)) {
                return
            }
            log(
                level = level,
                event = "ff13_packet_sampled",
                message = "【AIPIN原生BLE】【FF13文件流】收到文件分包，原始音频字节已省略",
                fields = fields,
            )
            return
        }
        log(
            level = level,
            event = event,
            message = message,
            fields = fields,
            rawPacketHex = value.toHexString(),
        )
    }

    private fun log(
        level: NativeLogLevel,
        event: String,
        message: String,
        fields: Map<String, Any?>,
        rawPacketHex: String? = null,
    ) {
        when (level) {
            NativeLogLevel.DEBUG -> NativeBleLog.debug(event, message, fields, rawPacketHex)
            NativeLogLevel.ERROR -> NativeBleLog.error(event, message, fields, rawPacketHex)
        }
    }

    private fun isFileTransferCharacteristic(
        subscriptionRequest: pb.CharacteristicAddress,
    ): Boolean =
        uuidConverter.uuidFromByteArray(
            subscriptionRequest.characteristicUuid.data.toByteArray(),
        ) == evtFileTransferCharacteristicUuid

    private fun nextFileTransferPacketCount(
        subscriptionRequest: pb.CharacteristicAddress,
    ): Int {
        val next = (fileTransferPacketCounts[subscriptionRequest] ?: 0) + 1
        fileTransferPacketCounts[subscriptionRequest] = next
        return next
    }

    private fun shouldLogFileTransferPacket(packetCount: Int): Boolean =
        packetCount <= fileTransferInitialPacketLogCount ||
            packetCount % fileTransferLogSampleInterval == 0

    private fun ByteArray.toHexString(): String =
        joinToString(separator = " ") { byte ->
            hexByteFormat.format(Locale.ROOT, byte.toInt() and 0xFF)
        }

    private enum class NativeLogLevel {
        DEBUG,
        ERROR,
    }

    private data class NotificationSetupKey(
        val deviceId: String,
        val characteristicUuid: UUID,
    )
}
