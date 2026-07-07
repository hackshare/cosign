import Foundation

public extension CosignCopy {
    enum ManageSquad {
        public static let entryTitle = "Manage"
        public static let screenTitle = "Manage squad"

        // Sections
        public static let membersSection = "Members"
        public static let addMemberSection = "Add member"
        public static let thresholdSection = "Threshold"

        // Member editing
        public static let addMemberPlaceholder = "Member address"
        public static let addMember = "Add"
        public static let removeMember = "Remove"
        public static let youBadge = "You"
        public static let addedBadge = "New"

        // Self-removal warnings
        public static let selfRemovalSoloWarning = "You will lose access to this squad."
        public static let selfRemovalQuorumWarning =
            "This removal needs the squad's approval before it takes effect."

        // Address validation
        public static let invalidAddress = "That is not a valid Solana address."
        public static let duplicateAddress = "That member is already in the squad."
        public static let notAMemberError = "That address is not a member of this squad."

        /// Diff summary
        public static func diff(added: Int, removed: Int) -> String {
            [
                added > 0 ? (added == 1 ? "1 added" : "\(added) added") : nil,
                removed > 0 ? (removed == 1 ? "1 removed" : "\(removed) removed") : nil
            ]
            .compactMap(\.self)
            .joined(separator: " \u{00B7} ")
        }

        /// Threshold
        public static func thresholdSummary(_ threshold: Int, of total: Int) -> String {
            "\(threshold) of \(total) signatures"
        }

        public static let thresholdTooLow = "Threshold must be at least 1."
        public static let thresholdTooHigh = "Threshold cannot exceed the number of members."

        public static func voterCount(_ count: Int) -> String {
            count == 1 ? "1 approval required" : "\(count) approvals required"
        }

        // Time lock
        public static let timeLockSection = "Time lock"
        public static let timeLockSubtitle = "Delay between approval and execution."
        public static let timeLockCustom = "Custom"
        public static let timeLockOff = "Off"
        public static let timeLockOutOfRange = "Time lock must be 90 days or less."
        public static let timeLockUnitMinutes = "Minutes"
        public static let timeLockUnitHours = "Hours"
        public static let timeLockUnitDays = "Days"
        public static let timeLockCustomPlaceholder = "0"
        public static let timeLockCustomHint = "0 = off \u{00B7} max 90 days (Squads program limit)"

        public static func timeLockCurrent(_ display: String) -> String {
            "Currently: \(display)"
        }

        public static func timeLockDiff(old: String, new: String) -> String {
            "Time lock: \(old) \u{2192} \(new)"
        }

        // Proposal creation
        public static let createButton = "Create proposal"
        public static let creating = "Creating proposal"
        public static let controlledNote =
            "This squad's configuration is managed by an external authority."

        // Errors
        public static let demoDisabled = "Configuration changes are disabled in the demo build."
        public static let noEligibleSigner = "No active signer can propose changes in this squad."
        public static let noVotersRemain = "The squad must keep at least one voting member."
        public static let noProposersRemain = "The squad must keep at least one member who can propose."
        public static let noExecutorsRemain = "The squad must keep at least one member who can execute."
        public static let noChangesError = "There are no changes to propose."
        public static let contradictoryEditError = "The changes contain a conflict and cannot be submitted."
        public static func createFailed(_ message: String) -> String {
            "Could not create the proposal. \(message)"
        }

        // Load error
        public static let loadErrorTitle = "Could not load squad"
        public static let loadErrorMessage = "The squad details could not be retrieved. Check your connection and try again."
        public static let loadErrorRetry = "Retry"
    }
}
