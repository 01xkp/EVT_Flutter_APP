#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

import Foundation
import class CoreBluetooth.CBUUID
import struct CoreBluetooth.CBCharacteristicProperties
import class CoreBluetooth.CBService
import enum CoreBluetooth.CBManagerState
import var CoreBluetooth.CBAdvertisementDataServiceDataKey
import var CoreBluetooth.CBAdvertisementDataServiceUUIDsKey
import var CoreBluetooth.CBAdvertisementDataManufacturerDataKey
import var CoreBluetooth.CBAdvertisementDataIsConnectable
import var CoreBluetooth.CBAdvertisementDataLocalNameKey

private func evtSupportsNotify(_ properties: CBCharacteristicProperties) -> Bool {
    properties.contains(.notify) || properties.contains(.notifyEncryptionRequired)
}

private func evtSupportsIndicate(_ properties: CBCharacteristicProperties) -> Bool {
    properties.contains(.indicate) || properties.contains(.indicateEncryptionRequired)
}

final class PluginController {

    private static let evtFileTransferCharacteristicUUID = CBUUID(
        string: "0000FF13-1212-EFDE-1523-785FEABCD123"
    )
    // A control/read indication can arrive during the method-channel handoff
    // that follows CCC setup. Keep a bounded queue for that short window;
    // never retain the unbounded FF13 audio/file stream without a Dart sink.
    private static let pendingCharacteristicMessageLimit = 64

    struct Scan {
        let services: [CBUUID]
    }

    private struct NotificationSetupKey: Hashable {
        let deviceID: String
        let characteristicUUID: String
    }

    private enum NotificationSetupOutcome {
        case ready
        case failed(FlutterError)
    }

    private final class NotificationSetupState {
        var outcome: NotificationSetupOutcome?
        var subscriptionInProgress = false
        var waiters: [FlutterResult] = []
    }

    private var central: Central?
    private var scan: StreamingTask<Scan>?
    var stateSink: EventSink? {
        didSet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.reportState()
            }
        }
    }
    private var messageQueue: [CharacteristicValueInfo] = []
    var connectedDeviceSink: EventSink?
    private var characteristicValueUpdateSink: EventSink?
    private let characteristicMessageLock = NSLock()
    private var notificationSetupStates: [NotificationSetupKey: NotificationSetupState] = [:]

    /// Installs the Dart characteristic stream sink and atomically takes the
    /// bounded handoff queue. The queued control frames are delivered while
    /// the lock is held so a newly arriving frame cannot overtake an older
    /// response during the flush.
    func installCharacteristicValueSink(_ sink: EventSink) {
        characteristicMessageLock.lock()
        defer { characteristicMessageLock.unlock() }

        characteristicValueUpdateSink = sink
        let queued = messageQueue
        messageQueue.removeAll(keepingCapacity: true)
        print(
            "【AIPIN原生BLE】【通知通道】Flutter监听已建立，补发暂存回包：\(queued.count)条"
        )
        queued.forEach { message in
            sink.add(.success(message))
        }
    }

    /// Clears only the handoff queue. It is used when a peripheral disconnects
    /// or the native client is reinitialized, because buffered frames belong
    /// to the previous GATT connection.
    func clearCharacteristicMessageQueue() {
        characteristicMessageLock.lock()
        messageQueue.removeAll(keepingCapacity: true)
        characteristicMessageLock.unlock()
    }

    /// Removes the Dart sink and drops buffered frames as one operation. This
    /// closes the cancellation race with CoreBluetooth value callbacks.
    func removeCharacteristicValueSink() {
        characteristicMessageLock.lock()
        characteristicValueUpdateSink = nil
        messageQueue.removeAll(keepingCapacity: true)
        characteristicMessageLock.unlock()
    }

    /// Delivers a characteristic value or stores it for the short method
    /// channel handoff window. FF13 is a streaming file/audio channel and is
    /// intentionally never buffered without an active Dart consumer.
    func emitCharacteristicValue(
        _ message: CharacteristicValueInfo,
        isFileTransfer: Bool
    ) {
        characteristicMessageLock.lock()
        defer { characteristicMessageLock.unlock() }

        if let sink = characteristicValueUpdateSink {
            sink.add(.success(message))
            return
        }

        if isFileTransfer {
            print(
                "【AIPIN原生BLE】【回包丢弃】Flutter监听未建立，丢弃FF13文件/音频流分包：\(message.value.count)字节"
            )
            return
        }

        if messageQueue.count >= Self.pendingCharacteristicMessageLimit {
            messageQueue.removeFirst()
            print("【AIPIN原生BLE】【回包暂存】控制回包缓存已满，丢弃最旧一条")
        }
        messageQueue.append(message)
        print(
            "【AIPIN原生BLE】【回包暂存】Flutter监听未建立，暂存控制回包：当前\(messageQueue.count)条"
        )
    }

    func initialize(name: String, completion: @escaping PlatformMethodCompletionHandler) {
        invalidateAllNotificationSetups()
        // A value can be queued while Flutter is between stream listeners.
        // Never carry that packet across a new native BLE client: it belongs
        // to the previous GATT session and could satisfy a new command.
        clearCharacteristicMessageQueue()
        if let central = central {
            central.stopScan()
            central.disconnectAll()
        }

        central = Central(
            onStateChange: papply(weak: self) { context, _, state in
                context.reportState(state)
            },
            onDiscovery: papply(weak: self) { context, _, peripheral, advertisementData, rssi in
                guard let sink = context.scan?.sink
                else { assert(false); return }

                let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? ServiceData ?? [:]
                let serviceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
                let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
                let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()
                let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? String()
                let deviceDiscoveryMessage = DeviceScanInfo.with {
                    $0.id = peripheral.identifier.uuidString
                    $0.name = name
                    $0.rssi = Int32(rssi)
                    $0.isConnectable = IsConnectable()
                    switch isConnectable {
                    case .none:
                      $0.isConnectable.code = 0
                    case .some(let isConnectable):
                      $0.isConnectable.code = isConnectable ? 2 : 1
                    }
                    $0.serviceData = serviceData
                        .map { entry in
                            ServiceDataEntry.with {
                                $0.serviceUuid = Uuid.with { $0.data = entry.key.data }
                                $0.data = entry.value
                            }
                        }
                    $0.serviceUuids = serviceUuids.map { entry in Uuid.with { $0.data = entry.data }}
                    $0.manufacturerData = manufacturerData
                }

                sink.add(.success(deviceDiscoveryMessage))
            },
            onConnectionChange: papply(weak: self) { context, central, peripheral, change in
                let failure: (code: ConnectionFailure, message: String)?

                switch change {
                case .connected:
                    // Wait for services & characteristics to be discovered
                    return
                case .failedToConnect(let underlyingError), .disconnected(let underlyingError):
                    context.invalidateNotificationSetups(for: peripheral.identifier.uuidString)
                    // Drop packets buffered before the disconnect callback.
                    // The queue is only valid for the current peripheral
                    // connection and must not be replayed after reconnect.
                    context.clearCharacteristicMessageQueue()
                    failure = underlyingError.map { (.failedToConnect, "\($0)") }
                }

                let message = DeviceInfo.with {
                    $0.id = peripheral.identifier.uuidString
                    $0.connectionState = encode(peripheral.state)
                    if let error = failure {
                        $0.failure = GenericFailure.with {
                            $0.code = Int32(error.code.rawValue)
                            $0.message = error.message
                        }
                    }
                }

                context.connectedDeviceSink?.add(.success(message))
            },
            onServicesWithCharacteristicsInitialDiscovery: papply(weak: self) { context, central, peripheral, errors in
                guard let sink = context.connectedDeviceSink
                else { assert(false); return }

                let message = DeviceInfo.with {
                    $0.id = peripheral.identifier.uuidString
                    $0.connectionState = encode(peripheral.state)
                    if !errors.isEmpty {
                        $0.failure = GenericFailure.with {
                            $0.code = Int32(ConnectionFailure.unknown.rawValue)
                            $0.message = errors.map(String.init(describing:)).joined(separator: "\n")
                        }
                    }
                }

                sink.add(.success(message))
            },
            onCharacteristicValueUpdate: papply(weak: self) { context, central, characteristic, value, error in
                let message = CharacteristicValueInfo.with {
                    $0.characteristic = CharacteristicAddress.with {
                        $0.characteristicUuid = Uuid.with { $0.data = characteristic.id.data }
                        $0.characteristicInstanceID = characteristic.instanceID
                        $0.serviceUuid = Uuid.with { $0.data = characteristic.serviceID.data }
                        $0.serviceInstanceID = characteristic.serviceInstanceID
                        $0.deviceID = characteristic.peripheralID.uuidString
                    }
                    if let value = value {
                        $0.value = value
                    }
                    if let error = error {
                        $0.failure = GenericFailure.with {
                            $0.code = Int32(CharacteristicValueUpdateFailure.unknown.rawValue)
                            $0.message = "\(error)"
                        }
                    }
                }
                // CoreBluetooth can deliver an indication in the small
                // window between CCC acknowledgement and the Dart stream
                // listener being attached. Route it through the atomic sink /
                // queue handoff so that response cannot be lost or reordered.
                context.emitCharacteristicValue(
                    message,
                    isFileTransfer: characteristic.id ==
                        PluginController.evtFileTransferCharacteristicUUID
                )
            }
        )

        completion(.success(nil))
    }

    func deinitialize(name: String, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        central.stopScan()
        central.disconnectAll()
        invalidateAllNotificationSetups()
        clearCharacteristicMessageQueue()

        self.central = nil

        completion(.success(nil))
    }

    func scanForDevices(name: String, args: ScanForDevicesRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        assert(!central.isScanning)

        scan = StreamingTask(parameters: .init(services: args.serviceUuids.map({ uuid in CBUUID(data: uuid.data) })))

        completion(.success(nil))
    }

    func startScanning(sink: EventSink) -> FlutterError? {
        guard let central = central
        else { return PluginError.notInitialized.asFlutterError }

        guard let scan = scan
        else { return PluginError.internalInconcictency(details: "a scanning task has not been initialized yet, but a client has subscribed").asFlutterError }

        self.scan = scan.with(sink: sink)

        central.scanForDevices(with: scan.parameters.services)

        return nil
    }

    func stopScanning() -> FlutterError? {
        central?.stopScan()
        return nil
    }

    func connectToDevice(name: String, args: ConnectToDeviceRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        let servicesWithCharacteristicsToDiscover: ServicesWithCharacteristicsToDiscover
        if args.hasServicesWithCharacteristicsToDiscover {
            let items = args.servicesWithCharacteristicsToDiscover.items.reduce(
                into: [ServiceID: [CharacteristicID]](), { dict, item in
                    let serviceID = CBUUID(data: item.serviceID.data)
                    let characteristicIDs = item.characteristics.map { CBUUID(data: $0.data) }

                    dict[serviceID] = characteristicIDs
                }
            )
            servicesWithCharacteristicsToDiscover = ServicesWithCharacteristicsToDiscover.some(items.mapValues(CharacteristicsToDiscover.some))
        } else {
            servicesWithCharacteristicsToDiscover = .all
        }

        let timeout = args.timeoutInMs > 0 ? TimeInterval(args.timeoutInMs) / 1000 : nil

        completion(.success(nil))

        if let sink = connectedDeviceSink {
            let message = DeviceInfo.with {
                $0.id = args.deviceID
                $0.connectionState = encode(.connecting)
            }
            sink.add(.success(message))
        } else {
            print("Warning! No event channel set up to report a connection update")
        }

        do {
            try central.connect(
                to: deviceID,
                discover: servicesWithCharacteristicsToDiscover,
                timeout: timeout
            )
        } catch {
            guard let sink = connectedDeviceSink
            else {
                print("Warning! No event channel set up to report a connection failure: \(error)")
                return
            }

            let message = DeviceInfo.with {
                $0.id = args.deviceID
                $0.connectionState = encode(.disconnected)
                $0.failure = GenericFailure.with {
                    $0.code = Int32(ConnectionFailure.failedToConnect.rawValue)
                    $0.message = "\(error)"
                }
            }

            sink.add(.success(message))
        }
    }

    func disconnectFromDevice(name: String, args: ConnectToDeviceRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        // CoreBluetooth disconnect is asynchronous. Waiting for Central's
        // terminal callback prevents the next same-device connection stream
        // from receiving this connection's late disconnected event.
        central.disconnect(from: deviceID) {
            completion(.success(nil))
        }
    }

    func discoverServices(name: String, args: DiscoverServicesRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        func makeDiscoveredService(service: CBService) -> DiscoveredService {
            DiscoveredService.with {
                $0.serviceUuid = Uuid.with { $0.data = service.uuid.data }
                $0.serviceInstanceID = service.instanceId?.description ?? ""
                $0.characteristicUuids = (service.characteristics ?? []).map { characteristic in
                    Uuid.with { $0.data = characteristic.uuid.data }
                }
                $0.characteristics = (service.characteristics ?? []).map { characteristic in
                    DiscoveredCharacteristic.with {
                        $0.characteristicID = Uuid.with {$0.data = characteristic.uuid.data}
                        $0.characteristicInstanceID = characteristic.instanceId?.description ?? ""
                        if characteristic.service?.uuid.data != nil {
                            $0.serviceID = Uuid.with {$0.data = characteristic.service!.uuid.data}
                        }
                        $0.isReadable = characteristic.properties.contains(.read)
                        $0.isWritableWithResponse = characteristic.properties.contains(.write)
                        $0.isWritableWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
                        $0.isNotifiable = evtSupportsNotify(characteristic.properties)
                        $0.isIndicatable = evtSupportsIndicate(characteristic.properties)
                    }
                }

                $0.includedServices = (service.includedServices ?? []).map(makeDiscoveredService)
            }
        }

        do {
            try central.discoverServicesWithCharacteristics(
                for: deviceID,
                discover: .all,
                completion: { central, peripheral, errors in
                    // Keep the method-channel contract consistent with
                    // Android: a partial CoreBluetooth discovery must not be
                    // reported as a successful, complete GATT snapshot. The
                    // connected-device event stream also reports this error,
                    // but callers awaiting discoverServices need the failure
                    // on the method result to stop before subscribing or
                    // sending EVT commands against an incomplete profile.
                    if !errors.isEmpty {
                        completion(.failure(
                            PluginError.unknown(
                                NSError(
                                    domain: "reactive_ble_mobile.service_discovery",
                                    code: ConnectionFailure.unknown.rawValue,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: errors
                                            .map(String.init(describing:))
                                            .joined(separator: "\n")
                                    ]
                                )
                            ).asFlutterError
                        ))
                        return
                    }

                    completion(.success(DiscoverServicesInfo.with {
                        $0.deviceID = deviceID.uuidString
                        $0.services = (peripheral.services ?? []).map(makeDiscoveredService)
                    }))
                }
            )
        } catch {
            completion(.failure(PluginError.unknown(error).asFlutterError))
        }
    }

    func getDiscoveredServices(name: String, args: DiscoverServicesRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let deviceID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "\"deviceID\" is invalid").asFlutterError))
            return
        }

        func makeDiscoveredService(service: CBService) -> DiscoveredService {
            DiscoveredService.with {
                $0.serviceUuid = Uuid.with { $0.data = service.uuid.data }
                $0.serviceInstanceID = service.instanceId?.description ?? ""
                $0.characteristicUuids = (service.characteristics ?? []).map { characteristic in
                    Uuid.with { $0.data = characteristic.uuid.data }
                }
                $0.characteristics = (service.characteristics ?? []).map { characteristic in
                    DiscoveredCharacteristic.with {
                        $0.characteristicID = Uuid.with {$0.data = characteristic.uuid.data}
                        $0.characteristicInstanceID = characteristic.instanceId?.description ?? ""
                        if characteristic.service?.uuid.data != nil {
                            $0.serviceID = Uuid.with {$0.data = characteristic.service!.uuid.data}
                        }
                        $0.isReadable = characteristic.properties.contains(.read)
                        $0.isWritableWithResponse = characteristic.properties.contains(.write)
                        $0.isWritableWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
                        $0.isNotifiable = evtSupportsNotify(characteristic.properties)
                        $0.isIndicatable = evtSupportsIndicate(characteristic.properties)
                    }
                }

                $0.includedServices = (service.includedServices ?? []).map(makeDiscoveredService)
            }
        }

        do {
            let peripheral = try central.peripheral(for: deviceID)
            completion(.success(DiscoverServicesInfo.with {
                        $0.deviceID = deviceID.uuidString
                        $0.services = (peripheral.services ?? []).map(makeDiscoveredService)
                    }))

        } catch {
            completion(.failure(PluginError.unknown(error).asFlutterError))
        }
    }

    func enableCharacteristicNotifications(name: String, args: NotifyCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        guard let setupKey = notificationSetupKey(
            deviceID: args.characteristic.deviceID,
            characteristicUuidData: args.characteristic.characteristicUuid.data
        ) else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "a 128-bit characteristic UUID is required").asFlutterError))
            return
        }
        let setupState = notificationSetupStateForSubscription(setupKey)

        do {
            try central.turnNotifications(.on, for: characteristic, completion: { [weak self] _, error in
                guard let self = self else { return }
                if let error = error {
                    let setupError = self.notificationSetupError(error)
                    completion(.failure(setupError))
                    self.completeNotificationSetup(
                        key: setupKey,
                        state: setupState,
                        outcome: .failed(setupError)
                    )
                } else {
                    // The Dart subscription attaches its characteristic-value
                    // listener from the method-result async continuation.
                    // Complete that method first, then release the explicit
                    // readiness barrier on the next main-loop turn so a
                    // command cannot race the Dart listener after CCC setup.
                    completion(.success(nil))
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self,
                              self.notificationSetupStates[setupKey] === setupState,
                              setupState.outcome == nil,
                              setupState.subscriptionInProgress
                        else { return }
                        self.completeNotificationSetup(
                            key: setupKey,
                            state: setupState,
                            outcome: .ready
                        )
                    }
                }
            })
        } catch {
            let setupError = notificationSetupError(error)
            completeNotificationSetup(
                key: setupKey,
                state: setupState,
                outcome: .failed(setupError)
            )
            completion(.failure(setupError))
        }
    }

    func disableCharacteristicNotifications(name: String, args: NotifyNoMoreCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        let setupKey = notificationSetupKey(
            deviceID: args.characteristic.deviceID,
            characteristicUuidData: args.characteristic.characteristicUuid.data
        )

        do {
            try central.turnNotifications(.off, for: characteristic, completion: { _, error in
                if let error = error {
                    completion(.failure(PluginError.unknown(error).asFlutterError))
                } else {
                    completion(.success(nil))
                }
            })
        } catch {
            completion(.failure(PluginError.unknown(error).asFlutterError))
        }
        if let setupKey = setupKey {
            invalidateNotificationSetup(setupKey, message: "Characteristic notification setup was cancelled.")
        }
    }

    /// Completes after CoreBluetooth confirms the CCC state update. It can be
    /// called before or after `readNotifications`; callers must apply a Dart
    /// timeout if no subscription is requested.
    func awaitNotificationSetup(arguments: Any?, completion: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let deviceID = arguments["deviceId"] as? String,
            !deviceID.isEmpty,
            let rawCharacteristicUUID = arguments["characteristicUuid"] as? String,
            let characteristicUUID = UUID(uuidString: rawCharacteristicUUID)
        else {
            completion(
                FlutterError(
                    code: "invalid_notification_setup_arguments",
                    message: "deviceId and a canonical 128-bit characteristicUuid are required",
                    details: nil
                )
            )
            return
        }

        let state = notificationSetupStateForWait(
            NotificationSetupKey(
                deviceID: deviceID.lowercased(),
                characteristicUUID: characteristicUUID.uuidString.lowercased()
            )
        )
        switch state.outcome {
        case .ready:
            completion(nil)
        case .failed(let error):
            completion(error)
        case .none:
            state.waiters.append(completion)
        }
    }

    private func notificationSetupKey(
        deviceID: String,
        characteristicUuidData: Data
    ) -> NotificationSetupKey? {
        let hex = characteristicUuidData.map { String(format: "%02x", $0) }.joined()
        let canonicalUUID: String
        switch characteristicUuidData.count {
        case 2:
            canonicalUUID = "0000\(hex)-0000-1000-8000-00805f9b34fb"
        case 4:
            canonicalUUID = "\(hex)-0000-1000-8000-00805f9b34fb"
        case 16:
            canonicalUUID = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        default:
            return nil
        }
        guard let parsedUUID = UUID(uuidString: canonicalUUID) else { return nil }
        return NotificationSetupKey(
            deviceID: deviceID.lowercased(),
            characteristicUUID: parsedUUID.uuidString.lowercased()
        )
    }

    private func notificationSetupStateForWait(_ key: NotificationSetupKey) -> NotificationSetupState {
        if let existing = notificationSetupStates[key] {
            return existing
        }
        let state = NotificationSetupState()
        notificationSetupStates[key] = state
        return state
    }

    private func notificationSetupStateForSubscription(_ key: NotificationSetupKey) -> NotificationSetupState {
        if let existing = notificationSetupStates[key] {
            if existing.outcome == nil && !existing.subscriptionInProgress {
                existing.subscriptionInProgress = true
                return existing
            }
            if existing.outcome == nil {
                completeNotificationSetup(
                    key: key,
                    state: existing,
                    outcome: .failed(
                        FlutterError(
                            code: "notification_setup_failed",
                            message: "Characteristic notification setup was replaced.",
                            details: nil
                        )
                    )
                )
            }
        }
        let state = NotificationSetupState()
        state.subscriptionInProgress = true
        notificationSetupStates[key] = state
        return state
    }

    private func completeNotificationSetup(
        key: NotificationSetupKey,
        state: NotificationSetupState,
        outcome: NotificationSetupOutcome
    ) {
        guard notificationSetupStates[key] === state else { return }
        state.subscriptionInProgress = false
        state.outcome = outcome
        let waiters = state.waiters
        state.waiters.removeAll()
        for waiter in waiters {
            switch outcome {
            case .ready:
                waiter(nil)
            case .failed(let error):
                waiter(error)
            }
        }
    }

    private func invalidateNotificationSetup(_ key: NotificationSetupKey, message: String) {
        // A completed CCC result is scoped to the current GATT connection.
        // Remove it on disconnect as well as an in-flight result; otherwise a
        // reconnect to the same iOS peripheral identifier could immediately
        // reuse stale readiness and send an EVT command before CCC is active.
        guard let state = notificationSetupStates.removeValue(forKey: key) else {
            return
        }
        guard state.outcome == nil else {
            return
        }
        let error = FlutterError(
            code: "notification_setup_failed",
            message: message,
            details: nil
        )
        let waiters = state.waiters
        state.waiters.removeAll()
        for waiter in waiters {
            waiter(error)
        }
    }

    private func invalidateNotificationSetups(for deviceID: String) {
        let keys = notificationSetupStates.keys.filter { $0.deviceID == deviceID.lowercased() }
        for key in keys {
            invalidateNotificationSetup(key, message: "The Bluetooth device disconnected during notification setup.")
        }
    }

    private func invalidateAllNotificationSetups() {
        let keys = Array(notificationSetupStates.keys)
        for key in keys {
            invalidateNotificationSetup(key, message: "The Bluetooth client was deinitialized during notification setup.")
        }
    }

    private func notificationSetupError(_ error: Error) -> FlutterError {
        FlutterError(
            code: "notification_setup_failed",
            message: "\(error)",
            details: nil
        )
    }

    func readCharacteristic(name: String, args: ReadCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        completion(.success(nil))

        do {
            try central.read(characteristic: characteristic)
        } catch {
            let message = CharacteristicValueInfo.with {
                $0.characteristic = args.characteristic
                $0.failure = GenericFailure.with {
                    $0.code = Int32(CharacteristicValueUpdateFailure.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }
            // Read failures use the same handoff queue as successful values;
            // otherwise a failure arriving before the Dart listener would be
            // silently lost and the command layer would wait until timeout.
            emitCharacteristicValue(message, isFileTransfer: false)
        }
    }

    func writeCharacteristicWithResponse(name: String, args: WriteCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        do {
            try central.writeWithResponse(
                value: args.value,
                characteristic: characteristic,
                completion: { _, characteristic, error in
                    let result = WriteCharacteristicInfo.with {
                        $0.characteristic = args.characteristic
                        if let error = error {
                            $0.failure = GenericFailure.with {
                                $0.code = Int32(WriteCharacteristicFailure.unknown.rawValue)
                                $0.message = "\(error)"
                            }
                        }
                    }

                    completion(.success(result))
                }
            )
        } catch {
            let result = WriteCharacteristicInfo.with {
                $0.characteristic = args.characteristic
                $0.failure = GenericFailure.with {
                    $0.code = Int32(WriteCharacteristicFailure.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }

            completion(.success(result))
        }
    }

    func writeCharacteristicWithoutResponse(name: String, args: WriteCharacteristicRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let characteristic = CharacteristicInstanceIDFactory().make(from: args.characteristic)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "characteristic, service, and peripheral IDs are required").asFlutterError))
            return
        }

        let result: WriteCharacteristicInfo
        do {
            try central.writeWithoutResponse(
                value: args.value,
                characteristic: characteristic
            )
            result = WriteCharacteristicInfo.with {
                $0.characteristic = args.characteristic
            }
        } catch {
            result = WriteCharacteristicInfo.with {
                $0.characteristic = args.characteristic
                $0.failure = GenericFailure.with {
                    $0.code = Int32(WriteCharacteristicFailure.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }
        }

        completion(.success(result))
    }

    func reportMaximumWriteValueLength(name: String, args: NegotiateMtuRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }

        guard let peripheralID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "peripheral ID is required").asFlutterError))
            return
        }

        let result: NegotiateMtuInfo
        do {
            let mtu = try central.maximumWriteValueLength(for: peripheralID, type: .withoutResponse)
            result = NegotiateMtuInfo.with {
                $0.deviceID = args.deviceID
                $0.mtuSize = Int32(mtu)
            }
        } catch {
            result = NegotiateMtuInfo.with {
                $0.deviceID = args.deviceID
                $0.failure = GenericFailure.with {
                    $0.code = Int32(MaximumWriteValueLengthRetrieval.unknown.rawValue)
                    $0.message = "\(error)"
                }
            }
        }

        completion(.success(result))
    }
    
    func readRssi(name: String, args: ReadRssiRequest, completion: @escaping PlatformMethodCompletionHandler) {
        guard let central = central
        else {
            completion(.failure(PluginError.notInitialized.asFlutterError))
            return
        }
        
        guard let peripheralID = UUID(uuidString: args.deviceID)
        else {
            completion(.failure(PluginError.invalidMethodCall(method: name, details: "peripheral ID is required").asFlutterError))
            return
        }

        do {
            try central.readRssi(
                for: peripheralID,
                completion: papply(weak: self) { context, result in
                    result.iif(
                        success: { rssi in
                            let result: ReadRssiResult = ReadRssiResult.with {
                                $0.rssi = Int32(rssi)
                            }
                            completion(.success(result))
                        },
                        failure: { error in
                            completion(.failure(context.makeFlutterError(error: error)))
                        }
                    )
                }
            )
        } catch let error {
            completion(.failure(makeFlutterError(error: error)))
        }
    }

    // takes an error and converts it into a Flutter error
    private func makeFlutterError(error: Error) -> FlutterError {
        if let error = error as? PluginError {
            return error.asFlutterError
        } else {
            return PluginError.unknown(error).asFlutterError
        }
    }

    private func reportState(_ knownState: CBManagerState? = nil) {
        guard let sink = stateSink
        else { return }

        let stateToReport = knownState ?? central?.state ?? .unknown
        let message = BleStatusInfo.with { $0.status = encode(stateToReport) }

        sink.add(.success(message))
    }
}
