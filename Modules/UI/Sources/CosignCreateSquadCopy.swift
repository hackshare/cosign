import Foundation

public extension CosignCopy {
    enum CreateSquad {
        public static let entryTitle = "Create a Squad"
        public static let screenTitle = "New Squad"
        public static let eyebrow = "Set up a multisig"

        // Funding step
        public static let fundingTitle = "Fund the creator"
        public static let fundingBody =
            "Creating a Squad costs a small amount of SOL for rent and the network fee. This signer pays."
        public static let balanceLabel = "Creator balance"
        public static let fundedEnough = "Enough to create"
        public static let needDevnetSOL = "Need devnet SOL?"
        public static let getDevnetSOL = "Get devnet SOL"
        public static let airdropWorking = "Requesting devnet SOL"
        public static let airdropFailedTitle = "Faucet unavailable"
        public static let airdropFailedBody =
            "The devnet faucet is rate limited right now. Copy the address below and fund it from a web faucet, then continue."
        public static let copyAddress = "Copy address"
        public static let faucetLink = "Open a devnet faucet"
        public static func estimatedTotal(_ quantity: String) -> String {
            "\u{2248} \(quantity) SOL"
        }

        // Mainnet funding (no faucet)
        public static let mainnetFundInstruction = "Send SOL to this signer to continue."
        public static func mainnetNeedAmount(_ quantity: String) -> String {
            "Need \u{2248} \(quantity) SOL"
        }

        // Members step
        public static let membersTitle = "Members"
        public static let membersBody =
            "You are the first member. Add more by address, or continue solo for a 1-of-1."
        public static let youCreator = "You (creator)"
        public static let pinnedTag = "PINNED"
        public static let addMemberPlaceholder = "Member address"
        public static let addMember = "Add member"
        public static let invalidAddress = "That is not a valid Solana address."
        public static let duplicateAddress = "That member is already added."
        public static func memberCount(_ count: Int) -> String {
            count == 1 ? "1 member" : "\(count) members"
        }

        // Threshold step
        public static let thresholdTitle = "Threshold"
        public static let thresholdBody =
            "How many members must approve before a proposal can execute."
        public static func thresholdSummary(_ threshold: Int, of total: Int) -> String {
            "\(threshold) of \(total) signatures"
        }

        // Creator-only 1-of-1 resolved state
        public static let soloThresholdTitle = "1 of 1 signatures"
        public static let soloThresholdSubtitle = "Just you, a solo signer."
        public static let soloThresholdExplainer =
            "A 1-of-1 is a valid Squad. Add members later through a proposal to raise the threshold."

        // Review step
        public static let reviewTitle = "Review"
        public static let configurationLabel = "Configuration"
        public static let networkLabel = "Network"
        public static let devnetValue = "Devnet"
        public static let costLabel = "Estimated cost"
        public static let costNetworkFee = "Network fee"
        public static let costRent = "Account rent"
        public static let costCreationFee = "Squads creation fee"
        public static let costTotal = "Total"
        public static let solUnit = "SOL"
        public static let createButton = "Create Squad"
        public static let creating = "Creating Squad"
        public static let unavailableInDemo = "Unavailable in demo"

        // Result
        public static let successTitle = "Squad created"
        public static let successBody =
            "Your multisig is live on devnet. It is autonomous, every change from here goes through a proposal."
        public static let resultSquadLabel = "Squad"
        public static func resultThreshold(_ threshold: Int, of total: Int) -> String {
            "\(threshold) of \(total)"
        }

        public static let resultMembersLabel = "Members"
        public static func resultMembersValue(_ count: Int) -> String {
            count == 1 ? "1 member \u{00B7} you" : "\(count) members \u{00B7} you"
        }

        public static let openSquad = "Open Squad"
        public static let viewOnExplorer = "View on Explorer"

        // Errors
        public static let demoDisabled = "Squad creation is disabled in the demo build."
        public static let noActiveSigner = "No active signer is available to create the Squad."
        public static func createFailed(_ message: String) -> String {
            "Could not create the Squad. \(message)"
        }
    }
}
