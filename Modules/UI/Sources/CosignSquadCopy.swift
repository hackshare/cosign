extension CosignCopy {
    enum Squads {
        static let memberSection = "Member"
        static let screenTitle = "Squads"
        static let copyMemberAddress = "Copy Member Address"
        static let unableToLoadSquadsTitle = "Unable to Load Squads"
        static let sectionTitle = "Squads"
        static let emptySignerAddressMessage = "The signer public key could not be encoded."
        static let copySquadAddress = "Copy Squad Address"
        static let noTransactions = "No proposals"

        static func pendingCount(_ count: Int) -> String {
            count == 1 ? "1 pending" : "\(count) pending"
        }

        static func transactionSummary(transactionIndex: UInt64, staleTransactionIndex: UInt64) -> String {
            guard transactionIndex > 0 || staleTransactionIndex > 0 else {
                return noTransactions
            }
            return "tx \(transactionIndex) · stale \(staleTransactionIndex)"
        }

        static func threshold(
            _ threshold: some BinaryInteger,
            memberCount: some BinaryInteger
        ) -> String {
            "\(threshold) / \(memberCount)"
        }
    }

    enum SquadDetail {
        static let navigationTitle = "Squad"
        static let unableToLoadSquadTitle = "Unable to Load Squad"
        static let emptySquadAddressMessage = "The Squad address is empty."
        static let combinedBalance = "Combined balance"
        static let usdSymbol = "USD"
        static let tokensMetric = "Tokens"
        static let nftsMetric = "NFTs"
        static let vaultsMetric = "Vaults"
        static let proposalsTab = "Proposals"
        static let activityTab = "Activity"
        static let latestTransactionMetric = "Latest tx"
        static let staleTransactionMetric = "Stale tx"
        static let timelockMetric = "Timelock"
        static let noMembersTitle = "No Members"
        static let noMembersMessage = "This Squad did not return any member accounts."
        static let membersSection = "Members"
        static let unavailable = "Unavailable"
        static let none = "None"
        static let initiatePermission = "Initiate"
        static let votePermission = "Vote"
        static let executePermission = "Execute"

        static func header(threshold: some BinaryInteger, memberCount: Int) -> String {
            "Squad · \(threshold) of \(memberCount)"
        }

        static func vaultCount(_ count: Int) -> String {
            count == 1 ? "1 vault" : "\(count) vaults"
        }

        static func memberCount(_ count: Int) -> String {
            count == 1 ? "1 member" : "\(count) members"
        }

        static func knownBalance(_ balance: String) -> String {
            "\(balance) known"
        }

        static func estimatedUSD(_ amount: String) -> String {
            "≈ \(amount) \(usdSymbol)"
        }

        static func staleTransaction(index: UInt64) -> String {
            index == 0 ? none : "#\(index)"
        }

        static func latestTransaction(index: UInt64) -> String {
            index == 0 ? none : "#\(index)"
        }

        static func timeLock(seconds: UInt32) -> String {
            seconds == 0 ? none : "\(seconds)s"
        }
    }

    enum Vaults {
        static let sectionTitle = "Vaults"
        static let holdingsSection = "Holdings"
        static let nftsSection = "NFTs"
        static let solSymbol = "SOL"
        static let solBalanceSubtitle = "Balance (SOL)"
        static let token2022Badge = "Token-2022"
        static let unknownToken = "Unknown token"
        static let unknownAmount = "Unknown"
        static let balanceUnavailable = "Balance unavailable"
        static let copyVaultAddress = "Copy Vault Address"

        static func title(index: UInt8) -> String {
            "Vault \(index)"
        }

        static func indexBadge(index: UInt8) -> String {
            "\(index)"
        }

        static func tokenCount(_ count: Int) -> String {
            count == 1 ? "1 token" : "\(count) tokens"
        }

        static func nftCount(_ count: Int) -> String {
            count == 1 ? "1 NFT" : "\(count) NFTs"
        }

        static func mintSubtitle(_ mint: String) -> String {
            "Mint \(mint)"
        }

        static func tokenAmount(_ amount: String, symbol: String?) -> String {
            guard let symbol, amount != unknownAmount else {
                return amount
            }
            return "\(amount) \(symbol)"
        }
    }

    enum VaultDetail {
        static let unableToLoadVaultTitle = "Unable to Load Vault"
        static let balance = "Balance"
        static let propose = "Propose"
        static let inspect = "Inspect"
        static let history = "History"
        static let usdValueColumn = "USD value"
        static let usdUnavailable = "—"
        static let openInExplorerAccessibilityLabel = "Open Vault in Explorer"

        static func missingVaultMessage(index: UInt8) -> String {
            "Vault \(index) was not returned for this Squad."
        }

        static func header(squadName: String, vaultIndex: UInt8) -> String {
            "\(squadName) · \(CosignCopy.Vaults.title(index: vaultIndex))"
        }

        static func holdingsTitle(assetCount: Int) -> String {
            "Holdings · \(assetCount) assets"
        }
    }

    enum VaultInspection {
        static let navigationTitle = "Vault Inspection"
        static let unableToLoadTitle = "Unable to Load Vault Inspection"
        static let identitySection = "Vault identity"
        static let authorityLabel = "Authority"
        static let ownerLabel = "owner"
        static let squadsProgramLabel = "Squads v4"
        static let holdingsLabel = "Holdings"
        static let recentMovementSection = "Recent movement · 30D"
        static let noRecentMovementTitle = "No recent movement"
        static let noRecentMovementMessage = "No recent transactions were returned for this vault."
        static let copyAddress = "Copy address"
        static let openInExplorer = "Open in Explorer"

        static func header(squadName: String, vaultIndex: UInt8) -> String {
            "Vault inspection · \(squadName) · Vault \(vaultIndex)"
        }

        static func vaultSubtitle(address: String) -> String {
            "\(address) · \(ownerLabel) · \(squadsProgramLabel)"
        }

        static func holdingsValue(sol: String, tokenCount: Int) -> String {
            "\(sol) SOL · \(tokenCount) tokens"
        }
    }
}

extension SquadDetailTab {
    var title: String {
        switch self {
        case .vaults:
            CosignCopy.Vaults.sectionTitle
        case .proposals:
            CosignCopy.SquadDetail.proposalsTab
        case .activity:
            CosignCopy.SquadDetail.activityTab
        case .members:
            CosignCopy.SquadDetail.membersSection
        }
    }
}
