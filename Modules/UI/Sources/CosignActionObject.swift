import Indexer
import Squads
import SwiftUI

struct ActionObject: Equatable {
    let title: String
    let subtitle: String?
    let severity: ActionSeverity
    let confidence: ActionConfidence
    let source: String?
    let roles: [ActionRole]
    let warnings: [RelayInspectionWarning]

    var usesGenericReviewCopy: Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedTitle == CosignCopy.ActionObject.reviewRawInstructionsBeforeSigningTitle.lowercased() ||
            normalizedTitle == CosignCopy.ActionObject.reviewUnknownExecutedInstructionsTitle.lowercased()
    }

    /// Whether a generic relay "unknown instruction" action may be replaced by a local
    /// (bundled- or IDL-decoded) action for legibility. Only when it is NOT high-risk:
    /// a high-severity generic action carries the type-to-confirm gate, and a local decode
    /// (including a relay-supplied on-chain IDL) must never lift that gate.
    var isReplaceableByLocalDecode: Bool {
        usesGenericReviewCopy && severity != .high
    }
}

enum ActionObjectContext {
    case preSign
    case executed
}

enum ActionSeverity: Equatable {
    case routine
    case authority
    case high

    var label: String {
        switch self {
        case .routine:
            CosignCopy.ActionObject.routineSeverity
        case .authority:
            CosignCopy.ActionObject.authoritySeverity
        case .high:
            CosignCopy.ActionObject.highRiskSeverity
        }
    }

    var color: Color {
        switch self {
        case .routine:
            CosignTheme.accentDeep
        case .authority:
            CosignTheme.riskAmber
        case .high:
            CosignTheme.riskRed
        }
    }
}

enum ActionConfidence: Equatable {
    case known
    case idl
    case partial
    case unknown

    var label: String {
        switch self {
        case .known:
            CosignCopy.ActionObject.decodedConfidence
        case .idl:
            CosignCopy.ActionObject.idlConfidence
        case .partial:
            CosignCopy.ActionObject.partialConfidence
        case .unknown:
            CosignCopy.ActionObject.unknownConfidence
        }
    }

    var filledBars: Int {
        switch self {
        case .known:
            4
        case .idl:
            3
        case .partial:
            2
        case .unknown:
            0
        }
    }
}

struct ActionRole: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String
    var subvalue: String?
    var isAddressLike = false
    var isDanger = false

    static func == (lhs: ActionRole, rhs: ActionRole) -> Bool {
        lhs.label == rhs.label &&
            lhs.value == rhs.value &&
            lhs.subvalue == rhs.subvalue &&
            lhs.isAddressLike == rhs.isAddressLike &&
            lhs.isDanger == rhs.isDanger
    }
}

extension RelayInspectionAction {
    var actionObject: ActionObject {
        actionObject()
    }

    func actionObject(context: ActionObjectContext = .preSign) -> ActionObject {
        ActionObject(
            title: title(context: context),
            subtitle: subtitle(context: context),
            severity: actionSeverity,
            confidence: actionConfidence,
            source: primarySource,
            roles: actionRoles,
            warnings: warnings
        )
    }

    private func title(context: ActionObjectContext) -> String {
        if context == .executed, usesGenericUnknownPreSignCopy {
            return CosignCopy.ActionObject.reviewUnknownExecutedInstructionsTitle
        }
        return summary
    }

    private func subtitle(context: ActionObjectContext) -> String? {
        if context == .executed, usesGenericUnknownPreSignCopy {
            return CosignCopy.ActionObject.manualReviewRequiredSubtitle
        }

        guard let firstEffect = effects.first else {
            return confidence.lowercased() == "low" ? CosignCopy.ActionObject.manualReviewRequiredSubtitle : nil
        }
        if let program = firstEffect.program {
            return "\(displayLabel(firstEffect.kind)) · \(program)"
        }
        return displayLabel(firstEffect.kind)
    }

    private var usesGenericUnknownPreSignCopy: Bool {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
            CosignCopy.ActionObject.reviewRawInstructionsBeforeSigningTitle
        ) == .orderedSame
    }

    private var actionSeverity: ActionSeverity {
        if classification.lowercased().contains("unknown") || warnings.contains(where: { warning in
            cosignWarningIsHighRisk(warning.severity)
        }) {
            return .high
        }

        let authorityTerms = [
            "authority",
            "threshold",
            "upgrade",
            "nonce",
            "lookup_table",
            "stake_authorize",
            "set_authority"
        ]
        if authorityTerms.contains(where: { classification.lowercased().contains($0) }) {
            return classification.lowercased().contains("upgrade") ? .high : .authority
        }

        if effects.contains(where: { effect in
            let value = "\(effect.kind) \(effect.summary)".lowercased()
            return value.contains("authority") || value.contains("upgrade") || value.contains("nonce")
        }) {
            return .authority
        }

        return .routine
    }

    private var actionConfidence: ActionConfidence {
        switch confidence.lowercased() {
        case "decoded", "high", "known":
            .known
        case "idl":
            .idl
        case "medium", "partial":
            .partial
        default:
            .unknown
        }
    }

    private var primarySource: String? {
        effects.compactMap(\.program).first ?? (classification == "unknown" ? nil : displayLabel(classification))
    }

    private var actionRoles: [ActionRole] {
        var roles = [ActionRole]()
        for effect in effects {
            if let amount = effect.amount {
                roles.append(ActionRole(label: CosignCopy.ActionObject.amountRole, value: amount))
            }
            if let asset = effect.asset {
                roles.append(ActionRole(
                    label: CosignCopy.ActionObject.assetRole,
                    value: asset,
                    isAddressLike: asset != "SOL"
                ))
            }
            if let source = effect.source {
                roles.append(ActionRole(label: CosignCopy.ActionObject.fromRole, value: source, isAddressLike: true))
            }
            if let destination = effect.destination {
                roles.append(ActionRole(
                    label: CosignCopy.ActionObject.toRole,
                    value: destination,
                    isAddressLike: true,
                    isDanger: actionSeverity != .routine
                ))
            }
            if let program = effect.program {
                roles.append(ActionRole(label: CosignCopy.ActionObject.programRole, value: program))
            }
        }

        if roles.isEmpty {
            roles.append(ActionRole(label: CosignCopy.ActionObject.actionRole, value: displayLabel(classification)))
        }

        return uniqueRoles(roles)
    }
}

/// Confidence for a locally decoded action, tied to the tier-3 effect cross-check.
/// A registry decode earns the cap only when simulation confirms it; a contradiction
/// yields nil so the caller drops the confident statement (raw + simulation remain).
func registryConfidence(provenance: DecodeProvenance?, crossCheck: CrossCheckVerdict?) -> ActionConfidence? {
    guard case .registry = provenance else {
        return provenance == nil ? .partial : .idl
    }
    switch crossCheck {
    case .confirmed: return .known
    case .contradicted: return nil
    case .unconfirmed, .none: return .idl
    }
}

func cosignShortAddress(_ address: String, prefix: Int = 4, suffix: Int = 4) -> String {
    guard address.count > prefix + suffix + 1 else {
        return address
    }
    return "\(address.prefix(prefix))…\(address.suffix(suffix))"
}

/// Medium address form (7+7) for surfaces with room for more disambiguation
/// than the default 4+4 short form (member rows, squad/vault headers, movement legs).
func cosignMediumAddress(_ address: String) -> String {
    cosignShortAddress(address, prefix: 7, suffix: 7)
}

private func uniqueRoles(_ roles: [ActionRole]) -> [ActionRole] {
    var seen = Set<String>()
    return roles.filter { role in
        seen.insert("\(role.label)|\(role.value)").inserted
    }
}

func cosignWarningIsHighRisk(_ severity: String) -> Bool {
    ["high", "high-risk", "error", "critical", "danger"].contains(severity.lowercased())
}

func cosignWarningTone(for severity: String) -> CosignBannerTone {
    cosignWarningIsHighRisk(severity) ? .red : .amber
}

func cosignWarningSeverityLabel(_ severity: String) -> String {
    switch severity.lowercased() {
    case "high", "high-risk":
        CosignCopy.ActionObject.highRiskSeverity
    default:
        displayLabel(severity)
    }
}

func cosignWarningTitle(_ warning: RelayInspectionWarning) -> String {
    switch warning.code.lowercased() {
    case "first_time_recipient":
        CosignCopy.ProposalDetail.firstTimeRecipientWarningTitle
    default:
        cosignWarningSeverityLabel(warning.severity)
    }
}
