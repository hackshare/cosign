import CoreBluetooth
import Foundation

public final class CoreBluetoothLedgerTransport: NSObject, LedgerAPDUTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hackshare.cosign.ledger-ble")

    private var central: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var discoveredDevices: [UUID: LedgerBLEDevice] = [:]

    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var scanContinuation: CheckedContinuation<[LedgerBLEDevice], Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var pendingConnectID: UUID?

    // A scan requested before the central manager finished powering on (first
    // launch / permission grant). Held until centralManagerDidUpdateState settles.
    private var scanAwaitingPowerOn = false
    private var pendingScanTimeout: TimeInterval?

    private var exchangeContinuation: CheckedContinuation<LedgerAPDUResponse, Error>?
    private var pendingFrames: [Data] = []
    private var receivedFrames: [Data] = []
    private var nextFrameIndex = 0

    override public init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    public func scan(timeout: TimeInterval = 8) async throws -> [LedgerBLEDevice] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[LedgerBLEDevice], any Error>) in
            queue.async {
                guard self.scanContinuation == nil else {
                    continuation.resume(throwing: LedgerBLETransportError.scanInProgress)
                    return
                }

                switch self.central.state {
                case .poweredOn:
                    self.scanContinuation = continuation
                    self.beginScan(timeout: timeout)
                case .unknown, .resetting:
                    // The manager is still coming up (first launch or just after
                    // the permission grant). Hold the scan until it settles
                    // rather than failing with "Bluetooth is not ready yet".
                    self.scanContinuation = continuation
                    self.scanAwaitingPowerOn = true
                    self.pendingScanTimeout = timeout
                    self.queue.asyncAfter(deadline: .now() + .seconds(5)) {
                        guard self.scanAwaitingPowerOn, let pending = self.scanContinuation else {
                            return
                        }
                        self.scanAwaitingPowerOn = false
                        self.scanContinuation = nil
                        pending.resume(throwing: self.unavailableError(for: self.central.state))
                    }
                default:
                    continuation.resume(throwing: self.unavailableError(for: self.central.state))
                }
            }
        }
    }

    /// Starts the actual peripheral scan. `scanContinuation` must already be set;
    /// must be called on `queue` with the central powered on.
    private func beginScan(timeout: TimeInterval) {
        scanAwaitingPowerOn = false
        discovered.removeAll()
        discoveredDevices.removeAll()
        central.scanForPeripherals(withServices: [LedgerBLEUUID.service])

        queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout * 1000))) {
            guard let continuation = self.scanContinuation else {
                return
            }
            self.central.stopScan()
            self.scanContinuation = nil
            continuation.resume(returning: self.discoveredDevices.values.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            })
        }
    }

    public func connect(to device: LedgerBLEDevice, timeout: TimeInterval = 15) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard self.connectContinuation == nil else {
                    continuation.resume(throwing: LedgerBLETransportError.connectInProgress)
                    return
                }
                guard self.central.state == .poweredOn else {
                    continuation.resume(throwing: self.unavailableError(for: self.central.state))
                    return
                }
                guard let peripheral = self.discovered[device.id] else {
                    continuation.resume(throwing: LedgerBLETransportError.unknownDevice(device.id))
                    return
                }

                self.connectContinuation = continuation
                self.pendingConnectID = device.id
                self.connectedPeripheral = nil
                self.writeCharacteristic = nil
                self.notifyCharacteristic = nil
                peripheral.delegate = self
                self.central.connect(peripheral)

                self.queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout * 1000))) {
                    guard let continuation = self.connectContinuation,
                          self.pendingConnectID == device.id
                    else {
                        return
                    }
                    self.central.cancelPeripheralConnection(peripheral)
                    self.connectContinuation = nil
                    self.pendingConnectID = nil
                    continuation.resume(throwing: LedgerBLETransportError.connectionFailed("Connection timed out."))
                }
            }
        }
    }

    public func disconnect() {
        queue.async {
            guard let connectedPeripheral = self.connectedPeripheral else {
                return
            }
            self.central.cancelPeripheralConnection(connectedPeripheral)
        }
    }

    public func exchange(_ command: LedgerAPDUCommand) async throws -> LedgerAPDUResponse {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            LedgerAPDUResponse,
            any Error
        >) in
            queue.async {
                guard self.exchangeContinuation == nil else {
                    continuation.resume(throwing: LedgerBLETransportError.exchangeInProgress)
                    return
                }
                guard let peripheral = self.connectedPeripheral,
                      let writeCharacteristic = self.writeCharacteristic
                else {
                    continuation.resume(throwing: LedgerBLETransportError.notConnected)
                    return
                }

                do {
                    self.pendingFrames = try LedgerBLEFraming.encodeAPDU(
                        command.encoded,
                        mtu: peripheral.maximumWriteValueLength(for: .withResponse)
                    )
                    self.receivedFrames = []
                    self.nextFrameIndex = 0
                    self.exchangeContinuation = continuation
                    self.writeNextFrame(to: peripheral, characteristic: writeCharacteristic)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func writeNextFrame(to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard nextFrameIndex < pendingFrames.count else {
            return
        }

        let frame = pendingFrames[nextFrameIndex]
        nextFrameIndex += 1
        peripheral.writeValue(frame, for: characteristic, type: .withResponse)
    }

    private func finishExchange(_ result: Result<LedgerAPDUResponse, Error>) {
        guard let continuation = exchangeContinuation else {
            return
        }

        exchangeContinuation = nil
        pendingFrames = []
        receivedFrames = []
        nextFrameIndex = 0

        switch result {
        case let .success(response):
            continuation.resume(returning: response)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        guard let continuation = connectContinuation else {
            return
        }

        connectContinuation = nil
        pendingConnectID = nil

        switch result {
        case .success:
            continuation.resume()
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func unavailableError(for state: CBManagerState) -> LedgerBLETransportError {
        switch state {
        case .poweredOff:
            .bluetoothUnavailable(.off)
        case .unauthorized:
            .bluetoothUnavailable(.unauthorized)
        case .unsupported:
            .bluetoothUnavailable(.unsupported)
        case .resetting:
            .bluetoothUnavailable(.resetting)
        case .unknown:
            .bluetoothUnavailable(.notReady)
        case .poweredOn:
            .bluetoothUnavailable(.unavailable)
        @unknown default:
            .bluetoothUnavailable(.unavailable)
        }
    }
}

extension CoreBluetoothLedgerTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Start a scan that was requested before the manager finished
            // powering on.
            if scanAwaitingPowerOn, scanContinuation != nil {
                beginScan(timeout: pendingScanTimeout ?? 8)
            }
        case .unknown, .resetting:
            // Still transient — keep any pending scan waiting; the scan()
            // safety timeout gives up if it never settles.
            break
        default:
            // Terminal-unavailable (off / unauthorized / unsupported): fail
            // pending work with a specific reason.
            if let scanContinuation {
                self.scanContinuation = nil
                scanAwaitingPowerOn = false
                scanContinuation.resume(throwing: unavailableError(for: central.state))
            }
            finishConnect(.failure(unavailableError(for: central.state)))
            finishExchange(.failure(unavailableError(for: central.state)))
        }
    }

    public func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Ledger"
        discovered[peripheral.identifier] = peripheral
        discoveredDevices[peripheral.identifier] = LedgerBLEDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )
    }

    public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([LedgerBLEUUID.service])
    }

    public func centralManager(
        _: CBCentralManager,
        didFailToConnect _: CBPeripheral,
        error: (any Error)?
    ) {
        finishConnect(.failure(LedgerBLETransportError
                .connectionFailed(error?.localizedDescription ?? "Connection failed.")))
    }

    public func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error _: (any Error)?
    ) {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        finishConnect(.failure(LedgerBLETransportError.disconnected))
        finishExchange(.failure(LedgerBLETransportError.disconnected))
    }
}

extension CoreBluetoothLedgerTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            finishConnect(.failure(LedgerBLETransportError.connectionFailed(error.localizedDescription)))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == LedgerBLEUUID.service }) else {
            finishConnect(.failure(LedgerBLETransportError.missingService))
            return
        }

        peripheral.discoverCharacteristics(
            [LedgerBLEUUID.notifyCharacteristic, LedgerBLEUUID.writeCharacteristic],
            for: service
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        if let error {
            finishConnect(.failure(LedgerBLETransportError.connectionFailed(error.localizedDescription)))
            return
        }

        notifyCharacteristic = service.characteristics?.first { $0.uuid == LedgerBLEUUID.notifyCharacteristic }
        writeCharacteristic = service.characteristics?.first { $0.uuid == LedgerBLEUUID.writeCharacteristic }

        guard let notifyCharacteristic, writeCharacteristic != nil else {
            finishConnect(.failure(LedgerBLETransportError.missingCharacteristic))
            return
        }

        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    public func peripheral(
        _: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            finishConnect(.failure(LedgerBLETransportError.connectionFailed(error.localizedDescription)))
            return
        }

        if characteristic.uuid == LedgerBLEUUID.notifyCharacteristic, characteristic.isNotifying {
            finishConnect(.success(()))
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor _: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            finishExchange(.failure(LedgerBLETransportError.connectionFailed(error.localizedDescription)))
            return
        }

        if let writeCharacteristic {
            writeNextFrame(to: peripheral, characteristic: writeCharacteristic)
        }
    }

    public func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            finishExchange(.failure(LedgerBLETransportError.connectionFailed(error.localizedDescription)))
            return
        }
        guard characteristic.uuid == LedgerBLEUUID.notifyCharacteristic,
              let value = characteristic.value
        else {
            return
        }

        receivedFrames.append(value)
        do {
            let apdu = try LedgerBLEFraming.decodeAPDU(receivedFrames)
            try finishExchange(.success(LedgerAPDUResponse(encoded: apdu)))
        } catch LedgerBLEFramingError.incompletePayload {
            return
        } catch {
            finishExchange(.failure(error))
        }
    }
}
