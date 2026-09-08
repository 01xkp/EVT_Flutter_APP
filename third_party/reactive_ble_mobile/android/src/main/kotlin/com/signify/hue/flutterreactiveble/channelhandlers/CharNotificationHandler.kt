package com.signify.hue.flutterreactiveble.channelhandlers

import com.polidea.rxandroidble2.exceptions.BleDisconnectedException
import com.signify.hue.flutterreactiveble.converters.ProtobufMessageConverter
import com.signify.hue.flutterreactiveble.converters.UuidConverter
import io.flutter.plugin.common.EventChannel
import io.reactivex.android.schedulers.AndroidSchedulers
import io.reactivex.disposables.CompositeDisposable
import io.reactivex.subjects.CompletableSubject
import java.util.UUID
import com.signify.hue.flutterreactiveble.ProtobufModel as pb

@Suppress("LongMethod", "TooManyFunctions")
class CharNotificationHandler(private val bleClient: com.signify.hue.flutterreactiveble.ble.BleClient) :
    EventChannel.StreamHandler {
    private val uuidConverter = UuidConverter()
    private val protobufConverter = ProtobufMessageConverter()

    companion object {
        private var charNotificationSink: EventChannel.EventSink? = null

        private val subscriptionMap = mutableMapOf<pb.CharacteristicAddress, CompositeDisposable>()
        private val notificationSetupResults =
            mutableMapOf<NotificationSetupKey, CompletableSubject>()
    }

    override fun onListen(
        objectSink: Any?,
        eventSink: EventChannel.EventSink?,
    ) {
        eventSink?.let {
            charNotificationSink = eventSink
        }
    }

    override fun onCancel(objectSink: Any?) {
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
        val setupKey = NotificationSetupKey(
            deviceId = request.characteristic.deviceId,
            characteristicUuid = charUuid,
        )
        val setupResult = setupResultForSubscription(
            setupKey,
            hasPreviousSubscription = previous != null,
        )
        val subscriptions = CompositeDisposable()
        subscriptionMap[request.characteristic] = subscriptions
        var setupCompleted = false
        val setupSubscription =
            bleClient.setupNotification(
                request.characteristic.deviceId,
                charUuid,
                request.characteristic.characteristicInstanceId.toInt(),
            )
                .take(1)
                .observeOn(AndroidSchedulers.mainThread())
                .subscribe({ notificationValues ->
                    if (subscriptions.isDisposed ||
                        subscriptionMap[request.characteristic] !== subscriptions
                    ) {
                        return@subscribe
                    }
                    setupCompleted = true
                    val valueSubscription = notificationValues
                        .observeOn(AndroidSchedulers.mainThread())
                        .subscribe({ value ->
                            if (!subscriptions.isDisposed &&
                                subscriptionMap[request.characteristic] === subscriptions
                            ) {
                                handleNotificationValue(request.characteristic, value)
                            }
                        }, { error ->
                            removeSubscriptionIfCurrent(
                                request.characteristic,
                                subscriptions,
                            )
                            removeSetupResultIfCurrent(setupKey, setupResult)
                            if (error !is BleDisconnectedException) {
                                handleNotificationError(request.characteristic, error)
                            }
                        })
                    subscriptions.add(valueSubscription)
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
                    if (subscriptionMap[request.characteristic] !== subscriptions) {
                        return@subscribe
                    }
                    removeSubscriptionIfCurrent(request.characteristic, subscriptions)
                    if (setupCompleted) {
                        removeSetupResultIfCurrent(setupKey, setupResult)
                        handleNotificationError(request.characteristic, error)
                    } else {
                        setupResult.onError(error)
                        onSetupFailed(error)
                    }
                })
        subscriptions.add(setupSubscription)
    }

    fun unsubscribeFromNotifications(request: pb.NotifyNoMoreCharacteristicRequest) {
        subscriptionMap.remove(request.characteristic)?.dispose()
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
        charNotificationSink = null
        subscriptionMap.forEach { it.value.dispose() }
        subscriptionMap.clear()
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
        charNotificationSink?.success(convertedMsg.toByteArray())
    }

    private fun handleNotificationError(
        subscriptionRequest: pb.CharacteristicAddress,
        error: Throwable,
    ) {
        val convertedMsg =
            protobufConverter.convertCharacteristicError(subscriptionRequest, error.message ?: "")
        charNotificationSink?.success(convertedMsg.toByteArray())
    }

    private data class NotificationSetupKey(
        val deviceId: String,
        val characteristicUuid: UUID,
    )
}
