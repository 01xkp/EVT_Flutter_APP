package com.signify.hue.flutterreactiveble.channelhandlers

import com.google.common.truth.Truth.assertThat
import com.google.protobuf.ByteString
import com.signify.hue.flutterreactiveble.ble.BleClient
import com.signify.hue.flutterreactiveble.converters.UuidConverter
import com.signify.hue.flutterreactiveble.utils.NativeBleLog
import io.flutter.plugin.common.EventChannel
import io.mockk.every
import io.mockk.mockk
import io.reactivex.Observable
import io.reactivex.android.plugins.RxAndroidPlugins
import io.reactivex.schedulers.Schedulers
import io.reactivex.subjects.CompletableSubject
import io.reactivex.subjects.PublishSubject
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.util.UUID
import com.signify.hue.flutterreactiveble.ProtobufModel as pb

class CharNotificationHandlerTest {
    private val deviceId = "test-device"
    private val characteristicUuid = UUID.fromString("0000fa19-1212-efde-1523-785feabcd123")

    private lateinit var setupResponses: PublishSubject<Observable<ByteArray>>
    private lateinit var bleClient: BleClient
    private lateinit var handler: CharNotificationHandler

    @BeforeEach
    fun setUp() {
        NativeBleLog.sink = { _, _ -> }
        RxAndroidPlugins.setInitMainThreadSchedulerHandler { Schedulers.trampoline() }
        RxAndroidPlugins.setMainThreadSchedulerHandler { Schedulers.trampoline() }
        setupResponses = PublishSubject.create()
        bleClient = mockk<BleClient>()
        every {
            bleClient.setupNotification(deviceId, characteristicUuid, 0)
        }.returns(setupResponses)
        handler = CharNotificationHandler(bleClient)
    }

    @AfterEach
    fun tearDown() {
        handler.onCancel(null)
        NativeBleLog.resetForTests()
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
    fun `CCC ready keeps the owning subscription alive and forwards later indications`() {
        val packets = capturePackets()
        val values = PublishSubject.create<ByteArray>()
        val teardown = CompletableSubject.create()
        every {
            bleClient.setupNotification(deviceId, characteristicUuid, 0)
        }.returns(setupResponses.doFinally { teardown.onComplete() })
        handler.subscribeToNotifications(request(), {}, { throw AssertionError(it) })

        // RxAndroidBle terminates the value stream when its outer setup is disposed.
        setupResponses.onNext(values.takeUntil(teardown.toObservable<ByteArray>()))

        assertThat(setupResponses.hasObservers()).isTrue()
        assertThat(teardown.hasComplete()).isFalse()
        val response = byteArrayOf(0xED.toByte(), 4, 0, 0x89.toByte(), 1, 0x2E, 0xAC.toByte())
        values.onNext(response)
        values.onNext(response)
        assertThat(packets).hasSize(2)
        assertThat(packets[0].value.toByteArray()).isEqualTo(response)
        assertThat(packets[0].characteristic).isEqualTo(request().characteristic)

        handler.unsubscribeFromNotifications(
            pb.NotifyNoMoreCharacteristicRequest.newBuilder()
                .setCharacteristic(request().characteristic).build(),
        )
        assertThat(setupResponses.hasObservers()).isFalse()
        assertThat(teardown.hasComplete()).isTrue()
        assertThat(values.hasObservers()).isFalse()
        values.onNext(response)
        assertThat(packets).hasSize(2)
    }

    @Test
    fun `listener is active when CCC readiness triggers an immediate reply`() {
        val packets = capturePackets()
        val values = PublishSubject.create<ByteArray>()
        val response = byteArrayOf(0xED.toByte(), 4, 0, 0x89.toByte(), 1, 0x2E, 0xAC.toByte())
        handler.awaitNotificationSetup(
            deviceId, characteristicUuid,
            onSetupCompleted = { values.onNext(response) },
            onSetupFailed = { throw AssertionError(it) },
        )
        handler.subscribeToNotifications(request(), {}, { throw AssertionError(it) })
        setupResponses.onNext(values)

        assertThat(packets).hasSize(1)
        assertThat(packets.single().value.toByteArray()).isEqualTo(response)
    }

    @Test
    fun `outer failure after CCC readiness reaches Flutter and stops the value stream`() {
        val packets = capturePackets()
        val values = PublishSubject.create<ByteArray>()
        handler.subscribeToNotifications(request(), {}, { throw AssertionError(it) })
        setupResponses.onNext(values)

        setupResponses.onError(IllegalStateException("GATT connection lost"))

        assertThat(packets).hasSize(1)
        assertThat(packets.single().failure.message).isEqualTo("GATT connection lost")
        assertThat(values.hasObservers()).isFalse()
    }

    @Test
    fun `unexpected value stream completion invalidates readiness and reports failure`() {
        val packets = capturePackets()
        val values = PublishSubject.create<ByteArray>()
        handler.subscribeToNotifications(request(), {}, { throw AssertionError(it) })
        setupResponses.onNext(values)
        values.onComplete()

        assertThat(packets).hasSize(1)
        assertThat(packets.single().hasFailure()).isTrue()
        assertThat(setupResponses.hasObservers()).isFalse()
        var lateWaitCompleted = false
        handler.awaitNotificationSetup(
            deviceId, characteristicUuid,
            onSetupCompleted = { lateWaitCompleted = true },
            onSetupFailed = {},
        )
        assertThat(lateWaitCompleted).isFalse()
    }

    @Test
    fun `outer completion after readiness reports failure instead of remaining silently ready`() {
        val packets = capturePackets()
        val values = PublishSubject.create<ByteArray>()
        handler.subscribeToNotifications(request(), {}, { throw AssertionError(it) })
        setupResponses.onNext(values)
        setupResponses.onComplete()

        assertThat(packets).hasSize(1)
        assertThat(packets.single().hasFailure()).isTrue()
        assertThat(values.hasObservers()).isFalse()
    }

    @Test
    fun `value stream ending during setup never reports readiness`() {
        var readyCount = 0
        var failureCount = 0
        handler.subscribeToNotifications(
            request(),
            onSetupCompleted = { readyCount += 1 },
            onSetupFailed = { failureCount += 1 },
        )
        setupResponses.onNext(Observable.empty())

        assertThat(readyCount).isEqualTo(0)
        assertThat(failureCount).isEqualTo(1)
        assertThat(setupResponses.hasObservers()).isFalse()
        handler.awaitNotificationSetup(
            deviceId, characteristicUuid,
            onSetupCompleted = { readyCount += 1 },
            onSetupFailed = { failureCount += 1 },
        )
        assertThat(readyCount).isEqualTo(0)
        assertThat(failureCount).isEqualTo(2)
    }

    @Test
    fun `replacement detaches old values and keeps only the new listener`() {
        val packets = capturePackets()
        val oldValues = PublishSubject.create<ByteArray>()
        handler.subscribeToNotifications(request(), {}, { throw AssertionError(it) })
        setupResponses.onNext(oldValues)
        handler.subscribeToNotifications(request(), {}, { throw AssertionError(it) })
        val newValues = PublishSubject.create<ByteArray>()
        setupResponses.onNext(newValues)

        oldValues.onNext(byteArrayOf(1))
        newValues.onNext(byteArrayOf(2))

        assertThat(oldValues.hasObservers()).isFalse()
        assertThat(packets).hasSize(1)
        assertThat(packets.single().value.toByteArray()).isEqualTo(byteArrayOf(2))
        handler.onCancel(null)
        assertThat(newValues.hasObservers()).isFalse()
        assertThat(setupResponses.hasObservers()).isFalse()
        assertThat(packets).hasSize(1)
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

    private fun capturePackets(): MutableList<pb.CharacteristicValueInfo> {
        val packets = mutableListOf<pb.CharacteristicValueInfo>()
        val sink = mockk<EventChannel.EventSink>()
        every { sink.success(any()) } answers {
            packets.add(pb.CharacteristicValueInfo.parseFrom(firstArg<ByteArray>()))
            Unit
        }
        handler.onListen(null, sink)
        return packets
    }

    private fun request(): pb.NotifyCharacteristicRequest =
        pb.NotifyCharacteristicRequest
            .newBuilder()
            .setCharacteristic(
                pb.CharacteristicAddress
                    .newBuilder()
                    .setDeviceId(deviceId)
                    .setServiceUuid(
                        pb.Uuid.newBuilder().setData(
                            ByteString.copyFrom(
                                UuidConverter().byteArrayFromUuid(
                                    UUID.fromString("0000fa10-1212-efde-1523-785feabcd123"),
                                ),
                            ),
                        ).build(),
                    )
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
