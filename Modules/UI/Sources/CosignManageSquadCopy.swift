import Foundation

public extension CosignCopy {
    enum ManageSquad {
        public static let entryTitle = String(localized: "Manage", bundle: .module)
        public static let screenTitle = String(localized: "Manage squad", bundle: .module)

        // Sections
        public static let membersSection = String(localized: "Members", bundle: .module)
        public static let addMemberSection = String(localized: "Add member", bundle: .module)
        public static let thresholdSection = String(localized: "Threshold", bundle: .module)

        // Member editing
        public static let addMemberPlaceholder = String(localized: "Member address", bundle: .module)
        public static let addMember = String(localized: "Add", bundle: .module)
        public static let removeMember = String(localized: "Remove", bundle: .module)
        public static let youBadge = String(localized: "You", bundle: .module)
        public static let addedBadge = String(localized: "New", bundle: .module)

        // Permissions
        public static let permissionPropose = String(localized: "Propose", bundle: .module)
        public static let permissionVote = String(localized: "Vote", bundle: .module)
        public static let permissionExecute = String(localized: "Execute", bundle: .module)
        public static let changedBadge = String(localized: "Changed", bundle: .module)
        public static let memberMissingPermission = String(
            localized: "Every member needs at least one permission.",
            bundle: .module
        )

        /// Per-member diff line for proposal review: "<short addr>: <old bits> → <new bits>"
        public static func memberDiff(address: String, old: String, new: String) -> String {
            String(localized: "\(address): \(old) \u{2192} \(new)", bundle: .module)
        }

        /// Section title diff: only includes non-zero segments, separated by U+00B7
        public static func memberChangeDiff(added: Int, changed: Int, removed: Int) -> String {
            [
                added > 0 ? (added == 1 ? String(localized: "1 added", bundle: .module) : String(
                    localized: "\(added) added",
                    bundle: .module
                )) : nil,
                changed > 0 ? (changed == 1 ? String(localized: "1 changed", bundle: .module) : String(
                    localized: "\(changed) changed",
                    bundle: .module
                )) : nil,
                removed > 0 ? (removed == 1 ? String(localized: "1 removed", bundle: .module) : String(
                    localized: "\(removed) removed",
                    bundle: .module
                )) : nil
            ]
            .compactMap(\.self)
            .joined(separator: " \u{00B7} ")
        }

        /// Self-removal warnings
        public static let selfRemovalSoloWarning = String(
            localized: "You will lose access to this squad.",
            bundle: .module
        )
        public static let selfRemovalQuorumWarning =
            String(localized: "This removal needs the squad's approval before it takes effect.", bundle: .module)

        // Address validation
        public static let invalidAddress = String(localized: "That is not a valid Solana address.", bundle: .module)
        public static let duplicateAddress = String(localized: "That member is already in the squad.", bundle: .module)

        /// Diff summary
        public static func diff(added: Int, removed: Int) -> String {
            [
                added > 0 ? (added == 1 ? String(localized: "1 added", bundle: .module) : String(
                    localized: "\(added) added",
                    bundle: .module
                )) : nil,
                removed > 0 ? (removed == 1 ? String(localized: "1 removed", bundle: .module) : String(
                    localized: "\(removed) removed",
                    bundle: .module
                )) : nil
            ]
            .compactMap(\.self)
            .joined(separator: " \u{00B7} ")
        }

        /// Threshold
        public static func thresholdSummary(_ threshold: Int, of total: Int) -> String {
            String(localized: "\(threshold) of \(total) signatures", bundle: .module)
        }

        public static let thresholdTooLow = String(localized: "Threshold must be at least 1.", bundle: .module)
        public static let thresholdTooHigh = String(
            localized: "Threshold cannot exceed the number of members.",
            bundle: .module
        )

        public static func voterCount(_ count: Int) -> String {
            count == 1 ? String(localized: "1 approval required", bundle: .module) : String(
                localized: "\(count) approvals required",
                bundle: .module
            )
        }

        // Time lock
        public static let timeLockSection = String(localized: "Time lock", bundle: .module)
        public static let timeLockSubtitle = String(localized: "Delay between approval and execution.", bundle: .module)
        public static let timeLockCustom = String(localized: "Custom", bundle: .module)
        public static let timeLockOff = String(localized: "Off", bundle: .module)
        public static let timeLockOutOfRange = String(localized: "Time lock must be 90 days or less.", bundle: .module)
        public static let timeLockUnitMinutes = String(localized: "Minutes", bundle: .module)
        public static let timeLockUnitHours = String(localized: "Hours", bundle: .module)
        public static let timeLockUnitDays = String(localized: "Days", bundle: .module)
        public static let timeLockCustomPlaceholder = String(localized: "0", bundle: .module)
        public static let timeLockCustomHint = String(
            localized: "0 = off \u{00B7} max 90 days (Squads program limit)",
            bundle: .module
        )

        public static func timeLockCurrent(_ display: String) -> String {
            String(localized: "Currently: \(display)", bundle: .module)
        }

        public static func timeLockDiff(old: String, new: String) -> String {
            String(localized: "Time lock: \(old) \u{2192} \(new)", bundle: .module)
        }

        // Rent collector
        public static let rentCollectorSection = String(localized: "Rent collector", bundle: .module)
        public static let rentCollectorSubtitle = String(
            localized: "Receives reclaimed rent from closed accounts.",
            bundle: .module
        )
        public static let rentCollectorPlaceholder = String(localized: "Collector address", bundle: .module)
        public static let rentCollectorHint = String(
            localized: "Optional. Left unset, reclaimed rent stays with the squad.",
            bundle: .module
        )
        public static let rentCollectorSet = String(localized: "Set", bundle: .module)

        public static func rentCollectorCurrent(_ display: String) -> String {
            String(localized: "Currently: \(display)", bundle: .module)
        }

        public static func rentCollectorDiff(old: String, new: String) -> String {
            String(localized: "Rent collector: \(old) \u{2192} \(new)", bundle: .module)
        }

        // Proposal creation
        public static let createButton = String(localized: "Create proposal", bundle: .module)
        public static let creating = String(localized: "Creating proposal", bundle: .module)
        public static let controlledNote =
            String(localized: "This squad's configuration is managed by an external authority.", bundle: .module)

        /// Errors
        public static let demoDisabled = String(
            localized: "Configuration changes are disabled in the demo build.",
            bundle: .module
        )
        public static let noEligibleSigner = String(
            localized: "No active signer can propose changes in this squad.",
            bundle: .module
        )
        public static let noVotersRemain = String(
            localized: "The squad must keep at least one voting member.",
            bundle: .module
        )
        public static let noProposersRemain = String(
            localized: "The squad must keep at least one member who can propose.",
            bundle: .module
        )
        public static let noExecutorsRemain = String(
            localized: "The squad must keep at least one member who can execute.",
            bundle: .module
        )
        public static let noChangesError = String(localized: "There are no changes to propose.", bundle: .module)
        public static let contradictoryEditError = String(
            localized: "The changes contain a conflict and cannot be submitted.",
            bundle: .module
        )
        public static func createFailed(_ message: String) -> String {
            String(localized: "Could not create the proposal. \(message)", bundle: .module)
        }

        // Load error
        public static let loadErrorTitle = String(localized: "Could not load squad", bundle: .module)
        public static let loadErrorMessage = String(
            localized: "The squad details could not be retrieved. Check your connection and try again.",
            bundle: .module
        )
        public static let loadErrorRetry = String(localized: "Retry", bundle: .module)
    }
}
