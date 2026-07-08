import Foundation

public struct MemberPermissions: Equatable, Sendable {
    public let canInitiate: Bool
    public let canVote: Bool
    public let canExecute: Bool
    public init(canInitiate: Bool, canVote: Bool, canExecute: Bool) {
        self.canInitiate = canInitiate
        self.canVote = canVote
        self.canExecute = canExecute
    }
}

public enum ConfigChangeRow: Equatable, Sendable, Identifiable {
    case permission(address: String, old: MemberPermissions, new: MemberPermissions)
    case add(address: String, permissions: MemberPermissions)
    case remove(address: String)
    case threshold(oldValue: Int, oldOf: Int, newValue: Int, newOf: Int)
    /// The signing ratio shifting as a consequence of a voter-set change, when
    /// the threshold value itself is unchanged (M held constant, pool changes).
    /// Suppressed when the proposal carries an explicit threshold change.
    case signingPower(threshold: Int, oldOf: Int, newOf: Int)
    case timeLock(oldSeconds: UInt32, newSeconds: UInt32)
    case rentCollector(old: String?, new: String?)

    public var id: String {
        switch self {
        case let .permission(address, _, _): "perm-\(address)"
        case let .add(address, _): "add-\(address)"
        case let .remove(address): "remove-\(address)"
        case .threshold: "threshold"
        case .signingPower: "signingpower"
        case .timeLock: "timelock"
        case .rentCollector: "rentcollector"
        }
    }
}

public enum ConfigChangeSummary {
    /// Diffs a config proposal's structured actions against the current squad
    /// state. Returns [] when no instruction carries a `configAction` (caller
    /// then renders the flat summary rows).
    public static func build(detail: SquadDetail, instructions: [SquadDecodedInstruction]) -> [ConfigChangeRow] {
        let actions: [(kind: String, action: SquadConfigAction)] = instructions.compactMap { inst in
            inst.configAction.map { (inst.kind, $0) }
        }
        guard !actions.isEmpty else { return [] }

        let parsed = parseActions(actions)
        return permissionRows(parsed: parsed, currentMembers: detail.members)
            + thresholdRows(parsed: parsed, detail: detail)
            + addRemoveRows(parsed: parsed)
            + timeLockRentRows(parsed: parsed, detail: detail)
            + signingPowerRows(parsed: parsed, detail: detail)
    }
}

// MARK: - Private helpers

private extension ConfigChangeSummary {
    struct ParsedActions {
        var removeKeys: [String] = []
        var adds: [(key: String, perms: MemberPermissions)] = []
        var thresholdAction: SquadConfigAction?
        var timeLockAction: SquadConfigAction?
        var rentAction: SquadConfigAction?
    }

    static func parseActions(_ actions: [(kind: String, action: SquadConfigAction)]) -> ParsedActions {
        var parsed = ParsedActions()
        for (kind, action) in actions {
            switch kind {
            case "remove_member":
                if let key = action.memberKey { parsed.removeKeys.append(key) }
            case "add_member":
                if let key = action.memberKey {
                    parsed.adds.append((key, MemberPermissions(
                        canInitiate: action.canInitiate, canVote: action.canVote, canExecute: action.canExecute
                    )))
                }
            case "change_threshold": parsed.thresholdAction = action
            case "set_time_lock": parsed.timeLockAction = action
            case "set_rent_collector": parsed.rentAction = action
            default: break
            }
        }
        return parsed
    }

    /// Keys that are both removed and re-added (a permission change), collapsed
    /// into a single diff row rather than a raw Remove + Add pair.
    static func permissionKeys(_ parsed: ParsedActions) -> Set<String> {
        Set(parsed.removeKeys).intersection(Set(parsed.adds.map(\.key)))
    }

    static func permissionRows(parsed: ParsedActions, currentMembers: [SquadMember]) -> [ConfigChangeRow] {
        let keys = permissionKeys(parsed)
        let currentByKey = Dictionary(uniqueKeysWithValues: currentMembers.map { ($0.pubkey, $0) })
        return parsed.adds.filter { keys.contains($0.key) }.map { add in
            let current = currentByKey[add.key]
            let old = MemberPermissions(
                canInitiate: current?.canInitiate ?? false,
                canVote: current?.canVote ?? false,
                canExecute: current?.canExecute ?? false
            )
            return .permission(address: add.key, old: old, new: add.perms)
        }
    }

    static func addRemoveRows(parsed: ParsedActions) -> [ConfigChangeRow] {
        let keys = permissionKeys(parsed)
        var rows: [ConfigChangeRow] = []
        for add in parsed.adds where !keys.contains(add.key) {
            rows.append(.add(address: add.key, permissions: add.perms))
        }
        for key in parsed.removeKeys where !keys.contains(key) {
            rows.append(.remove(address: key))
        }
        return rows
    }

    /// Voting-member count before and after applying the proposal's member
    /// changes (removes then adds; a re-added key takes the add's vote status).
    static func voterCounts(parsed: ParsedActions, detail: SquadDetail) -> (old: Int, new: Int) {
        let old = detail.members.filter(\.canVote).count
        var voteByKey = Dictionary(uniqueKeysWithValues: detail.members.map { ($0.pubkey, $0.canVote) })
        for key in parsed.removeKeys {
            voteByKey[key] = nil
        }
        for add in parsed.adds {
            voteByKey[add.key] = add.perms.canVote
        }
        return (old, voteByKey.values.count(where: { $0 }))
    }

    static func thresholdRows(parsed: ParsedActions, detail: SquadDetail) -> [ConfigChangeRow] {
        guard let thresholdAction = parsed.thresholdAction, let newThreshold = thresholdAction.newThreshold else {
            return []
        }
        let counts = voterCounts(parsed: parsed, detail: detail)
        return [.threshold(
            oldValue: Int(detail.threshold), oldOf: counts.old,
            newValue: Int(newThreshold), newOf: counts.new
        )]
    }

    /// The derived signing-power row: shown when a voter-set change shifts the
    /// approval ratio but the threshold value is not explicitly changed. When an
    /// explicit threshold change is present, its row already reflects the new
    /// denominator, so this is suppressed to avoid a redundant row.
    static func signingPowerRows(parsed: ParsedActions, detail: SquadDetail) -> [ConfigChangeRow] {
        guard parsed.thresholdAction == nil else { return [] }
        let counts = voterCounts(parsed: parsed, detail: detail)
        guard counts.old != counts.new else { return [] }
        return [.signingPower(threshold: Int(detail.threshold), oldOf: counts.old, newOf: counts.new)]
    }

    static func timeLockRentRows(parsed: ParsedActions, detail: SquadDetail) -> [ConfigChangeRow] {
        var rows: [ConfigChangeRow] = []
        if let timeLockAction = parsed.timeLockAction, let newTimeLock = timeLockAction.newTimeLockSeconds {
            rows.append(.timeLock(oldSeconds: detail.timeLockSeconds, newSeconds: newTimeLock))
        }
        if let rentAction = parsed.rentAction {
            let newCollector = rentAction.clearsRentCollector ? nil : rentAction.newRentCollector
            rows.append(.rentCollector(old: detail.rentCollector, new: newCollector))
        }
        return rows
    }
}
