import Foundation
import SwiftData
import Testing
@testable import Core
@testable import Persistence

struct RegisteredSignerTests {
    @Test func roundTrip() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let context = ModelContext(container)

        let pubkey = Data(repeating: 0xAA, count: 32)
        let signer = RegisteredSigner(
            label: "Test Wallet",
            type: .hotWallet,
            pubkey: pubkey,
            keychainItemRef: "test-keychain-ref"
        )
        context.insert(signer)
        try context.save()

        let descriptor = FetchDescriptor<RegisteredSigner>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.label == "Test Wallet")
        #expect(fetched.first?.type == .hotWallet)
        #expect(fetched.first?.pubkey == pubkey)
        #expect(fetched.first?.keychainItemRef == "test-keychain-ref")
    }

    @Test func backedUpDefaultsToTrueForGrandfathering() {
        let signer = RegisteredSigner(
            label: "Legacy",
            type: .hotWallet,
            pubkey: Data(repeating: 0xAA, count: 32)
        )
        #expect(signer.backedUp == true)
        #expect(signer.backedUpAt == nil)
    }

    @Test func backupFieldsRoundTrip() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let context = ModelContext(container)

        let confirmedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let signer = RegisteredSigner(
            label: "Backed",
            type: .hotWallet,
            pubkey: Data(repeating: 0xBB, count: 32),
            backedUp: true,
            backedUpAt: confirmedAt
        )
        context.insert(signer)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RegisteredSigner>())
        #expect(fetched.first?.backedUp == true)
        #expect(fetched.first?.backedUpAt == confirmedAt)
    }

    @Test func deletion() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let context = ModelContext(container)

        let signer = RegisteredSigner(
            label: "ToRemove",
            type: .hotWallet,
            pubkey: Data(repeating: 0x55, count: 32)
        )
        context.insert(signer)
        try context.save()

        context.delete(signer)
        try context.save()

        let descriptor = FetchDescriptor<RegisteredSigner>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.isEmpty)
    }
}
