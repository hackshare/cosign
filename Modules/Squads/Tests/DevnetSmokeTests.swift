import Foundation
import Indexer
import Testing
@testable import Squads

struct DevnetSmokeTests {
    @Test func configuredDevnetMultisigLoadsThroughService() async throws {
        guard let multisig = envString("COSIGN_DEVNET_MULTISIG") else {
            return
        }

        let service = SquadsService(environment: devnetEnvironment())
        let detail = try await service.detail(of: multisig)

        #expect(detail.address == multisig)
        #expect(!detail.members.isEmpty)
    }

    @Test func configuredDevnetMemberLoadsMembershipThroughService() async throws {
        guard let member = envString("COSIGN_DEVNET_MEMBER") else {
            return
        }

        let service = SquadsService(environment: devnetEnvironment())
        let squads = try await service.squads(forMember: member)

        #expect(squads.allSatisfy { !$0.address.isEmpty })
    }

    private func devnetEnvironment() -> IndexerEnvironment {
        IndexerEnvironment(
            rpcURL: URL(string: envString("COSIGN_DEVNET_RPC_URL") ?? IndexerEnvironment.devnetRPCURL.absoluteString)!
        )
    }

    private func envString(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
