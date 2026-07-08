import CosignCore
import Foundation
import Indexer

public final class SquadsService: @unchecked Sendable {
    let rpcURL: String
    let indexer: HeliusDASClient
    let relay: any RelayClient
    let demoFixture: CosignDemoFixture?
    private let membershipCache = ReadThroughCache<String, [SquadSummary]>(defaultTTL: 30)
    private let membersCache = ReadThroughCache<String, [SquadMember]>(defaultTTL: 60)
    private let detailCache = ReadThroughCache<String, SquadDetail>(defaultTTL: 30)
    private let proposalsCache = ReadThroughCache<ProposalCacheKey, [SquadProposalSummary]>(defaultTTL: 30)
    private let activityCache = ReadThroughCache<ActivityCacheKey, [SquadActivityItem]>(defaultTTL: 15)
    let executionSignatureCache = ExecutionSignatureCache()

    public init(
        environment: IndexerEnvironment,
        indexer: HeliusDASClient? = nil,
        demoFixture: CosignDemoFixture? = nil,
        healthReporter: NetworkHealthReporter? = nil
    ) {
        rpcURL = environment.effectiveRPCURL.absoluteString
        relay = environment.relay
        self.demoFixture = demoFixture
        self.indexer = indexer ?? HeliusDASClient(
            rpcURL: environment.effectiveRPCURL,
            healthReporter: healthReporter
        )
    }

    public func squads(forMember pubkey: String) async throws -> [SquadSummary] {
        if let demoFixture {
            return try demoFixture.memberSquads(for: MemberSquadsRequest(memberAddress: pubkey))
                .squads
                .map(SquadSummary.init(record:))
        }

        return try await membershipCache.value(for: pubkey) {
            let response = try await self.relay.memberSquads(
                for: MemberSquadsRequest(memberAddress: pubkey)
            )
            return response.squads.map(SquadSummary.init(record:))
        }
    }

    public func detail(of squadAddress: String) async throws -> SquadDetail {
        if let demoFixture {
            return try makeSquadDetail(
                from: demoFixture.squadDetail(for: SquadDetailRequest(squadAddress: squadAddress)).squad,
                fixture: demoFixture
            )
        }

        return try await detailCache.value(for: squadAddress, ttl: 60) {
            let detail = try await self.relaySquadDetail(of: squadAddress)
            return try await self.makeSquadDetail(from: detail)
        }
    }

    /// The addresses of a squad's own vaults, used to classify an inspected
    /// transaction's effects as inflows or outflows relative to the squad.
    public func ownVaultAddresses(of squadAddress: String) async throws -> Set<String> {
        try await Set(detail(of: squadAddress).vaults.map(\.ref.address))
    }

    public func members(of squadAddress: String) async throws -> [SquadMember] {
        if let demoFixture {
            return try demoFixture.squadDetail(for: SquadDetailRequest(squadAddress: squadAddress))
                .squad
                .members
                .map(SquadMember.init(record:))
        }

        return try await membersCache.value(for: squadAddress, ttl: 60) {
            let detail = try await self.relaySquadDetail(of: squadAddress)
            return detail.members.map(SquadMember.init(record:))
        }
    }

    public func proposals(
        in squadAddress: String,
        range: ProposalRange
    ) async throws -> [SquadProposalSummary] {
        if let demoFixture {
            return try demoFixture.squadProposals(for: SquadProposalsRequest(
                squadAddress: squadAddress,
                fromIndex: range.fromIndex,
                toIndex: range.toIndex
            ))
            .proposals
            .map(SquadProposalSummary.init(record:))
            .sorted { $0.transactionIndex > $1.transactionIndex }
        }

        return try await proposalsCache.value(for: ProposalCacheKey(squad: squadAddress, range: range)) {
            let response = try await self.relay.squadProposals(
                for: SquadProposalsRequest(
                    squadAddress: squadAddress,
                    fromIndex: range.fromIndex,
                    toIndex: range.toIndex
                )
            )
            return response.proposals
                .map(SquadProposalSummary.init(record:))
                .sorted { $0.transactionIndex > $1.transactionIndex }
        }
    }

    public func proposal(
        in squadAddress: String,
        transactionIndex: UInt64
    ) async throws -> SquadProposalDetail {
        if let demoFixture {
            return try SquadProposalDetail(record: demoFixture.squadProposal(for: SquadProposalRequest(
                squadAddress: squadAddress,
                transactionIndex: transactionIndex
            )).proposal)
        }

        let response = try await relay.squadProposal(
            for: SquadProposalRequest(squadAddress: squadAddress, transactionIndex: transactionIndex)
        )
        return SquadProposalDetail(record: response.proposal)
    }

    public func activity(
        in squadAddress: String,
        before: String? = nil,
        limit: UInt32 = 50
    ) async throws -> [SquadActivityItem] {
        try await activity(forAddress: squadAddress, before: before, limit: limit)
    }

    public func activity(
        forAddress address: String,
        before: String? = nil,
        limit: UInt32 = 50
    ) async throws -> [SquadActivityItem] {
        if let demoFixture {
            return try demoFixture.accountActivity(for: AccountActivityRequest(
                address: address,
                beforeSignature: before,
                limit: limit
            ))
            .activity
            .map(SquadActivityItem.init(record:))
        }

        return try await activityCache.value(for: ActivityCacheKey(address: address, before: before, limit: limit)) {
            let response = try await self.relay.accountActivity(
                for: AccountActivityRequest(address: address, beforeSignature: before, limit: limit)
            )
            return response.activity.map(SquadActivityItem.init(record:))
        }
    }
}

private extension SquadsService {
    func relaySquadDetail(of squadAddress: String) async throws -> RelaySquadDetail {
        let response = try await relay.squadDetail(
            for: SquadDetailRequest(squadAddress: squadAddress)
        )
        return response.squad
    }

    func makeSquadDetail(from record: RelaySquadDetail) async throws -> SquadDetail {
        await makeSquadDetail(from: SquadDetailFields(
            address: record.address,
            displayName: record.displayName,
            threshold: record.threshold,
            timeLockSeconds: record.timeLockSeconds,
            rentCollector: record.rentCollector,
            transactionIndex: record.transactionIndex,
            staleTransactionIndex: record.staleTransactionIndex,
            isAutonomous: record.isAutonomous,
            members: record.members.map(SquadMember.init(record:)),
            vaultRefs: record.vaults.map(SquadVaultRef.init(record:))
        ))
    }

    func makeSquadDetail(from record: RelaySquadDetail, fixture: CosignDemoFixture) -> SquadDetail {
        let vaults = record.vaults.map { ref in
            let vaultRef = SquadVaultRef(record: ref)
            return VaultDetail(
                ref: vaultRef,
                nativeBalanceLamports: fixture.nativeBalanceLamports(for: ref.address),
                assets: fixture.assets(for: ref.address) ?? []
            )
        }

        return SquadDetail(
            address: record.address,
            displayName: record.displayName,
            threshold: record.threshold,
            timeLockSeconds: record.timeLockSeconds,
            rentCollector: record.rentCollector,
            transactionIndex: record.transactionIndex,
            staleTransactionIndex: record.staleTransactionIndex,
            isAutonomous: record.isAutonomous,
            members: record.members.map(SquadMember.init(record:)),
            vaults: vaults
        )
    }

    func makeSquadDetail(from fields: SquadDetailFields) async -> SquadDetail {
        var vaults = [VaultDetail]()
        for ref in fields.vaultRefs {
            async let nativeBalance = loadNativeBalance(for: ref.address)
            async let assets = loadVaultAssets(for: ref.address)
            let vaultBalance = await nativeBalance
            let vaultAssets = await assets
            vaults.append(VaultDetail(
                ref: ref,
                nativeBalanceLamports: vaultBalance,
                assets: vaultAssets
            ))
        }

        return SquadDetail(
            address: fields.address,
            displayName: fields.displayName,
            threshold: fields.threshold,
            timeLockSeconds: fields.timeLockSeconds,
            rentCollector: fields.rentCollector,
            transactionIndex: fields.transactionIndex,
            staleTransactionIndex: fields.staleTransactionIndex,
            isAutonomous: fields.isAutonomous,
            members: fields.members,
            vaults: vaults
        )
    }

    func loadNativeBalance(for address: String) async -> UInt64? {
        try? await indexer.getNativeBalance(pubkey: address)
    }

    func loadVaultAssets(for address: String) async -> [DASAsset] {
        await (try? indexer.getAssetsByOwner(owner: address)) ?? []
    }
}

private struct SquadDetailFields {
    let address: String
    let displayName: String?
    let threshold: UInt16
    let timeLockSeconds: UInt32
    let rentCollector: String?
    let transactionIndex: UInt64
    let staleTransactionIndex: UInt64
    let isAutonomous: Bool
    let members: [SquadMember]
    let vaultRefs: [SquadVaultRef]
}

extension SquadsService {
    func clearReadCaches() async {
        await membershipCache.removeAll()
        await membersCache.removeAll()
        await detailCache.removeAll()
        await activityCache.removeAll()
        await proposalsCache.removeAll()
    }
}

public extension SquadsService {
    func refreshSquads(forMember pubkey: String) async throws -> [SquadSummary] {
        await membershipCache.removeValue(for: pubkey)
        return try await squads(forMember: pubkey)
    }

    func refreshDetail(of squadAddress: String) async throws -> SquadDetail {
        await detailCache.removeValue(for: squadAddress)
        return try await detail(of: squadAddress)
    }

    func refreshMembers(of squadAddress: String) async throws -> [SquadMember] {
        await membersCache.removeValue(for: squadAddress)
        return try await members(of: squadAddress)
    }

    func refreshProposals(
        in squadAddress: String,
        range: ProposalRange
    ) async throws -> [SquadProposalSummary] {
        await proposalsCache.removeValue(for: ProposalCacheKey(squad: squadAddress, range: range))
        return try await proposals(in: squadAddress, range: range)
    }

    func refreshActivity(
        in squadAddress: String,
        before: String? = nil,
        limit: UInt32 = 50
    ) async throws -> [SquadActivityItem] {
        try await refreshActivity(forAddress: squadAddress, before: before, limit: limit)
    }

    func refreshActivity(
        forAddress address: String,
        before: String? = nil,
        limit: UInt32 = 50
    ) async throws -> [SquadActivityItem] {
        let key = ActivityCacheKey(address: address, before: before, limit: limit)
        await activityCache.removeValue(for: key)
        return try await activity(forAddress: address, before: before, limit: limit)
    }
}

private struct ProposalCacheKey: Hashable {
    let squad: String
    let range: ProposalRange
}

private struct ActivityCacheKey: Hashable {
    let address: String
    let before: String?
    let limit: UInt32
}
