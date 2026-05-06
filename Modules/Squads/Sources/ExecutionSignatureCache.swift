import Foundation

final class ExecutionSignatureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var signatures = [ExecutionSignatureCacheKey: String]()

    func signature(in squadAddress: String, transactionIndex: UInt64) -> String? {
        lock.withLock {
            signatures[ExecutionSignatureCacheKey(
                squadAddress: squadAddress,
                transactionIndex: transactionIndex
            )]
        }
    }

    func remember(_ signature: String, in squadAddress: String, transactionIndex: UInt64) {
        lock.withLock {
            signatures[ExecutionSignatureCacheKey(
                squadAddress: squadAddress,
                transactionIndex: transactionIndex
            )] = signature
        }
    }
}

private struct ExecutionSignatureCacheKey: Hashable {
    let squadAddress: String
    let transactionIndex: UInt64
}
