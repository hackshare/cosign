import Indexer

public struct ProgramIDLResolver: Sendable {
    private let relay: any RelayClient

    public init(relay: any RelayClient) {
        self.relay = relay
    }

    public func resolve(programIDs: [String]) async -> [String: ResolvedProgramIDL] {
        let unique = Array(Set(programIDs))
        guard !unique.isEmpty else {
            return [:]
        }

        return await withTaskGroup(of: (String, ResolvedProgramIDL?).self) { group in
            for programID in unique {
                group.addTask {
                    await (programID, resolveOne(programID))
                }
            }

            var result = [String: ResolvedProgramIDL]()
            for await (programID, resolved) in group {
                if let resolved {
                    result[programID] = resolved
                }
            }
            return result
        }
    }

    private func resolveOne(_ programID: String) async -> ResolvedProgramIDL? {
        guard let response = try? await relay.programIDL(for: ProgramIDLRequest(programID: programID)) else {
            return nil
        }
        return ResolvedProgramIDL(
            document: response.idl,
            provenance: .onChainIDL(idlName: response.idl.name, hash: response.hash, slot: response.slot)
        )
    }
}
