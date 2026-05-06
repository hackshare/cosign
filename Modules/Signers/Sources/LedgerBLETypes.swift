import CoreBluetooth
import Foundation

public struct LedgerBLEDevice: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

enum LedgerBLEUUID {
    static let service = CBUUID(string: "13D63400-2C97-6004-0000-4C6564676572")
    static let notifyCharacteristic = CBUUID(string: "13D63400-2C97-6004-0001-4C6564676572")
    static let writeCharacteristic = CBUUID(string: "13D63400-2C97-6004-0002-4C6564676572")
}

public enum LedgerBluetoothUnavailableReason: Equatable, Sendable {
    case off
    case unauthorized
    case unsupported
    case resetting
    case notReady
    case unavailable
}

enum LedgerBLETransportError: Error, Equatable {
    case bluetoothUnavailable(LedgerBluetoothUnavailableReason)
    case scanInProgress
    case connectInProgress
    case exchangeInProgress
    case unknownDevice(UUID)
    case notConnected
    case disconnected
    case missingService
    case missingCharacteristic
    case connectionFailed(String)
}
