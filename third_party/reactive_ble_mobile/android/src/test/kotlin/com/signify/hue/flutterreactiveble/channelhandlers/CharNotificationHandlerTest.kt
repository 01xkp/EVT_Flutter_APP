package com.signify.hue.flutterreactiveble.channelhandlers

import com.google.common.truth.Truth.assertThat
import com.google.protobuf.ByteString
import com.signify.hue.flutterreactiveble.ble.BleClient
import com.signify.hue.flutterreactiveble.converters.UuidConverter
import io.mockk.every
import io.mockk.mockk
import io.reactivex.Observable
import io.reactivex.android.plugins.RxAndroidPlugins
import io.reactivex.schedulers.Schedulers
import io.reactivex.subjects.PublishSubject
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.util.UUID
import com.signify.hue.flutterreactiveble.ProtobufModel as pb

class CharNotificationHandlerTest {
    private val deviceId = "test-device"
    private val characteristicUuid = UUID.fromString("0000fa19-0000-1000-8000-00805f9b34fb")

    private lateinit var setupResponses: PublishSubject<Observable<ByteArray>>
    private lateinit var handler: CharNotificationHandler

    @BeforeEach
    fun setUp() {
        RxAndroidPlugins.setInitMainThreadSchedulerHandler { Schedulers.trampoline() }
        RxAndroidPlugins.setMainThreadSchedulerHandler { Schedulers.trampoline() }
        setupResponses = PublishSubject.create()
        val bleClient = mockk<BleClient>()
        every {
            bleClient.setupNotification(deviceId, characteristicUuid, 0)
        }.returns(setupResponses)
        handler = CharNotificationHandler(bleClient)
    }

    @AfterEach
    fun tearDown() {
        handler.onCancel(null)
        RxAndroidPlugins.reset()
    }

    @Test
    fun `wait registered before subscription completes after CCC setup`() {
        var waitCompleted = 0
        handler.awaitNotificationSetup(
            deviceId = deviceId,
            characteristicUuid = characteristicUuid,
            onSetupCompleted = { waitCompleted += 1 },
            onSetupFailed = { throw AssertionError(it) },
        )

        var subscriptionCompleted = 0
        handler.subscribeToNotifications(
            request(),
            onSetupCompleted = { subscriptionCompleted += 1 },
            onSetupFailed = { throw AssertionError(it) },
        )
        assertThat(waitCompleted).isEqualTo(0)
        assertThat(subscriptionCompleted).isEqualTo(0)

        setupResponses.onNext(PublishSubject.create())

        assertThat(waitCompleted).isEqualTo(1)
        assertThat(subscriptionCompleted).isEqualTo(1)
    }

    @Test
    fun `wait registered after CCC setup replays success`() {
        handler.subscribeToNotifications(
            request(),
            onSetupCompleted = {},
            onSetupFailed = { throw AssertionError(it) },
        )
        setupResponses.onNext(PublishSubject.create())

        var waitCompleted = 0
        handler.awaitNotificationSetup(
            deviceId = deviceId,
            characteristicUuid = characteristicUuid,
            onSetupCompleted = { waitCompleted += 1 },
            onSetupFailed = { throw AssertionError(it) },
        )

        assertThat(waitCompleted).isEqualTo(1)
    }

    @Test
    fun `setup failure is reported to both subscription and waiter`() {
        var waiterError: Throwable? = null
        var subscriptionError: Throwable? = null
        handler.awaitNotificationSetup(
            deviceId = deviceId,
            characteristicUuid = characteristicUuid,
            onSetupCompleted = { throw AssertionError("Expected setup failure") },
            onSetupFailed = { waiterError = it },
        )
        handler.subscribeToNotifications(
            request(),
            onSetupCompleted = { throw AssertionError("Expected setup failure") },
            onSetupFailed = { subscriptionError = it },
        )

        val failure = IllegalStateException("CCC write failed")
        setupResponses.onError(failure)

        assertThat(waiterError).isSameInstanceAs(failure)
        assertThat(subscriptionError).isSameInstanceAs(failure)
    }

    @Test
    fun `replacing a pending subscription fails the old wait and retains the new one`() {
        var replacedWaitError: Throwable? = null
        handler.awaitNotificationSetup(
            deviceId = deviceId,
            characteristicUuid = characteristicUuid,
            onSetupCompleted = { throw AssertionError("Expected replacement failure") },
            onSetupFailed = { replacedWaitError = it },
        )
        handler.subscribeToNotifications(
            request(),
            onSetupCompleted = {},
            onSetupFailed = { throw AssertionError(it) },
        )
        handler.subscribeToNotifications(
            request(),
            onSetupCompleted = {},
            onSetupFailed = { throw AssertionError(it) },
        )

        assertThat(replacedWaitError?.message)
            .isEqualTo("Characteristic notification setup was replaced.")

        var newWaitCompleted = 0
        handler.awaitNotificationSetup(
            deviceId = deviceId,
            characteristicUuid = characteristicUuid,
            onSetupCompleted = { newWaitCompleted += 1 },
            onSetupFailed = { throw AssertionError(it) },
        )
        setupResponses.onNext(PublishSubject.create())

        assertThat(newWaitCompleted).isEqualTo(1)
    }

    private fun request(): pb.NotifyCharacteristicRequest =
        pb.NotifyCharacteristicRequest
            .newBuilder()
            .setCharacteristic(
                pb.CharacteristicAddress
                    .newBuilder()
                    .setDeviceId(deviceId)
                    .setCharacteristicInstanceId("0")
                    .setCharacteristicUuid(
                        pb.Uuid
                            .newBuilder()
                            .setData(
                                ByteString.copyFrom(
                                    UuidConverter().byteArrayFromUuid(characteristicUuid),
                                ),
                            )
                            .build(),
                    )
                    .build(),
            )
            .build()
}
