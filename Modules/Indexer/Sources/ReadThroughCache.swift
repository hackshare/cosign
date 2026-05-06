import Foundation

public actor ReadThroughCache<Key: Hashable & Sendable, Value: Sendable> {
    private let cache = NSCache<WrappedKey<Key>, Entry<Value>>()
    private let defaultTTL: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        defaultTTL: TimeInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaultTTL = defaultTTL
        self.now = now
    }

    public func value(
        for key: Key,
        ttl: TimeInterval? = nil,
        loader: @Sendable () async throws -> Value
    ) async throws -> Value {
        let wrappedKey = WrappedKey(key)
        let currentDate = now()

        if let entry = cache.object(forKey: wrappedKey), entry.expiresAt > currentDate {
            return entry.value
        }

        let loaded = try await loader()
        cache.setObject(
            Entry(value: loaded, expiresAt: currentDate.addingTimeInterval(ttl ?? defaultTTL)),
            forKey: wrappedKey
        )
        return loaded
    }

    public func removeAll() {
        cache.removeAllObjects()
    }

    public func removeValue(for key: Key) {
        cache.removeObject(forKey: WrappedKey(key))
    }
}

private final class WrappedKey<Key: Hashable>: NSObject {
    let key: Key

    init(_ key: Key) {
        self.key = key
    }

    override var hash: Int {
        key.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? WrappedKey<Key> else {
            return false
        }
        return key == other.key
    }
}

private final class Entry<Value>: NSObject {
    let value: Value
    let expiresAt: Date

    init(value: Value, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }
}
