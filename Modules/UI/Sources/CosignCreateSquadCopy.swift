import Foundation

public extension CosignCopy {
    enum CreateSquad {
        public static let entryTitle = String(localized: "Create a Squad", bundle: .module)
        public static let screenTitle = String(localized: "New Squad", bundle: .module)
        public static let eyebrow = String(localized: "Set up a multisig", bundle: .module)

        // Funding step
        public static let fundingTitle = String(localized: "Fund the creator", bundle: .module)
        public static let fundingBody =
            String(
                localized: "Creating a Squad costs a small amount of SOL for rent and the network fee. This signer pays.",
                bundle: .module
            )
        public static let balanceLabel = String(localized: "Creator balance", bundle: .module)
        public static let fundedEnough = String(localized: "Enough to create", bundle: .module)
        public static let needDevnetSOL = String(localized: "Need devnet SOL?", bundle: .module)
        public static let getDevnetSOL = String(localized: "Get devnet SOL", bundle: .module)
        public static let airdropWorking = String(localized: "Requesting devnet SOL", bundle: .module)
        public static let airdropFailedTitle = String(localized: "Faucet unavailable", bundle: .module)
        public static let airdropFailedBody =
            String(
                localized: "The devnet faucet is rate limited right now. Copy the address below and fund it from a web faucet, then continue.",
                bundle: .module
            )
        public static let copyAddress = String(localized: "Copy address", bundle: .module)
        public static let faucetLink = String(localized: "Open a devnet faucet", bundle: .module)
        public static func estimatedTotal(_ quantity: String) -> String {
            String(localized: "\u{2248} \(quantity) SOL", bundle: .module)
        }

        /// Mainnet funding (no faucet)
        public static let mainnetFundInstruction = String(
            localized: "Send SOL to this signer to continue.",
            bundle: .module
        )
        public static func mainnetNeedAmount(_ quantity: String) -> String {
            String(localized: "Need \u{2248} \(quantity) SOL", bundle: .module)
        }

        // Members step
        public static let membersTitle = String(localized: "Members", bundle: .module)
        public static let membersBody =
            String(
                localized: "You are the first member. Add more by address, or continue solo for a 1-of-1.",
                bundle: .module
            )
        public static let youCreator = String(localized: "You (creator)", bundle: .module)
        public static let pinnedTag = String(localized: "PINNED", bundle: .module)
        public static let addMemberPlaceholder = String(localized: "Member address", bundle: .module)
        public static let addMember = String(localized: "Add member", bundle: .module)
        public static let invalidAddress = String(localized: "That is not a valid Solana address.", bundle: .module)
        public static let duplicateAddress = String(localized: "That member is already added.", bundle: .module)
        public static func memberCount(_ count: Int) -> String {
            count == 1 ? String(localized: "1 member", bundle: .module) : String(
                localized: "\(count) members",
                bundle: .module
            )
        }

        // Threshold step
        public static let thresholdTitle = String(localized: "Threshold", bundle: .module)
        public static let thresholdBody =
            String(localized: "How many members must approve before a proposal can execute.", bundle: .module)
        public static func thresholdSummary(_ threshold: Int, of total: Int) -> String {
            String(localized: "\(threshold) of \(total) signatures", bundle: .module)
        }

        // Creator-only 1-of-1 resolved state
        public static let soloThresholdTitle = String(localized: "1 of 1 signatures", bundle: .module)
        public static let soloThresholdSubtitle = String(localized: "Just you, a solo signer.", bundle: .module)
        public static let soloThresholdExplainer =
            String(
                localized: "A 1-of-1 is a valid Squad. Add members later through a proposal to raise the threshold.",
                bundle: .module
            )

        // Review step
        public static let reviewTitle = String(localized: "Review", bundle: .module)
        public static let configurationLabel = String(localized: "Configuration", bundle: .module)
        public static let networkLabel = String(localized: "Network", bundle: .module)
        public static let devnetValue = String(localized: "Devnet", bundle: .module)
        public static let costLabel = String(localized: "Estimated cost", bundle: .module)
        public static let costNetworkFee = String(localized: "Network fee", bundle: .module)
        public static let costRent = String(localized: "Account rent", bundle: .module)
        public static let costCreationFee = String(localized: "Squads creation fee", bundle: .module)
        public static let costTotal = String(localized: "Total", bundle: .module)
        public static let solUnit = String(localized: "SOL", bundle: .module)
        public static let createButton = String(localized: "Create Squad", bundle: .module)
        public static let creating = String(localized: "Creating Squad", bundle: .module)
        public static let unavailableInDemo = String(localized: "Unavailable in demo", bundle: .module)

        // Result
        public static let successTitle = String(localized: "Squad created", bundle: .module)
        public static let successBody =
            String(
                localized: "Your multisig is live on devnet. It is autonomous, every change from here goes through a proposal.",
                bundle: .module
            )
        public static let resultSquadLabel = String(localized: "Squad", bundle: .module)
        public static func resultThreshold(_ threshold: Int, of total: Int) -> String {
            String(localized: "\(threshold) of \(total)", bundle: .module)
        }

        public static let resultMembersLabel = String(localized: "Members", bundle: .module)
        public static func resultMembersValue(_ count: Int) -> String {
            count == 1 ? String(localized: "1 member \u{00B7} you", bundle: .module) : String(
                localized: "\(count) members \u{00B7} you",
                bundle: .module
            )
        }

        public static let openSquad = String(localized: "Open Squad", bundle: .module)
        public static let viewOnExplorer = String(localized: "View on Explorer", bundle: .module)

        /// Errors
        public static let demoDisabled = String(
            localized: "Squad creation is disabled in the demo build.",
            bundle: .module
        )
        public static let noActiveSigner = String(
            localized: "No active signer is available to create the Squad.",
            bundle: .module
        )
        public static func createFailed(_ message: String) -> String {
            String(localized: "Could not create the Squad. \(message)", bundle: .module)
        }
    }
}
